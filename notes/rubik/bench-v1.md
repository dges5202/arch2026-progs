# rubik ASM — bench log (v1 →)

Date: 2026-11-09  
Build: `build/rubik/O2` / `impl_asm.o`  
Processor: rv32emu — **`cycle` ≡ `instret` (CPI = 1)**.  
KPI: same 2644 God’s-number-11 states; `get_cycles()` around C then ASM.

## Correctness gate

| Check | v1 | v2 | v2−r0 | v2−macro |
|-------|:--:|:--:|:-----:|:--------:|
| Course ELF 52/52 | ok | ok | ok | ok |
| d11 bad / len disagree | 0/0 | 0/0 | 0/0 | 0/0 |
| ASM wins vs C `-O2` | 2644 | 2644 | 2644 | 2644 |

C full-space vs BFS (once): ok=3674160 bad=0.

## Depth-11 vs GCC `-O2`

| Metric | C `-O2` | ASM **v1** | ASM **v2** | **v2−r0** | **v2−macro** |
|--------|--------:|-----------:|-----------:|----------:|-------------:|
| **sum** | 4,730,319,280 | 2,181,163,337 | 2,404,949,745 | 2,405,050,698 | **2,404,949,745** |
| **mean** | **1,789,077** | **824,948** | **909,588** | **909,626** | **909,588** |
| min | 698,463 | 335,671 | 367,057 | 367,927 | 367,057 |
| p50 | 1,646,624 | 756,750 | 827,801 | 828,321 | 827,801 |
| max | 9,923,162 | 4,541,102 | 5,060,746 | 5,055,709 | 5,060,746 |
| vs C | 1.00× | 2.17× | 1.97× | 1.97× | 1.97× |
| vs v1 | — | — | **+10.3%** | **+10.3%** | **+10.3%** |

Logs: `d11_cmp_cO2_vs_asm_v1.txt`, `_v2.txt`, `d11_cmp_v2_nor0.txt`, `d11_cmp_v2_nomacro.txt`.

## Course harness (6 mixed depths)

| impl | cycles | vs v1 |
|------|-------:|------:|
| C `-O2` | 331,049 | — |
| ASM v1 | 162,382 | — |
| ASM v2 / v2−macro | 173,528 | +6.9% |
| ASM v2−r0 | 179,201 | +10.4% |

## Footprint `.text`

| object | size |
|--------|-----:|
| C `O2/impl.o` | 2144 |
| ASM v1 | 3120 |
| ASM v2 / v2−macro | 3208 |

## Version / bisect table

| Ver | Change | d11 mean | Note |
|-----|--------|---------:|------|
| **v1** | `s→inv→σ→σ²`; C-style apply; parse `sll` | 824,948 | baseline |
| **v2** | `s→σ→σ²→inv` + `PDB_NIBBLE` + `r==0` | 909,588 | bundled regress +10.3% |
| **v2−r0** | v2 minus `r==0` gate | 909,626 | **not** the cost |
| **v2−macro** | v2 order + `r0`; nibble **inlined** (`.macro` left unused) | 909,588 | **≡ v2** → macro not the cost |

**Suspect left: waterfall reorder.** Next A/B: restore `s→inv→σ→σ²`, keep inline nibble + `r0`.

## Semantics reminder

- Apply: **`mv a6, s4`** then `turns_of[m]` quarters → `Q+16` (not HW1 `from_off`).
- Parse: **`sll`** when shift amount is a register.
