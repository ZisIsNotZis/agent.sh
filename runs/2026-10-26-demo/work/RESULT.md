# depsort — dependency-ordering tool

Source: `bin/depsort` (38 lines, executable, bash + awk only — no python, no compiler).

## What it does

Reads whitespace-separated `a b` lines meaning "a needs b" (dependency first), from the
file given as `$1`, or from stdin when the argument is absent or `-`. It prints one valid
build order, one package per line: every dependency appears before the package that needs
it. If the input contains a cycle it prints a single line `cycle: <packages in it>` and
exits 1.

## How it works

- `bin/depsort` is a thin `set -u` bash wrapper that runs a single awk program over
  `${1:--}`, so file argument and stdin take the same path.
- Topological sort is Kahn's algorithm on forward edges `b -> a` (b must be built before
  a). Duplicate lines are deduplicated with the key `b SUBSEP a`, so repeated pairs are
  harmless. Nodes that appear only on the right (dependencies never defined as users) are
  first-class and get emitted. Input order is preserved through an `order[]` array plus a
  `seen` map, so output is deterministic and stable. An empty input yields empty output
  and exit 0.
- On failure (`out != n`) the nodes with `indeg > 0` are still cyclic. The program walks
  the `need[]` edges from the first unresolved node, recording `where[u]` and `path[]`,
  and stops when it revisits a node. It then prints `cycle: ` followed by the slice of
  `path[]` from the first occurrence — so it reports a genuine closed loop, not merely the
  set of stuck nodes.

## Proving command

Generator and independent oracle live beside the tool: `gen.sh SEED` writes a random case
(2–9 packages, random pairs, ~1 in 3 duplicated pairs, ~1 in 4 with an injected cycle of
length 2–4), and `check.sh CASE_FILE BIN` validates the tool's output with a three-colour
recursive DFS — deliberately a different algorithm from the Kahn sort under test. For a
cycle case it requires exit 1, a `cycle:` prefix, that every consecutive pair in the
reported loop is a real edge, and that the last name needs the first (loop closed). For an
acyclic case it requires exit 0, every name exactly once, and position(dep) <=
position(user) for every edge.

The 300-case sweep was run as one backgrounded bash loop over seeds 1..300:

    bgrun -n 300-case-run bash -c 'loop over seeds 1..300: gen.sh $s > logs/cases/case_$s.in; check.sh logs/cases/case_$s.in bin/depsort >> logs/run300.log; done; echo RUN-DONE >> logs/run300.log'

and the logs were then read with:

    cat logs/run300.log

(301 lines: 300 verdicts plus RUN-DONE; long output truncates to the last 100 lines with
a `[truncated: total 301 lines ... full output at .../raw/13.raw]` header, and the full
file was read from there.)

## Measured results

- **300 generated cases: 300 PASS, 0 FAIL.**
- Split by verdict: 247 `PASS cycle-valid`, 53 `PASS valid-order`.
- Every case file is kept as evidence under `logs/cases/case_1.in … case_300.in`; the
  raw verdict log is `logs/run300.log`.
- Pre-flight coverage run over 30 seeds: 23 cyclic, 7 acyclic, 0 failures.
- Four named edge cases, all passing:
  - `e_empty` (empty input) -> `PASS valid-order` (no output, exit 0)
  - `e_rep` (`a b` twice, then `b a`) -> `PASS cycle-valid`
  - `e_short` (single token line `solo`) -> `PASS valid-order`
  - `e_self` (`x x`) -> `PASS cycle-valid`

The numbers above are from the actual runs in this session, not estimates. The tool writes
nothing outside the workspace.
