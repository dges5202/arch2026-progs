# rubik ASM — bench log (v1 →)

Date: 2026-11-09  
Build: `build/rubik/O2` / `impl_asm.o`  
Processor: rv32emu — **`cycle` ≡ `instret` (CPI = 1)**.  
KPI: same 2644 God’s-number-11 states; `get_cycles()` around C then ASM.

## Correctness gate

All listed versions: course ELF **52/52**, d11 bad=0, len agree, ASM wins 2644/2644 vs same-build C `-O2`.

## Depth-11 vs GCC `-O2`

C also switched to stride-1024 in **v3**, so the C column moves with that row.

| Metric | C v1/v2b | ASM **v2b** | C **v3** | ASM **v3** |
|--------|--------:|------------:|---------:|-----------:|
| **sum** | 4,730,319,280 | 2,181,073,908 | 4,607,051,860 | **2,117,968,869** |
| **mean** | **1,789,077** | **824,914** | **1,742,455** | **801,047** |
| min | 698,463 | 334,844 | 680,283 | 325,133 |
| p50 | 1,646,624 | 756,388 | 1,603,712 | 734,806 |
| max | 9,923,162 | 4,545,966 | 9,664,682 | 4,418,175 |
| vs same-row C | — | 2.17× | — | **2.18×** |
| vs ASM v2b | — | — | — | **−2.9%** |

Bisect (v2 regress):

| Ver | d11 mean | Note |
|-----|----------:|------|
| v2 | 909,588 | bad order `s→σ→σ²→inv` |
| v2−r0 / v2−macro | ≈909,588 | not the cost |
| v2b | 824,914 | restore `s→inv`; reuse pos |

Logs: `d11_cmp_*_v1/v2/v2b/v3.txt`.

## Course harness (6 mixed depths)

| impl | cycles | note |
|------|-------:|------|
| C `-O2` v2b | 331,049 | stride 729 |
| C `-O2` **v3** | **322,553** | stride 1024 |
| ASM v2b | 156,924 | — |
| ASM **v3** | **152,523** | **−2.8% vs v2b** |

## Footprint

| object | `.text` | tables / data | text+data ≤128KiB |
|--------|--------:|--------------:|:-----------------:|
| C `O2/impl.o` v3 | (in ELF) | pdb 107520 + arank | **110,298** ok |
| ASM `impl_asm.o` v2b | 3180 | 77423 | 80,603 |
| ASM `impl_asm.o` **v3** | **2892** | **108398** | **111,290** ok |
| ASM `impl_asm.o` **v4a** | **2980** | **108398** | **111,378** ok |
| ASM `impl_asm.o` **v4b** | **2876** | **108398** | **111,274** ok |
| ASM `impl_asm.o` **v5b** | 2808 | 108398 | 111,206 ok |
| ASM `impl_asm.o` **v5c1** | **2788** | **108405** | **111,193** ok |

## Version table

| Ver | Change | d11 mean | Note |
|-----|--------|---------:|------|
| **v1** | `s→inv→σ→σ²`; C-style apply; parse `sll` | 824,948 | baseline |
| **v2** | `s→σ→σ²→inv` + macro + `r==0` | 909,588 | regress +10.3% |
| **v2b** | Restore `s→inv`; reuse pos; keep `r0`+macro | 824,914 | fixed order |
| **v3** | PDB stride **1024**; idx=`(a<<10)+o` (C+ASM) | 801,047 | −2.9% vs v2b |
| **v4a** | `turns==1` fast path parent→`Q+16` | 801,022 | ≈v3; A/B record |
| **v4b** | Sibling 1q via `from_off` (always 1 quarter) | **685,295** | **−14.5% vs v3**; 2.54× vs C |
| **v5a** | Pin `a3=&sig`, walk `a4`; drop per-view `li s1,9` | **681,242** | −0.59% vs v4b |
| **v5b** | σ/σ² pack-while-scatter; drop 7-scan index | **660,887** | **−3.0% vs v5a**; 2.64× vs C |
| **v5c1** | Hot `%3` → `mod3tab` (`a7` pin) | **664,235** | emu **+0.51%** vs v5b; 5ST wins |

## Ripes 5-stage (`RV32_5S`) — d11 min/max samples

Tool: Ripes continuous CLI (`--mode cli --proc RV32_5S --cycles --iret --cpi`).  
Workload: one `rubik_solve_asm(state)` then exit (not the course harness).  
States: emu min `75346122133133`, emu max `14325671111111`.  
Artifacts: [`results/ripes_5s/`](results/ripes_5s/) (`summary.csv`, per-run JSON).  
v1 ELF = commit `70ba7d0` + parse `sll` fix (as measured baseline).

| Ver | role | cycles | instret | CPI | IPC |
|-----|------|-------:|--------:|----:|----:|
| **v1** | min | 442,606 | 328,717 | 1.346 | 0.743 |
| **v1** | max | 5,799,763 | 4,315,401 | 1.344 | 0.744 |
| **v2b** | min | 451,668 | 334,854 | 1.349 | 0.741 |
| **v2b** | max | 6,125,417 | 4,545,976 | 1.347 | 0.742 |
| **v3** | min | 441,957 | 325,143 | 1.359 | 0.736 |
| **v3** | max | 5,997,626 | 4,418,185 | 1.357 | 0.737 |
| **v4b** | min | 380,735 | 280,068 | 1.359 | 0.736 |
| **v4b** | max | 5,121,231 | 3,775,057 | 1.357 | 0.737 |
| **v5a** | min | 379,044 | 278,377 | 1.362 | 0.734 |
| **v5a** | max | 5,099,017 | 3,752,843 | 1.359 | 0.736 |
| **v5b** | min | 362,214 | 269,503 | 1.344 | 0.744 |
| **v5b** | max | 4,878,632 | 3,636,640 | 1.342 | 0.745 |
| **v5c1** | min | **355,179** | 270,619 | **1.312** | 0.762 |
| **v5c1** | max | **4,789,550** | 3,651,025 | **1.312** | 0.762 |

Takeaway: v4b was the big apply win; v5b cuts index scans; **v5c1 mod3tab** trades a bit of emu instret for lower 5ST CPI/cycles. Judge CPI steps on Ripes.

## Semantics reminder

- Apply **v4b**: always 1 quarter; `src = Q + from_off[m]`; sibling uses scratch then copy to `Q+16`.
- Parse: **`sll`** when shift amount is a register.
- Hot inv after `h(s)`: scratch pos = `inv.p`; do **not** rebuild after σ.
- PDB: **`idx = (a << 10) + o`** (stride 1024 nibble table).
- **v5a**: `a3=&sig` pinned; heuristic walk = `a4`; `s1` stays MOVES.
- **v5b**: while scattering `y.p`/`z.p`, fold cubie 0|3|6 dest into `a2` pack; `mv t6,a2` → arank (no 7-scan).
- **v5c1**: pin `a7=&mod3tab`; apply/inv/σ·σ² ori use `lbu` instead of `%3` branch loops.

## GCC disasm tips / why C loses (checklist)

Disasm: `objdump -d -M no-aliases build/rubik/O2/impl.o` (helpers `h_pos3ori`, `sym3`, `heuristic`, `rubik_solve`).

| Tip | Note |
|-----|------|
| Nibble shift | GCC: `slli x,idx,2; andi x,x,4` ≡ `(idx&1)<<2` in one fewer insn than `andi 1; slli 2`. Noted on `PDB_NIBBLE`; not applied yet. |
| `%3` | GCC uses `bgeu`/`addi -3`/`bltu` subtract loop — **no table**. `mod3tab` is our v5.4 idea for 5ST CPI, not copied from GCC. |
| Calls | `-O2`: `h_pos3ori` / `sym3` stay separate (`jalr`). `-O3`: both **inlined into `heuristic`**; `.text` 2108 → 3412. |
| Search | C `search()` is already an **explicit loop** (not recursion). Cost is still stack frame + spills around `heuristic` / helpers, and **no waterfall** (every child pays all four views). |

Harness (6 cases, rv32emu):

| C opt | C cycles | ASM (same ELF) | C/ASM |
|------:|---------:|---------------:|------:|
| `-O2` | 322,553 | 130,979 | 2.46× |
| `-O3` | **246,708** (−23.5% vs O2) | 130,962 | **1.88×** |

d11 mean (2644): C `-O2` 1,742,455 → C `-O3` **1,329,330** (−23.7%); ASM v5a **681,242** still **1.95×** vs O3. So inlining helps C a lot, but waterfall + pinned regs + sibling apply remain the larger gap.



