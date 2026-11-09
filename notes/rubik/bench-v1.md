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

## Version table

| Ver | Change | d11 mean | Note |
|-----|--------|---------:|------|
| **v1** | `s→inv→σ→σ²`; C-style apply; parse `sll` | 824,948 | baseline |
| **v2** | `s→σ→σ²→inv` + macro + `r==0` | 909,588 | regress +10.3% |
| **v2b** | Restore `s→inv`; reuse pos; keep `r0`+macro | 824,914 | fixed order |
| **v3** | PDB stride **1024**; idx=`(a<<10)+o` (C+ASM) | **801,047** | **−2.9% vs v2b**; +31KB pdb |

## Semantics reminder

- Apply: **`mv a6, s4`** then `turns_of[m]` quarters → `Q+16`.
- Parse: **`sll`** when shift amount is a register.
- Hot inv after `h(s)`: scratch pos = `inv.p`; do **not** rebuild after σ.
- PDB: **`idx = (a << 10) + o`** (stride 1024 nibble table).
