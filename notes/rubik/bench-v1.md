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
| ASM `impl_asm.o` **v5c13** | **2736** | **108405** | **111,141** ok |

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
| **v5c2** | `r≠0` fall into waterfall; `r0_id` cold | **664,235** | emu ≡ v5c1; 5ST **−0.3%** |
| **v5c3** | PDB nibble `slli; andi 4` (hot macro + root) | **664,235** | **≡ v5c2** (wash) |
| **v5c4** | `apply_1q` LU schedule (dest / `&twist` fills) | **664,235** | emu ≡; 5ST **−1.0%** |
| **v5c5** | pos-build: bump `a4` between `lbu p` and use | **664,235** | emu ≡; 5ST **−1.0%** vs v5c4 |
| **v5c6** | Sibling copy 4×`lw`/`sw` (was byte loop) | **597,951** | **−10.0% vs v5c5**; **2.91×** vs C |
| **v5c7** | `no_prev` via `s6+27`/`+24` (drop hot `la`) | **594,058** | **−0.65% vs v5c6**; **2.93×** vs C |
| **v5c8** | `inv_o` LU: `addi` + `slli a6` fills (keep `t6=a`) | **594,058** | emu ≡; **5ST ~−1.0%** vs v5c7 |
| **v5c9** | σ/σ² `p_build`: interleave `&sig[i]` in `a0` | **594,058** | emu ≡; **5ST ~−0.7%** vs v5c8 |
| **v5c10** | σ/σ² `o_build`: `a6` + overlap `kk`/`sig` | **589,145** | **−0.83%** emu; **5ST ~−4%**; `.text` 2772 |
| **v5c11** | `.balign 16` `states`/`scratch`; `.data` `ALIGN(4)` | **589,145** | hygiene; KPI ≡ v5c10 |
| **v5c12** | `no_prev`: `addi Q+16` fills `from_off→a6` | **589,145** | emu ≡; **5ST ~−0.17%** |
| **v5c13** | Drop post-push `solve_loop` id; `j child` | **588,089** | **−0.18%** emu; **5ST ~−0.2%**; `.text` 2736 |

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
| **v5c1** | min | 355,179 | 270,619 | 1.312 | 0.762 |
| **v5c1** | max | 4,789,550 | 3,651,025 | 1.312 | 0.762 |
| **v5c2** | min | 354,181 | 270,619 | 1.309 | 0.764 |
| **v5c2** | max | 4,775,204 | 3,651,025 | 1.308 | 0.765 |
| **v5c3** | min | 354,181 | 270,619 | 1.309 | 0.764 |
| **v5c3** | max | 4,775,204 | 3,651,025 | 1.308 | 0.765 |
| **v5c4** | min | 350,618 | 270,619 | 1.296 | 0.772 |
| **v5c4** | max | 4,724,909 | 3,651,025 | 1.294 | 0.773 |
| **v5c5** | min | 347,090 | 270,619 | 1.283 | 0.780 |
| **v5c5** | max | 4,674,656 | 3,651,025 | 1.280 | 0.781 |
| **v5c6** | min | **312,585** | 244,824 | **1.277** | 0.783 |
| **v5c6** | max | **4,181,698** | 3,282,503 | **1.274** | 0.785 |
| **v5c7** | min | **311,058** | 243,297 | **1.279** | 0.782 |
| **v5c7** | max | **4,160,143** | 3,260,948 | **1.276** | 0.784 |
| **v5c8** | min | **307,878** | 243,297 | **1.265** | 0.790 |
| **v5c8** | max | **4,124,035** | 3,260,948 | **1.265** | 0.791 |
| **v5c9** | min | **305,736** | 243,297 | **1.257** | 0.796 |
| **v5c9** | max | **4,095,986** | 3,260,948 | **1.256** | 0.796 |
| **v5c10** | min | **292,884** | 241,155 | **1.215** | 0.823 |
| **v5c10** | max | **3,927,692** | 3,232,899 | **1.215** | 0.823 |
| **v5c11** | min | **292,884** | 241,155 | **1.215** | 0.823 |
| **v5c11** | max | **3,927,692** | 3,232,899 | **1.215** | 0.823 |
| **v5c12** | min | **292,375** | 241,155 | **1.212** | 0.825 |
| **v5c12** | max | **3,920,507** | 3,232,899 | **1.213** | 0.825 |
| **v5c13** | min | **291,826** | 240,735 | **1.212** | 0.825 |
| **v5c13** | max | **3,911,647** | 3,226,279 | **1.212** | 0.825 |

Takeaway: v4b was the big apply win; v5b cuts index scans; **v5c1–c2** CPI/layout; **v5c3** nibble ≡; **v5c4–c5** LU fills (~1% each) at flat emu; **v5c6** word sibling copy **−10%** emu and 5ST (six of nine moves hit scratch→`Q+16`); **v5c7** kills hot `la` (−0.65% emu); **v5c8–c10** LU/interleave; **v5c11** align; **v5c12** `no_prev` LU **5ST ~−0.17%**; **v5c13** drops dead post-push id (**−0.18%** emu / **5ST ~−0.2%**). Judge CPI on Ripes.

## Semantics reminder

- Apply **v4b**: always 1 quarter; `src = Q + from_off[m]`; sibling uses scratch then copy to `Q+16`.
- Parse: **`sll`** when shift amount is a register.
- Hot inv after `h(s)`: scratch pos = `inv.p`; do **not** rebuild after σ.
- PDB: **`idx = (a << 10) + o`** (stride 1024 nibble table).
- **v5a**: `a3=&sig` pinned; heuristic walk = `a4`; `s1` stays MOVES.
- **v5b**: while scattering `y.p`/`z.p`, fold cubie 0|3|6 dest into `a2` pack; `mv t6,a2` → arank (no 7-scan).
- **v5c1**: pin `a7=&mod3tab`; apply/inv/σ·σ² ori use `lbu` instead of `%3` branch loops.
- **v5c2**: `beqz s3, r0_id_path`; common `r≠0` falls into waterfall (identity check is cold).
- **v5c3**: nibble extract `slli t4,idx,2; andi t4,t4,4` in `PDB_NIBBLE` and root heuristic (≡ old `andi 1; slli 2`).
- **v5c4**: `apply_1q` — `add dest` fills from→use; `add &twist` fills p→sb; twist `lbu` fills o→add.
- **v5c5**: `loop_heuristic_core_p` — `addi a4` between `lbu p` and `add` (LU fill).
- **v5c6**: `apply_sw_loop` — 4×`lw`/4×`sw` scratch→`Q+16` (was 14× byte loop ≈84 insn).
- **v5c7**: `no_prev` — `&source[face]`/`&twist[face]` from pinned `s6` (`+27` / `source+24`); drop per-child `la` pair.
- **v5c8**: `loop_heuristic_core_inv_o` — `addi t0` after `lbu i`; `slli a6,t4,1` fills `lbu s.o→sub` (do not clobber `t6=a`).
- **v5c9**: `sym_p_build` / `sym2_p_build` — `add a0,t0,a3` fills `p→use`; `lbu a0` interleaves with `lbu value`.
- **v5c10**: `sym_o_build` / `sym2_o_build` — `a6=&sig[i]`; overlap `kk[i]`/`sig[i]`; stores `y.o@+7` / `z.o@+21`.
- **v5c11**: `.balign 16` before `states` (covers `scratch`); `common/linker.ld` `.data` starts `ALIGN(4)`.
- **v5c12**: `no_prev` — `addi a0,s4,16` between `lbu from_off` and `add a6`.
- **v5c13**: push ends `j child` (drop `solve_loop` identity); solved only via `r0_id_path`.

## GCC vs ASM — CPI vs instruction count

Disasm: `objdump -d -M no-aliases build/rubik/O{2,3}/impl.o`.

### Same samples on Ripes `RV32_5S` (min `7534…` / max `1432…`)

| | min cycles | CPI | max cycles | CPI |
|--|----------:|----:|----------:|----:|
| C `-O2` | 840,081 | 1.235 | 11,935,062 | 1.235 |
| C `-O3` | 577,365 | **1.112** | 8,194,170 | **1.111** |
| C `-O3 -flto` | 574,256 | 1.113 | 8,152,521 | 1.112 |
| ASM **v5c13** | **291,826** | 1.212 | **3,911,647** | 1.212 |

`-flto` ≈ plain `-O3` here (single `rubik.c` TU). JSON: `results/ripes_5s/cO3flto_{min,max}.json`.

### Why C’s CPI looks better

| | C `-O3` | ASM v5c5 |
|--|--------:|---------:|
| stall / instret (min sample) | **~0.11** | **~0.28** (v5c5; v5c6 similar) |
| static load→use gap (mean) | ~4.1 | ~2.5 |
| share of loads used next insn | ~18% | ~48% |

`-O3` inlines `h_pos3ori` / `sym3` into `heuristic` (`.text` 2108 → 3412) and software-pipelines cubie loops (`lbu` burst, independent `addi`/`sb` in between). That fills 5ST load-use slots. ASM is a dense flat hot path: more adjacent `lbu`→use and taken loop backs → higher CPI even after v5c LU fills.

### Why C still retires far more instructions

| Factor | Effect on C instret |
|--------|---------------------|
| **No waterfall** | Every child evaluates **all four** views; ASM often prunes after `h(s)` (~53%) |
| **Call / spill** | `-O2` keeps helpers + frames; `-O3` inlines views but `jal heuristic` / spills remain |
| **`%3`** | subtract loops; ASM uses `mod3tab` |
| **No sibling apply** | full parent apply semantics vs ASM `from_off` 1q |

So: **CPI = quality of the average instruction in the pipe**; **instret = how many you must run**. C wins the first, loses the second by enough that **cycles still favor ASM** (~1.98× vs `-O3` on 5ST min; ~**2.3×** on emu d11 mean with **v5c13**).

### Emu / harness (CPI ≡ 1)

| | C `-O2` | C `-O3` | ASM **v5c13** |
|--|--------:|--------:|-------------:|
| d11 mean | 1,742,455 | 1,329,330 | **588,089** |
| harness 6 | 322,553 | 246,708 | **113,971** |

| Tip | Note |
|-----|------|
| Nibble shift | GCC: `slli; andi 4` ≡ `(idx&1)<<2`. Copied in **v5c3**; wash. |
| `%3` | GCC subtract loop; `mod3tab` is ours (v5c1). |
| Calls | `-O2` separate helpers; `-O3` inline into `heuristic`. |
| Search | C explicit loop, **no** waterfall short-circuit. |



