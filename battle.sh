#!/usr/bin/env bash
# chessbattle — a round-robin tournament of the bots in bots/ via fastchess.
#
#   ./battle.sh [ROUNDS]
#
# Each bots/<name>/bot.conf defines one contestant:
#   name=<display name>
#   cmd=<executable inside this folder>
#   opts=<extra fastchess engine args, space-separated, e.g. option.Hash=128>
#
# Overridable via env: TC (time control), CONCURRENCY, BOOK.
set -euo pipefail
cd "$(dirname "$0")"

TC="${TC:-60+0.5}"               # base+increment seconds, per side
ROUNDS="${1:-${ROUNDS:-2}}"      # N rounds (= N distinct openings) per pairing
CONCURRENCY="${CONCURRENCY:-1}"  # 1: engines often use all cores; parallel games oversubscribe & skew results
BOOK="${BOOK:-openings/book.epd}"
FASTCHESS="./fastchess/fastchess"

[ -x "$FASTCHESS" ] || { echo "fastchess not built at $FASTCHESS" >&2; exit 1; }
[ -f "$BOOK" ]      || { echo "opening book not found at $BOOK" >&2; exit 1; }

# Discover bots from bots/*/bot.conf
engines=()
names=()
for conf in bots/*/bot.conf; do
  [ -e "$conf" ] || continue
  dir="$(dirname "$conf")"
  name="" cmd="" opts=""
  while IFS='=' read -r k v || [ -n "$k" ]; do
    case "$k" in
      name) name="$v" ;;
      cmd)  cmd="$v" ;;
      opts) opts="$v" ;;
      ''|\#*) ;;            # skip blank lines and comments
    esac
  done < "$conf"
  [ -n "$name" ] && [ -n "$cmd" ] || { echo "skip $conf (missing name/cmd)" >&2; continue; }
  bin="$(realpath "$dir/$cmd")"
  [ -x "$bin" ] || { echo "skip $name (no executable at $dir/$cmd)" >&2; continue; }
  engines+=( -engine "cmd=$bin" "name=$name" )
  # shellcheck disable=SC2206  # intentional word-split: opts is a list of args
  [ -n "$opts" ] && engines+=( $opts )
  names+=( "$name" )
done

[ "${#names[@]}" -ge 2 ] || { echo "need >=2 bots in bots/ (found ${#names[@]})" >&2; exit 1; }

run="results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$run"
pgn="$run/games.pgn"
summary="$run/summary.txt"

games=$(( ${#names[@]} * (${#names[@]} - 1) * ROUNDS ))
echo "chessbattle: ${#names[@]} bots [${names[*]}] | round-robin | rounds=$ROUNDS = $games games | tc=$TC | concurrency=$CONCURRENCY"
echo "results -> $run/"
echo

"$FASTCHESS" \
  "${engines[@]}" \
  -each tc="$TC" \
  -openings file="$BOOK" format=epd order=random \
  -tournament roundrobin -rounds "$ROUNDS" -repeat \
  -concurrency "$CONCURRENCY" \
  -pgnout file="$pgn" \
  2>&1 | tee "$summary"

echo
echo "Done. PGN: $pgn  |  summary: $summary"
