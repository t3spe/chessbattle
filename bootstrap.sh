#!/usr/bin/env bash
# Bootstrap chessbattle on a fresh checkout:
#   1. verify the host (Linux / x86-64 / BMI2 + AVX2 — what son_of_anton needs)
#   2. ensure fastchess is built (runs setup-fastchess.sh if missing)
#   3. download the son_of_anton release binary
#   4. configure one son_of_anton bot per playing mode
#   5. set up the chess-eval-scaling bots (reuse a build, else clone + build)
#   6. play a quick game to prove it all works
set -euo pipefail
cd "$(dirname "$0")"

REPO="t3spe/chessbattle"
TAG="v0.1.0"
ASSET="son_of_anton"
MODES="im_too_young_to_die hey_not_too_rough hurt_me_plenty"

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# 1. host check ------------------------------------------------------------
say "Verifying host (son_of_anton needs Linux / x86-64 / BMI2 + AVX2)"
[ "$(uname -s)" = Linux  ] || die "needs Linux (this is $(uname -s))"
[ "$(uname -m)" = x86_64 ] || die "needs x86-64 (this is $(uname -m))"
flags=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null) || die "cannot read /proc/cpuinfo"
for feat in bmi2 avx2; do
  echo "$flags" | grep -qw "$feat" || die "CPU is missing '$feat' (BMI2 + AVX2 are required)"
done
echo "    OK: $(uname -sm), bmi2 + avx2 present"

# 2. fastchess -------------------------------------------------------------
say "Ensuring fastchess is built"
if ! ./fastchess/fastchess --version >/dev/null 2>&1; then
  echo "    not found — building via ./setup-fastchess.sh"
  ./setup-fastchess.sh
fi
./fastchess/fastchess --version >/dev/null 2>&1 || die "fastchess is not working"
echo "    OK: $(./fastchess/fastchess --version 2>&1 | head -1)"

# 3. download son_of_anton -------------------------------------------------
say "Downloading $ASSET ($REPO@$TAG)"
url="https://github.com/$REPO/releases/download/$TAG/$ASSET"
tmp=$(mktemp)
curl -fL --retry 3 -o "$tmp" "$url" || die "download failed: $url"
chmod +x "$tmp"
file "$tmp" | grep -q 'ELF 64-bit' || die "downloaded file is not an ELF binary"
echo "    OK: $(du -h "$tmp" | cut -f1)"

# 4. configure son_of_anton bots -------------------------------------------
say "Configuring son_of_anton bots (one per mode): $MODES"
for m in $MODES; do
  mkdir -p "bots/$m"
  install -m 0755 "$tmp" "bots/$m/$ASSET"
  printf 'name=%s\ncmd=%s\nopts=option.mode=%s\n' "$m" "$ASSET" "$m" > "bots/$m/bot.conf"
  echo "    bots/$m  (mode=$m)"
done
rm -f "$tmp"

# 5. chess-eval-scaling bots -----------------------------------------------
say "Setting up chess-eval-scaling bots (one bot per network)"
# Temporary: track the fork's fix branch (carries the UCI lazy-load fix) until the
# PR lands upstream, then switch back to swarajvatsa @ the merge commit.
CES_REPO="https://github.com/t3spe/chess-eval-scaling"
CES_REF="fix/load-eval-net-on-go"
CES_NETS="eval_tiny:compact_tiny eval_small:compact_small eval_champion:compact_champion eval_wide:compact_wide eval_deep:deep_b4"

# Reuse an existing build (CES_DIR override, sibling checkout, or in-tree);
# otherwise clone the pinned source in-tree and build just the engine target.
ces=""
for cand in "${CES_DIR:-}" "../chess-eval-scaling" "chess-eval-scaling"; do
  if [ -n "$cand" ] && [ -x "$cand/engine/build/engine" ]; then ces="$cand"; break; fi
done
if [ -n "$ces" ]; then
  echo "    reusing build at $ces"
else
  ces="chess-eval-scaling"
  if [ ! -d "$ces/.git" ]; then
    echo "    fetching $CES_REPO @ ${CES_REF:0:12}"
    git init -q "$ces"
    git -C "$ces" remote add origin "$CES_REPO"
    git -C "$ces" fetch -q --depth 1 origin "$CES_REF"
    git -C "$ces" checkout -q --detach FETCH_HEAD
  fi
  echo "    building engine (cmake, Release / -march=native)"
  ( cd "$ces/engine" && cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null && cmake --build build --target engine -j ) \
    || die "chess-eval-scaling build failed"
fi

engine_bin="$(cd "$ces/engine/build" && pwd)/engine"
models_dir="$(cd "$ces/models" && pwd)"
ces_abs="$(cd "$ces" && pwd)"
[ -x "$engine_bin" ] || die "engine not found at $engine_bin"
probe="$(printf 'uci\nquit\n' | "$engine_bin" 2>/dev/null || true)"
echo "$probe" | grep -q '^uciok' || die "chess-eval-scaling engine did not answer 'uci'"
echo "    OK: $engine_bin"

# One bot per network. Each bot launches the engine through a wrapper that runs
# it from the repo dir, so the engine's built-in default EvalFile resolves and
# the match log stays clean (an unpatched engine loads the net at the first
# isready, before setoption EvalFile arrives). Threads = all cores; concurrency stays 1.
ncpu="$(nproc)"
for pair in $CES_NETS; do
  bot="${pair%%:*}"; net="${pair##*:}"
  qbin="$models_dir/$net.qbin"
  [ -f "$qbin" ] || { echo "    skip $bot (missing $net.qbin)"; continue; }
  mkdir -p "bots/$bot"
  rm -f "bots/$bot/engine"          # never write through a stale symlink (would clobber its target)
  cat > "bots/$bot/engine" <<EOF
#!/bin/sh
cd "$ces_abs" && exec "$engine_bin" "\$@"
EOF
  chmod +x "bots/$bot/engine"
  printf 'name=%s\ncmd=engine\nopts=option.EvalFile=%s option.Threads=%s option.Hash=64\n' \
    "$bot" "$qbin" "$ncpu" > "bots/$bot/bot.conf"
  echo "    bots/$bot  (net=$net)"
done

# 6. quick game ------------------------------------------------------------
say "Playing a quick test game (fast) to verify"
read -r a b _ <<<"$MODES"
if out=$(./fastchess/fastchess \
      -engine cmd="$PWD/bots/$a/$ASSET" name="$a" option.mode="$a" \
      -engine cmd="$PWD/bots/$b/$ASSET" name="$b" option.mode="$b" \
      -each tc=2+0.05 -rounds 1 -games 1 \
      -openings file=openings/book.epd format=epd order=random 2>&1); then
  echo "$out" | grep -E '^Finished game' || { echo "$out" | tail -15; die "no game result"; }
else
  echo "$out" | tail -15; die "fastchess game failed"
fi

# 7. offer the full battle -------------------------------------------------
nbots=$(find bots -maxdepth 2 -name bot.conf 2>/dev/null | wc -l)
per_round=$(( nbots * (nbots - 1) ))   # round-robin, each pairing plays both colors
tc=${TC:-60+0.5}
say "Setup verified — $nbots bots ready in bots/"
printf '\nA full battle is a round-robin: %d games per round at tc=%s.\n' "$per_round" "$tc"
printf 'At this time control each game runs a couple of minutes, one at a time.\n\n'
rounds=""
[ -t 0 ] && read -r -p "How many rounds to play now? (enter a number, or just Enter to skip) " rounds
if [[ "$rounds" =~ ^[1-9][0-9]*$ ]]; then
  say "Starting the battle: $rounds round(s) = $(( per_round * rounds )) games at tc=$tc"
  exec ./battle.sh "$rounds"
else
  printf '\nSkipped. Start anytime with:  ./battle.sh [rounds]   (e.g. ./battle.sh 2)\n'
fi
