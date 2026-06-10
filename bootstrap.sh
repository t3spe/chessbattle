#!/usr/bin/env bash
# Bootstrap chessbattle on a fresh checkout:
#   1. verify the host (Linux / x86-64 / BMI2 + AVX2 — what son_of_anton needs)
#   2. ensure fastchess is built (runs setup-fastchess.sh if missing)
#   3. download the son_of_anton release binary
#   4. configure one bot per playing mode
#   5. play a quick game to prove it all works
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

# 4. configure bots --------------------------------------------------------
say "Configuring bots (one per mode): $MODES"
for m in $MODES; do
  mkdir -p "bots/$m"
  install -m 0755 "$tmp" "bots/$m/$ASSET"
  printf 'name=%s\ncmd=%s\nopts=option.mode=%s\n' "$m" "$ASSET" "$m" > "bots/$m/bot.conf"
  echo "    bots/$m  (mode=$m)"
done
rm -f "$tmp"

# 5. quick game ------------------------------------------------------------
say "Playing a quick game to verify"
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

say "Bootstrap complete. Run a tournament with:  ./battle.sh [rounds]"
