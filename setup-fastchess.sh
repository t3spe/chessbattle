#!/usr/bin/env bash
# Fetch and build the fastchess match runner into ./fastchess, pinned to a
# specific commit for reproducibility. Idempotent: re-running rebuilds; delete
# ./fastchess to re-fetch (e.g. after bumping REF).
set -euo pipefail
cd "$(dirname "$0")"

REPO="https://github.com/Disservin/fastchess.git"
# Pinned commit: fastchess alpha 1.8.1 (2026-06-06), a few commits past the
# v1.8.1-alpha tag — pinned so everyone builds the same validated runner.
# Bump deliberately to upgrade.
REF="58072f231dc1ae33204254f867afd0a195f21a2e"
DIR="fastchess"
BIN="$DIR/fastchess"

if [ ! -d "$DIR" ]; then
  echo "==> Fetching fastchess @ ${REF:0:12}"
  git init -q "$DIR"
  git -C "$DIR" remote add origin "$REPO"
  git -C "$DIR" fetch -q --depth 1 origin "$REF"
  git -C "$DIR" checkout -q --detach FETCH_HEAD
else
  echo "==> $DIR already present; rebuilding (delete it to re-fetch/re-pin)"
fi

echo "==> Building (make -j$(nproc))"
make -C "$DIR" -j"$(nproc)"

[ -x "$BIN" ] || { echo "ERROR: build failed — $BIN not found" >&2; exit 1; }
echo "==> OK: $("$BIN" --version 2>&1 | head -1)"
echo "    binary: $DIR/fastchess  (pinned ${REF:0:12})"
