# rubik ASM — bench log (v1 →)

Date: 2026-11-09  
Build: `build/rubik/O2` / `impl_asm.o`  
Processor: rv32emu — **`cycle` ≡ `instret` (CPI = 1)**.  
KPI: same 2644 God’s-number-11 states; `get_cycles()` around C then ASM.

## Correctness gate (each version)

| Check | v1 | v2 |
|-------|:--:|:--:|
| Course ELF micro-tests | 52/52 | 52/52 |
| ASM d11 bad / len disagree | 0 / 0 | 0 / 0 |
| Pairwise ASM faster than C `-O2` | 2644/2644 | 2644/2644 |

C full-space vs BFS (once, C only): ok=3674160 bad=0.

## Depth-11 vs GCC `-O2`

| Metric | C `-O2` | ASM **v1** | ASM **v2** | v2 / v1 |
|--------|--------:|-----------:|-----------:|--------:|
| **sum cycles** | 4,730,319,280 | 2,181,163,337 | 2,404,949,745 | 1.103× |
| **mean** | **1,789,077** | **824,948** | **909,588** | **+10.3%** |
| min | 698,463 | 335,671 | 367,057 | — |
| p50 | 1,646,624 | 756,750 | 827,801 | — |
| p90 | 2,546,822 | 1,181,734 | 1,317,066 | — |
| p99 | 4,149,808 | 2,031,729 | 2,249,240 | — |
| max | 9,923,162 | 4,541,102 | 5,060,746 | — |
| vs C mean | 1.00× | **2.17× faster** | **1.97× faster** | regression |

Logs: `results/d11_cmp_cO2_vs_asm_v1.txt`, `results/d11_cmp_cO2_vs_asm_v2.txt`.

## Course harness bench (6 mixed depths 0/2/4/6/8/9)

| impl | cycles | vs C | vs ASM v1 |
|------|-------:|-----:|----------:|
| C `-O2` | 331,049 | 1.00× | — |
| ASM v1 | 162,382 | 0.490× | 1.00× |
| ASM v2 | 173,528 | 0.524× | **+6.9%** |

## Footprint

| object | `.text` | tables / data |
|--------|--------:|--------------:|
| C `O2/impl.o` | 2144 | `.rodata` 77165 |
| ASM v1 `impl_asm.o` | 3120 | `.data` 77423 |
| ASM v2 `impl_asm.o` | 3208 | `.data` 77423 |

## Version table

| Version | Change | d11 mean | vs `-O2` | 5ST | Note |
|---------|--------|---------:|---------:|----:|------|
| **v1** | IDA* + waterfall `s→inv→σ→σ²`; C-style apply; parse `sll` | 824,948 | 2.17× | *TBD* | baseline |
| **v2** | Reorder `s→σ→σ²→inv`; `PDB_NIBBLE` macro; `r==0` gate | 909,588 | 1.97× | *TBD* | **regress vs v1**; keep for A/B; next measure each micro-step |

## What v2 changed (code)

1. Hot `heuristic_core` view order: **s → σ → σ² → inv** (σ² reuses y).
2. Shared `.macro PDB_NIBBLE` for `a*729+o` nibble load + prune (`li s1,9` kept in macro).
3. **`r==0`**: identity → `found`; unsolved → `search_top` (align C; no bare push).

## Lesson

Bundling reorder + macro + `r==0` without a mid-step d11 measure hid which piece cost the +10%. From here: **measure after each small edit**.

## Semantics reminder

- Apply: **`mv a6, s4`** then `turns_of[m]` quarters → `Q+16` (not HW1 `from_off`).
- Parse: **`sll`** when shift amount is a register.
