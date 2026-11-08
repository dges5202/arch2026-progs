# Experiment: waterfall order of 4 heuristic views

Date: 2026-11-07  
Machine: WSL2 Linux, 16 threads OpenMP  
Heuristic views (same pos3ori PDB):

| id | name | meaning | build cost |
|----|------|---------|------------|
| 0 | `s` | state as-is | free |
| 1 | `inv` | inverse cubie state | cheap (`invert`) |
| 2 | `σ` | diagonal sym3 once | `sym3(s)` |
| 3 | `σ²` | diagonal twice | `sym3(sym3(s))` |

Search uses **waterfall short-circuit**: evaluate views in a fixed order, keep `run_max = max(...)`, stop as soon as `run_max > r` (prune). Order does **not** change the final `h = max(all four)` when all are evaluated; it only changes how early prune fires and how often expensive transforms run.

Space: `7! × 3^6 = 3,674,160` states. Exact distance from BFS; IDA* must return that length.

---

## Round A — lookup-count sim only (no IDA*)

Tool: ad-hoc `/tmp/scan_ord24` (same math as `notes/rubik/tools/scan_waterfall.c`, extended to 24 perms).

Metric: for every state and every remaining budget `r < M` where `M = max(4 views)`, count how many views are touched until `run_max > r`. Average over all such events.

`events = 28,363,122`

| rank | avg lookups | order |
|------|-------------|-------|
| 1–6 | **1.1275** | any of `{s,σ,σ²}` first three, **`inv` last** |
| 7–12 | ~1.131 | mixed |
| 21–24 | **1.1367** | `s→inv→σ→σ²` and close variants (**σ last**) |

**A takeaway:** if you only count PDB probes, putting `inv` last is best; putting conjugations last is *worst*. Gap is small (~0.8% relative).

---

## Round B — real solve, **independent** σ / σ² builds (historical)

Each view rebuilt from `s` alone (`σ²` = two fresh `sym3`, no reuse). **Superseded by Round C** for implementation advice; kept for comparison.

Tool (older semantics; current source is Round C): same binary path after rebuild historically.

Setup (shared with Round C unless noted):

- Compiler: `gcc -O3 -fopenmp`, 16 OpenMP threads
- Per order: solve all 3,674,160 states; `len == BFS d`
- Timing: `CLOCK_MONOTONIC` wall time
- Round B only: no σ-state cache between views

### Correctness

**All 24 orders:** `ok=3674160 bad=0 fail=0` → `all_orders_correct=yes`.

Order never broke shortest-path correctness in this scan.

### Ranked by wall time

| rank | sec | order |
|------|-----|-------|
| 1 | **2.32** | `s→σ2→σ→inv` |
| 2 | 2.35 | `s→σ→σ2→inv` |
| 3 | 2.36 | `s→σ2→inv→σ` |
| 4 | 2.36 | `s→σ→inv→σ2` |
| 5 | 2.37 | `σ→s→inv→σ2` |
| 6 | 2.37 | `s→inv→σ→σ2` |
| 7 | 2.41 | `σ→inv→s→σ2` |
| 8 | 2.43 | `σ→s→σ2→inv` |
| 9 | 2.48 | `σ→σ2→inv→s` |
| 10 | 2.48 | `σ→σ2→s→inv` |
| 11 | 2.51 | `σ2→σ→s→inv` |
| 12 | 2.51 | `s→inv→σ2→σ` |
| 13 | 2.52 | `σ2→s→σ→inv` |
| 14 | 2.55 | `σ→inv→σ2→s` |
| 15 | 2.59 | `σ2→s→inv→σ` |
| 16 | 2.60 | `σ2→inv→s→σ` |
| 17 | 2.61 | `σ2→inv→σ→s` |
| 18 | 2.62 | `σ2→σ→inv→s` |
| 19 | 2.69 | `inv→s→σ→σ2` |
| 20 | 2.72 | `inv→σ→s→σ2` |
| 21 | 2.73 | `inv→s→σ2→σ` |
| 22 | 2.75 | `inv→σ2→σ→s` |
| 23 | 2.78 | `inv→σ2→s→σ` |
| 24 | **2.87** | `inv→σ→σ2→s` |

Best → worst ≈ **2.32s → 2.87s** (~**+24%**). Round B favored **`s` first**; **`inv` first** was slowest.

---

## Round C — real solve, **chained** σ → σ² (current)

Model matches real code: `σ²` is grown from `σ`.

```text
t  = sym3(s)          # build σ once, cache
hσ = pdb(t)           # always available when entering conj
if run_max > r: prune # can stop before second sym3
t2 = sym3(t)
hσ2 = pdb(t2)
```

If the permutation lists `σ²` **before** `σ`, runtime still does the intermediate `σ` lookup (and may prune) before the second `sym3`; a later `σ` slot is then free (already have `hσ`). Label order ≠ physical build order for that pair.

```bash
gcc -O3 -fopenmp -Isrc/rubik -o /tmp/scan_ord24_real \
    notes/rubik/tools/scan_ord24_real.c
/tmp/scan_ord24_real
```

### Correctness

**All 24:** `ok=3674160 bad=0 fail=0` → `all_orders_correct=yes`.

### Ranked by wall time (chained)

| rank | sec | order (label) |
|------|-----|---------------|
| 1 | **2.45** | `σ2→inv→s→σ` |
| 2 | 2.46 | `σ2→s→inv→σ` |
| 3 | 2.48 | `σ→s→σ2→inv` |
| 4 | 2.49 | `σ2→s→σ→inv` |
| 5 | 2.49 | `σ2→inv→σ→s` |
| 6 | 2.51 | `σ→σ2→inv→s` |
| 7 | 2.54 | `σ→s→inv→σ2` |
| 8 | 2.54 | `σ2→σ→s→inv` |
| 9 | 2.56 | `s→σ2→inv→σ` |
| 10 | 2.56 | `σ2→σ→inv→s` |
| 11 | 2.56 | `σ→inv→s→σ2` |
| 12 | 2.57 | `σ→σ2→s→inv` |
| 13 | 2.62 | `s→σ2→σ→inv` |
| 14 | 2.65 | `σ→inv→σ2→s` |
| 15 | 2.66 | `inv→s→σ→σ2` |
| 16 | 2.67 | `s→inv→σ2→σ` |
| 17 | 2.67 | `inv→s→σ2→σ` |
| 18 | 2.69 | `s→σ→inv→σ2` |
| 19 | 2.69 | `s→inv→σ→σ2` |
| 20 | 2.70 | `inv→σ2→s→σ` |
| 21 | 2.71 | `inv→σ→s→σ2` |
| 22 | 2.71 | `s→σ→σ2→inv` |
| 23 | 2.72 | `inv→σ2→σ→s` |
| 24 | **2.75** | `inv→σ→σ2→s` |

Best → worst ≈ **2.45s → 2.75s** (~**+12%**, tighter than Round B).

**C takeaway:**

- Top ranks mostly **enter the conjugation chain early** (`σ` or `σ2` first in the label ≈ pay `sym3` + `hσ` soon, often prune before `inv` / second `sym3`).
- Label `σ2→…→σ` is not “skip σ”; it means “start conj chain now, σ lookup happens inside.”
- `s→inv→σ→σ2` lands mid/slow (2.69s, rank 19) once chaining is modeled — cheap views first delay the strong conj prune.
- `inv` first still tends to the bottom half.

---

## Round D — scratch / register pressure (RV32-relevant)

Concern: if conj runs first, a scratch state lives across several prune checks while `child` must stay intact for `state[g+1] = child`. RV32I + 4 KiB stack — is that a problem?

### Peak live data (serialized views)

| live value | size | notes |
|------------|------|-------|
| IDA `state[0..11]` | 12 × 14 B ≈ **168 B** | search stack |
| `child` | 14 B | must not clobber until accept |
| **one** scratch | 14 B | reused for `inv` **or** `σ`→`σ²` (overwrite) |
| scalars | `g,r,bound,path,next,…` | a handful of regs / words |

**Peak scratch is still one `state_t`**, not four. Four waterfall checks do not need four copies if views run one after another and share the same buffer. σ² overwrites / continues from σ’s scratch; afterward inv can reuse the same 14 B.

So the issue is less “不夠放” (168+14+14 ≪ 4 KiB), more **hot-path 要不要每次都碰 scratch / `sym3`**（暫存器壓力、spill、指令數）。

### How often scratch is touched (full-space IDA*, chained model)

Tool: `notes/rubik/tools/scan_prune_pressure.c`  
Same search tree for all orders (`prune_calls` identical) — only work inside prune changes.

| order (label) | only_s_prune | scratch_used | did_sym1 | did_sym2 | wall (instr.) |
|---------------|-------------:|-------------:|---------:|---------:|---------------|
| `s→inv→σ→σ2` | **52.6%** | **47.4%** | 30.6% | 22.5% | 3.42s |
| `s→σ→σ2→inv` | **52.6%** | **47.4%** | 47.4% | 29.0% | 4.16s |
| `s→σ2→σ→inv` | **52.6%** | **47.4%** | 47.4% | 29.0% | 3.34s |
| `σ2→inv→s→σ` (C #1) | **0%** | **100%** | **100%** | 47.3% | 2.95s |
| `σ→s→σ2→inv` (C #3) | **0%** | **100%** | **100%** | 29.0% | 5.07s |

(`s` first ≈ half of all prune calls return after one PDB read on `child` — **zero scratch**.)

### ASM-oriented reading

1. **空間**：一份 scratch 夠；不必為「四次判斷」留四份狀態。
2. **壓力**：`σ`/`σ2` 開頭 ⇒ **每次** prune 都 `sym3` + scratch 活著；`s` 開頭 ⇒ **一半**呼叫連 scratch 都不開。
3. Round C host 上 conj-first 可稍快，是因為 x86 有很多暫存器、`sym3` 相對便宜；**RV32 ASM 更可能被「100% scratch」打臉**，`s` 優先較穩。
4. 實作折衷：**`s` 先**（常免費剪枝）→ 再 **一條** `σ→σ²` 鏈（同 scratch）→ 再 `inv`（同 scratch）。可讀且對暫存器友善；若 guest cycle 顯示 conj 更值，再對調。

---

## Round E — full-space node visits (current `rubik.c` heuristic)

Heuristic identical to `src/rubik/rubik.c`: `h = max(h(s), h(inv), h(σ), h(σ²))` with σ² chained from σ; **no** waterfall short-circuit (every `h_eval` pays all four views).

Definitions (one IDA* solve):

| counter | meaning |
|---------|---------|
| `gen` | children after `apply` (same-face move skip happens first) |
| `h_eval` | `heuristic()` calls in search (`h > r` tests) |
| `expand` | nodes pushed on the IDA* stack (survived prune) |
| `iters` | `search()` invocations (bound iterations) |

Waterfall order does **not** change `gen` / `expand` / `iters` (same prune decisions); it only changes work per `h_eval`.

```bash
gcc -O3 -fopenmp -Isrc/rubik -o /tmp/scan_nodes notes/rubik/tools/scan_nodes.c
/tmp/scan_nodes
```

### Correctness

`ok=3674160 bad=0 fail=0` (length == BFS distance). Wall ≈ 4.3s (16 threads).

### Totals over all states

| metric | sum | avg / state |
|--------|-----|-------------|
| `gen` | 412,472,509 | **112.263** |
| `h_eval` | 399,567,906 | **108.751** |
| `expand` | 72,808,687 | **19.816** |
| `iters` | 7,480,425 | **2.036** |

### By exact distance

| d | count | avg_gen | avg_h_eval | avg_expand | avg_iters | max_gen | max_expand |
|---|------:|--------:|-----------:|-----------:|----------:|--------:|-----------:|
| 0 | 1 | 0.000 | 0.000 | 0.000 | 0.000 | 0 | 0 |
| 1 | 9 | 5.000 | 0.000 | 0.000 | 1.000 | 9 | 0 |
| 2 | 54 | 8.500 | 5.000 | 1.000 | 1.000 | 15 | 1 |
| 3 | 321 | 11.981 | 8.486 | 2.000 | 1.000 | 21 | 2 |
| 4 | 1847 | 15.592 | 12.091 | 3.015 | 1.006 | 36 | 5 |
| 5 | 9992 | 18.982 | 15.483 | 4.016 | 1.001 | 34 | 5 |
| 6 | 50136 | 22.481 | 18.974 | 5.026 | 1.005 | 50 | 7 |
| 7 | 227536 | 26.626 | 23.114 | 6.102 | 1.040 | 87 | 14 |
| 8 | 870072 | 38.968 | 35.454 | 8.156 | 1.345 | 298 | 48 |
| 9 | 1887748 | 97.481 | 93.970 | 17.269 | 2.147 | 997 | 166 |
| 10 | 623800 | 294.500 | 290.985 | 49.461 | 3.122 | 3387 | 559 |
| 11 | 2644 | **1297.528** | **1294.043** | **216.020** | **4.071** | **7185** | **1194** |

**E takeaway:** hardest states are d=11 (2644 of them): ~1.3k generated / ~216 expanded on average; worst case max_gen=7185, max_expand=1194. Overall tree is small vs naive IDA* — 4-way pos3ori keeps avg expand ≈ 20 / state.

---

## Conclusions

1. **σ² 從 σ 長出**；中間必查 σ，可在第二次 `sym3` 前 prune。
2. Host Round C 偏好早進 conj；**不算 scratch 熱度**。
3. Round D：peak 只需 **1×14 B scratch**；但 conj-first ⇒ **100%** prune 碰 scratch，`s`-first ⇒ **~53%** 只靠 `s` 剪掉。
4. **ASM 建議預設 `s` 開頭 + 共用 scratch 的 conj 鏈**；Round C 名次當參考，不以 x86 wall time 鎖死順序。
5. Round E：現行 C 啟發式全空間 avg **expand ≈ 19.8**、d=11 avg **expand ≈ 216**（max 1194）。
6. 量的是 host 統計 / wall time，不是 RV32 `cycle`；定稿前用 guest / Ripes 抽樣。

---

## Related tools

| file | role |
|------|------|
| `notes/rubik/tools/scan_shortest.c` | BFS vs `rubik_solve` full-space length check |
| `notes/rubik/tools/scan_waterfall.c` | early lookup-count sim |
| `notes/rubik/tools/scan_ord24_real.c` | Round C — 24 orders, chained, wall time |
| `notes/rubik/tools/scan_prune_pressure.c` | Round D — scratch / how far prune walks |
| `notes/rubik/tools/scan_nodes.c` | Round E — full-space gen / h_eval / expand |
