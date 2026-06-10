# UCI support required by chessbattle

A bot communicates over stdin/stdout using [UCI](https://backscattering.de/chess/uci/).
The harness (fastchess) sends the commands in the first table; your bot must
produce the responses in the second. That is the whole contract.

Lines are newline-terminated text: commands arrive on **stdin**, responses go to
**stdout**.

## Commands the bot must handle (harness → bot)

| command | meaning | required response |
|---|---|---|
| `uci` | start handshake | `id name <name>`, `id author <author>`, any `option name ...` lines, then `uciok` |
| `isready` | sync / ping | `readyok` once ready |
| `ucinewgame` | a new game is starting | — |
| `position startpos [moves <m1> <m2> ...]` | set position from the start | — |
| `position fen <FEN> [moves <m1> ...]` | set position from a FEN | — |
| `go wtime <ms> btime <ms> winc <ms> binc <ms>` | search with the given clock | `bestmove <move>` when done |
| `stop` | stop searching now | `bestmove <move>` promptly |
| `setoption name <id> value <v>` | set an option you advertised | — |
| `quit` | shut down | exit the process |

## Responses the bot must produce (bot → harness)

| response | when |
|---|---|
| `id name <name>` and `id author <author>` | after `uci` |
| `option name <id> type <type> ...` | after `uci`, once per option you expose |
| `uciok` | end of the `uci` handshake |
| `readyok` | after every `isready` |
| `bestmove <move>` | when a `go` finishes, or in response to `stop` |

Moves are long algebraic notation: `e2e4`, `g1f3`, `e7e8q` (promotion suffix `q`,
`r`, `b`, or `n`); castling is the king's move, e.g. `e1g1`.

A bot that implements these two tables runs in chessbattle. See
[README.md](README.md) for how to register it.
