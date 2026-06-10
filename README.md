# chessbattle

Make 2 or more chess engines fight. A small **round-robin tournament harness for
UCI engines** — drop bots into `bots/`, run `./battle.sh`, get a cross-table with
ratings. Matches are played by [fastchess](https://github.com/Disservin/fastchess)
under the hood; this repo is the thin layer that discovers the bots, runs the
tournament, and records the results.

## Quick start

```sh
git clone git@github.com:t3spe/chessbattle.git
cd chessbattle
./bootstrap.sh      # check host, build fastchess, fetch a sample bot, play a test game
./battle.sh 5       # run a 5-round round-robin of everything in bots/
```

Output lands in `results/<timestamp>/` — `games.pgn` plus a `summary.txt` with the
cross-table and Elo (± error).

## What `bootstrap.sh` does

1. Checks the host is compatible (Linux / x86-64 / required CPU features).
2. Builds fastchess if needed (via `setup-fastchess.sh`).
3. Downloads the **son_of_anton** sample bot from this repo's releases and sets up
   a few contestants from it.
4. Plays one quick game to confirm everything works.

That download is the only place a specific engine is involved — chessbattle itself
is engine-agnostic.

## Adding a bot

A contestant is a folder under `bots/` holding the engine binary and a `bot.conf`:

```
bots/
└── mybot/
    ├── mybot          # the engine executable
    └── bot.conf
```

`bot.conf` is plain `key=value`:

```
name=mybot             # display name in the results
cmd=mybot              # the executable inside this folder
opts=option.Hash=128   # optional: extra UCI options, space-separated (e.g. option.Threads=2)
```

Any engine that speaks the minimal UCI subset works — see **[UCI.md](UCI.md)** for
exactly what a bot must support.

## Running tournaments

```sh
./battle.sh [ROUNDS]   # round-robin; each pairing plays ROUNDS rounds × 2 games (both colors)
```

Tunable via environment variables:

| var | default | meaning |
|---|---|---|
| `TC` | `60+0.5` | time control — `base+increment` seconds per side |
| `CONCURRENCY` | `1` | how many games run in parallel |
| `BOOK` | `openings/book.epd` | opening book for varied, fair starts |

Openings matter: deterministic engines from the start position replay the same
game, so games begin from a balanced opening book — each opening played once with
each color, which also cancels White's first-move advantage.

## Requirements

- Linux with `bash`, `curl`, and `git`
- A C++ toolchain (`cmake` / `make` / `g++`) so `setup-fastchess.sh` can build the runner
- Whatever each bot binary itself requires at runtime

## Layout

```
battle.sh            run a tournament
bootstrap.sh         one-shot setup: host check → fastchess → sample bot → test game
setup-fastchess.sh   fetch + build the fastchess runner (pinned commit)
openings/book.epd    opening book
UCI.md               the UCI commands a bot must support
bots/                contestants — one folder each (not committed)
results/             tournament output (not committed)
fastchess/           the built runner (not committed)
```
