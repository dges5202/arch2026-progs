---
tags: computer-arch
---

<!-- published: https://hackmd.io/@dges5202/arch2026-homework2 -->

# Assignment 2: Complete Applications on Bare-Metal RV32I
> contributed by [dges5202](https://github.com/dges5202)

NCKU CSIE Computer Architecture, Fall 2026. Follows [Assignment 2](https://hackmd.io/@sysprog/2026-arch-homework2). Graded sources are in this fork under `src/`; long-form experiment trees sit in `notes/` and `labs/`.

Style references: [2D line drawing (fixed-point)](https://hackmd.io/@sysprog/linux2022-linedraw), [BF16 sine](https://hackmd.io/@sysprog/linux2023-bf16-sine).

## Environment

| Item | Value |
| :--- | :--- |
| Repository | https://github.com/dges5202/arch2026-progs |
| Pinned commit | [`0286cc2`](https://github.com/dges5202/arch2026-progs/tree/0286cc2) |
| Host | AMD Ryzen 7 9800X3D, Linux 6.6 (WSL2) |
| Toolchain | `riscv64-unknown-elf-gcc` 16.1.0, `-march=rv32i_zicsr -mabi=ilp32` |
| Emulator | [rv32emu](https://github.com/sysprog21/rv32emu) system emulation + `ELF_LOADER` |
| Note on timing | rv32emu: `cycle` ≡ `instret` (CPI = 1); size weighed separately with `size -A` |

---

# 1. minirubik (`rubik`)

Port of Homework 1’s 2×2 cube solver to the `arch2026-progs` contract (`rubik_solve` / `rubik_solve_asm`).

## 1.1 Principle of the code

The solver is **iterative deepening A\*** (IDA*) over the Pocket Cube’s nine face turns. Each IDA* iteration deepens with a fixed `bound`; a child is pruned when `g + 1 + h(child) > bound` (equivalently `h > r` with `r = bound - g - 1`). When the bound reaches the true distance, the first goal found is a **shortest** path: IDA* never accepts a longer path before a shorter one has been ruled out.

The heuristic is an **admissible** pattern-database lookup on a packed `(a, o)` index (pos3ori): seven cubie positions contribute an even-permutation rank `a`, and six orientations (the seventh is determined) fold into `o < 729`. To tighten `h` without losing admissibility, the search takes

$$
h = \max\bigl(h(s),\; h(s^{-1}),\; h(\sigma(s)),\; h(\sigma^{2}(s))\bigr)
$$

and **waterfalls** the four views in order `s → inv → σ → σ²`, stopping as soon as a view exceeds `r`. ASM keeps an explicit stack (`states[]` / `path[]`) instead of recursion so the 4 KiB stack and RV32I register file stay under control. The contract API is `rubik_solve` / `rubik_solve_asm(state, out, cap)`: parse 14 characters, write a space-separated move string, return length or `-1`/`-2`.

## 1.2 Mathematical foundation

**State space.** Model of `sysprog21/minirubik`: seven movable cubies, orientations in $\{0,1,2\}$ with $\sum o_i \equiv 0 \pmod{3}$. Reachable size is

$$
7! \times 3^{6} = 3{,}674{,}160.
$$

God’s number for this metric is **11**; there are **2644** states at distance 11 (the hard KPI layer).

**Encoding.** Fourteen ASCII digits `PPPPPPPOOOOOOO`: permutation `'1'..'7'` then orientation `'1'..'3'`. Solved cube: `12345671111111`.

**Generators.** Faces R, B, D; nine moves `R R2 R' B B2 B' D D2 D'`. Same-face consecutive moves are skipped in search (`face_of`).

**Distance / “shortest”.** Length = number of those nine tokens. A solution is accepted only if its length equals the BFS distance; a path that merely reaches solved is not enough if a shorter one exists. The PDB stores a lower bound on that distance, so IDA* with `max` of conjugates remains admissible and returns exact length when the bound catches up.

**Index (v3+).** Nibble PDB with stride 1024: `idx = (a << 10) + o` (live `o < 729`; padding buys a shift instead of `a*729`).

## 1.3 Analysis

**Correctness.** Course ELF **52/52**. On all **2644** d11 states, ASM length matches C; `bad=0`. Host waterfall / node scans (notes under `notes/rubik/`) checked full-space orders earlier; the graded path is guest + harness.

**Speed (rv32emu).** Here `cycle` ≡ `instret` (CPI = 1), so the d11 **mean** is an instruction KPI:

| | C `-O2` | C `-O3` | C `-O3 -flto` | ASM **v5c16** |
|--|--------:|--------:|--------------:|-------------:|
| d11 mean (2644) | 1,742,455 | 1,329,330 | 1,348,452 | **566,380** |
| vs ASM | **3.08×** | **2.35×** | **2.38×** |  |
| harness 6-depth | 322,553 | 246,708 |  | **110,161** |

Peak ASM d11 max ≈ 3.10M ≪ `RUBIK_INSN_BUDGET` (7.5M). `-O3` (inline `sym3` / `h_pos3ori`) cuts ~24% vs `-O2`; `-flto` adds little on this single-TU solver. ASM is still ~**2.35×** the best C on the d11 mean.

**Pipeline (Ripes `RV32_5S`).** Same emu min/max d11 samples (not the 2644 mean). Detail: §1.5 and [`bench-v1.md`](rubik/bench-v1.md).

| | min cycles | CPI | max cycles | CPI | ASM cycles / C |
|--|----------:|----:|----------:|----:|---------------:|
| C `-O2` | 840,081 | **1.235** | 11,935,062 | **1.235** | 0.33 / 0.31 |
| C `-O3` | 577,365 | **1.112** | 8,194,170 | **1.111** | 0.48 / 0.45 |
| C `-O3 -flto` | 574,256 | **1.113** | 8,152,521 | **1.112** | 0.48 / 0.46 |
| ASM **v5c16** | **277,288** | 1.199 | **3,718,098** | 1.198 |  |

**Why C wins CPI but loses instructions / cycles.** CPI on 5ST is stall rate, not speed. Static load→use on current objects (`objdump -d -M no-aliases`, whole `.text`): GCC `-O3` mean gap ≈**4.1**, gap=1 only ~**18%**; ASM **v5c16** mean gap ≈**2.7**, gap=1 ~**33%** (was ~48% around v5c5 before the LU-fill series). Dynamic stall/insn on the Ripes min sample is ~**0.11** (C `-O3`) vs ~**0.20** (ASM v5c16; was ~0.28 at v5c5). Instruction count is the other axis: C **never waterfalls** (every child pays all four views), keeps call/spill around `heuristic`, and uses subtract-`%3` instead of `mod3tab` — so C’s d11 mean stays ~**2.3×** ASM even though each C instruction bubbles less. Net: **lower CPI, higher cycles**. Artifacts: [`d11_cmp_cO3flto_vs_asm.txt`](rubik/results/d11_cmp_cO3flto_vs_asm.txt), [`ripes_5s/cO3flto_*.json`](rubik/results/ripes_5s/).

**Footprint.** `RUBIK_DATA_BUDGET` = 128 KiB (`size -A`). ASM `impl_asm.o` **v5c16**: `.text` **2684** + data **108405** → **111,089** ok. C `-O2` impl ≈ **110,298**.

## 1.4 Verification

- **Course micro-tests** (`tests/trubik.c` via `O2/rubik.elf`): depths 0–11 samples, solved, single moves, chains, invalid states, small `cap` → `-2`, C↔ASM length agreement — **52 passed** (`tests_rc=0`).
- **d11 battery:** 2644 God’s-number-11 states; C then ASM; length agree (`len_disagree=0`); ASM wins every cycle comparison on rv32emu ([`results/d11_cmp_v5c16.txt`](rubik/results/d11_cmp_v5c16.txt)).
- **Budgets:** instruction caps in `rubik.h`; data budget via `scripts/driver.py` / `size -A` (ASM text+data **111,089** ≤ 128 KiB).
- **Ripes:** CLI `RV32_5S` on a tiny ELF that only calls `rubik_solve_asm` ([`results/ripes_5s/`](rubik/results/ripes_5s/)) — CPI/stall check, not a substitute for the 2644 mean.

## 1.5 Optimization

Baseline numbers: [`notes/rubik/bench-v1.md`](rubik/bench-v1.md). Depth-11 = hardest God’s-number layer (**2644** states); full 3.67M C check is separate.

| Ver | Change | d11 mean | vs `-O2` | 5ST (CPI / cycles) | Notes |
|-----|--------|--------:|---------:|-------------------:|-------|
| **v1** | IDA* + waterfall `s→inv→σ→σ²`; C-style apply; parse `sll` | **824,948** (p50 757k / max 4.54M) | **2.17×** (C 1,789,077) | CPI **1.346** / **1.344**; cycles **442,606** / **5,799,763** | First correct ASM; harness 162k vs C 331k |
| **v2** | Reorder `s→σ→σ²→inv`; `PDB_NIBBLE`; `r==0` gate | **909,588** (p50 828k / max 5.06M) | **1.97×** | *(bisect; not 5ST’d)* | **+10.3% vs v1** (regress); harness 174k |
| **v2−r0** | Same as v2 but drop `r==0` gate | **909,626** | 1.97× | — | ≈v2 → not the +10% |
| **v2−macro** | Same order+`r0`; inline nibble (macro unused) | **909,588** | 1.97× | — | ≡ v2 → macro not the cost |
| **v2b** | Restore `s→inv→σ→σ²`; reuse `h(s)` pos; keep `r0`+macro | **824,914** (p50 756k / max 4.55M) | **2.17×** | CPI **1.349** / **1.347**; cycles **451,668** / **6,125,417** | Fixed; harness **156,924**; `.text` 3180 |
| **v3** | PDB stride 1024; idx=`(a<<10)+o` (C+ASM same table) | **801,047** (p50 735k / max 4.42M) | **2.18×** (C **1,742,455**) | CPI **1.359** / **1.357**; cycles **441,957** / **5,997,626** | **−2.9% vs v2b** emu |
| **v4a** | `turns==1` fast path: parent→`Q+16` one quarter | **801,022** | **2.18×** | *(not re-5ST’d; ≈v3)* | ≈v3 (noise) |
| **v4b** | Sibling 1-quarter apply via `from_off` (always 1q) | **685,295** | **2.54×** | CPI **1.359** / **1.357**; cycles **380,735** / **5,121,231** | **−14.5% vs v3**; harness **131,708** |
| **v5a** | Pin `a3=&sig`, walk `a4`; no per-PDB `li s1,9` | **681,242** | **2.56×** | CPI **1.362** / **1.359**; cycles **379,044** / **5,099,017** | −0.59% vs v4b |
| **v5b** | σ/σ² pack-while-scatter (drop 7-scan) | **660,887** | **2.64×** | CPI **1.344** / **1.342**; cycles **362,214** / **4,878,632** | **−3.0% vs v5a** |
| **v5c1** | Hot `%3` → `mod3tab` (`a7` pin) | **664,235** | **2.62×** | CPI **1.312** / **1.312**; cycles **355,179** / **4,789,550** | emu **+0.51%** vs v5b; 5ST wins; `.text` **2788** |
| **v5c2** | `r==0` cold: `beqz` → `r0_id_path`; `r≠0` fall into waterfall | **664,235** | **2.62×** | CPI **1.309** / **1.308**; cycles **354,181** / **4,775,204** | emu ≡ v5c1; **5ST −0.3%** |
| **v5c3** | PDB nibble `slli; andi 4` (macro + root) | **664,235** | **2.62×** | CPI **1.309** / **1.308**; cycles **354,181** / **4,775,204** | ≡ v5c2 (2→2 insn) |
| **v5c4** | `apply_1q` load-use schedule (dest / `&twist` fills) | **664,235** | **2.62×** | CPI **1.296** / **1.294**; cycles **350,618** / **4,724,909** | emu ≡; **5ST −1.0%** |
| **v5c5** | pos-build: `addi a4` between `lbu p` and use | **664,235** | **2.62×** | CPI **1.283** / **1.280**; cycles **347,090** / **4,674,656** | emu ≡; **5ST −1.0%** vs v5c4 |
| **v5c6** | Sibling copy: 4×`lw`/`sw` (was 14×`lbu`/`sb` loop) | **597,951** | **2.91×** | CPI **1.277** / **1.274**; cycles **312,585** / **4,181,698** | **−10%** emu/5ST; harness **115,916**; `.text` **2792** |
| **v5c7** | `no_prev`: `&source`/`&twist` via `s6+27` / `+24` (drop hot `la`) | **594,058** | **2.93×** | CPI **1.279** / **1.276**; cycles **311,058** / **4,160,143** | **−0.65%** vs v5c6; harness **115,175**; `.text` **2780** |
| **v5c8** | `inv_o` LU: `addi` after `lbu i`; `slli a6=o*2` fills `s.o→sub` | **594,058** | **2.93×** | CPI **1.265** / **1.265**; cycles **307,878** / **4,124,035** | emu ≡; **5ST ~−1.0%**; keep `t6=a` |
| **v5c9** | σ/σ² `p_build`: interleave `&sig[i]` in `a0` | **594,058** | **2.93×** | CPI **1.257** / **1.256**; cycles **305,736** / **4,095,986** | emu ≡; **5ST ~−0.7%** vs v5c8 |
| **v5c10** | σ/σ² `o_build`: `a6=&sig[i]`; overlap `kk`/`sig` loads | **589,145** | **2.96×** | CPI **1.215** / **1.215**; cycles **292,884** / **3,927,692** | **−0.83%** emu; **5ST ~−4%**; `.text` **2772** |
| **v5c11** | `.balign 16` on `states`/`scratch`; linker `.data` `ALIGN(4)` | **589,145** | **2.96×** | CPI **1.215** / **1.215**; cycles **292,884** / **3,927,692** | hygiene for `lw`/`sw`; KPI ≡ v5c10 |
| **v5c12** | `no_prev`: `addi a0=Q+16` fills `lbu from_off→add a6` | **589,145** | **2.96×** | CPI **1.212** / **1.213**; cycles **292,375** / **3,920,507** | emu ≡; **5ST ~−0.17%** |
| **v5c13** | Drop post-push `solve_loop` id; `j child`; finds via `r0_id` | **588,089** | **2.96×** | CPI **1.212** / **1.212**; cycles **291,826** / **3,911,647** | **−0.18%** emu; **5ST ~−0.2%**; `.text` **2736** |
| **v5c14** | `apply_1q`: `li t0=6`; `addi` fills mod3→`sb`; `bgez` | **588,089** | **2.96×** | CPI **1.197** / **1.197**; cycles **288,263** / **3,861,352** | emu ≡; **5ST ~−1.2%** |
| **v5c15** | Merge σ/σ² `p_build`+`o_build` per `i` (share `p`/`sig[i]`) | **567,032** | **3.07×** | CPI **1.199** / **1.198**; cycles **277,553** / **3,721,107** | **−3.58%** emu; **5ST ~−3.7%**; `.text` **2688** |
| **v5c16** | `h(inv)`: fold `&child.o[0]` to `addi a4,s4,23` | **566,380** | **3.08×** | CPI **1.199** / **1.198**; cycles **277,288** / **3,718,098** | **−0.11%** emu; **5ST ~−0.1%**; `.text` **2684** |

Raw d11 compare dumps stay in the repo under `notes/rubik/results/` (not linked row-by-row). Root cause of v2 regress: putting **inv after σ** forced a pos rebuild. `r0` / macro were innocent. v3 pads PDB for a cheap shift index. v4b reuses prior face-turn at `Q+16` for R2/R'. v5b folds arank pack while scattering `y.p`/`z.p`. v5c1 trades a bit of emu instret for lower 5ST CPI (branch-free `%3`). v5c2 makes the common `r≠0` path fall through into the waterfall. v5c3 aligns nibble extract with GCC’s form; no cycle win alone. v5c4–v5c5 fill load-use slots in apply and pos-build. **v5c6** replaces the sibling byte-copy (~84 insn) with eight word moves — large because six of nine moves take the scratch path. **v5c7** drops the per-child `la source`/`la twist` pair; F-cluster layout already places them at `s6+27` / `s6+51`. **v5c8** fills the two `lbu t2`→use edges in `inv_o` (`addi t0` + `slli a6`); `a6` is the temp so `t6` still holds arank `a` for `PDB_NIBBLE`. **v5c9** overlaps independent `&sig[i]` with `p[i]`→use and interleaves `lbu sig[i]` against `sig[p[i]]` in both σ and σ² `p_build`. **v5c10** does the same for `o_build`: keep `a6=&sig[i]`, load `kk[i]`/`sig[i]` around the `kk[p]` use, drop a redundant address add (also −8B `.text`). **v5c11** forces 16-byte alignment on the `lw`/`sw` slots so strict RV32I cannot misaligned-trap if `.data` placement shifts. **v5c12** slides the independent `addi a0,s4,16` into the `from_off` load-use gap in `no_prev`. **v5c13** drops the post-push identity scan (`solve_loop`): under IDA* return-on-first-bound it never reached `found` (solved hits only via cold `r0_id_path`), so push ends in `j child` (−36B `.text`, ~−0.18% emu). **v5c14** moves the countdown `addi` between mod3 `lbu` and `sb` (`li t0=6` + `bgez`), killing the last apply load-use (~−1.2% 5ST; emu flat). **v5c15** folds σ/σ² `o_build` into the `p_build` loop so each `i` shares `p[i]`/`sig[i]` (keep bare `sig[i]` in `a6`; ori in `t6`; σ² stores `z` at `+14`/`+21`) — ~−3.6% emu/5ST from fewer loads and one less loop trip. **v5c16** folds the two-`addi` `&child.o[0]` setup (`s4+16` then `+7`) into one `addi a4,s4,23` (−4B `.text`, ~−0.11% emu).

**Ripes 5ST method:** CLI `RV32_5S` on `rubik_solve_asm` only (tiny ELF), sample states from [`d11_ripes_sample_states.txt`](rubik/results/d11_ripes_sample_states.txt) (emu min/max). JSON + CSV: [`results/ripes_5s/`](rubik/results/ripes_5s/). Full 2644× not run (too slow in GUI/CLI). rv32emu still owns the **mean of 2644** KPI.

## 1.6 RV32I improvements

No `mul`/`div`/`rem` and no F: ranks and PDB indices are shifts and adds (`a << 10`, nibble extract). Homework 1’s Ripes ecall/LED path is gone; I/O is `out`/`cap` plus freestanding `write`/`exit` in the harness.

What hand-written ASM recovers versus gcc `-O2`/`-O3` on this cube:

- **Algorithm shape gcc will not invent:** sibling one-quarter apply (`from_off`), four-view waterfall with early prune, pack-while-scatter for σ/σ².
- **Stable pins:** `MOVES`, `&sig`, `&mod3tab`, walk cursor in `a`/`s` regs — fewer `li`/`la` in the child hot path than a spilling C `search` loop.
- **Pipeline-facing layout:** fall-through on the common `r ≠ 0` path; load-use fills through `apply_1q` / pos / inv / σ; word sibling copy; merged σ p+o (Ripes CPI ~1.36 → ~**1.20**). rv32emu cannot see those stalls (`CPI ≡ 1`).

C still wins on raw “compiler micro” tricks in places (nibble form was a wash when copied). The large gap is search structure + tables under a 128 KiB ceiling, not a missing M-extension multiply.

## 1.7 Real-world applications

IDA* with pattern databases is the standard exact approach for small permutation groups (Pocket Cube, 15-puzzle variants, some logistics / assembly sequencing). The same trade appears in embedded and bare-metal settings: a **compact admissible table** plus iterative deepening beats storing all distances (here 3.67M states would blow the 128 KiB data budget and the instruction budget of a plain BFS).

Memory and instruction caps in `rubik.h` mirror MCU constraints — fit code+tables in a fixed ROM/RAM envelope, and bound worst-case work (d11) so a solve cannot run unbounded on a soft core. RV32I-only forces the implementation to stay in shifts, loads, and branches; the interesting engineering is which symmetries and move factorizations buy prune power without growing the PDB past the envelope.

---

# 2. BFloat16 (`bf16`)

Quiz 1 Problem B, graded in this fork: three leaves — [`bf16_from_f32`](https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/bf16/bf16.c) / [`bf16_mul`](https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/bf16/bf16.c) / [`bf16_sqrt`](https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/bf16/bf16.c) and the matching `*_asm` in [`bf16.S`](https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/bf16/bf16.S) — contract in [`bf16.h`](https://github.com/sysprog21/arch2026-progs/blob/main/src/bf16/bf16.h). Harness numbers below come from `scripts/driver.py --prog bf16` on this tree; a short log sits in [`notes/bf16/bench.md`](bf16/bench.md). The separate personal truncate/IEEE lab lives outside this repo at `homework/bf16` (add/sub/div and twins; not graded here).

## 2.1 Principle of the code

BFloat16 stores a binary32 value truncated to 16 bits: 1 sign, 8 exponent bits (bias 127), 7 fraction bits. All arithmetic in this assignment is on the **bit pattern** (`uint16_t` / `uint32_t`); no FP instruction and no C `float` arithmetic.

**`bf16_from_f32(f32bits)`** narrows a binary32 pattern. If the exponent field is `0xFF` (Inf/NaN), return the top 16 bits unchanged. Otherwise add `0x7FFF` plus bit 16 of the input and keep the top 16 bits — round to nearest, **ties to even**. That add may carry into the exponent (largest finite → Inf).

**`bf16_mul(a, b)`** XORs the signs, then examines specials in order **a then b** (NaN unchanged, Inf×0 → quiet NaN `0x7FC0`, else Inf with the product sign). Finite zeros → signed zero. Denormals are normalized (shift leading one up, adjust exponent). The 8×8 significand product (hidden 1 when exp≠0) is renormalized one bit when bit 15 is set; the fraction is **truncated** (toward zero), not RNE. Exponent ≥`0xFF` → Inf; ≤0 → denormal shift or signed zero if the exponent falls below −6.

**`bf16_sqrt(a)`** keeps NaN and +Inf; −Inf and any negative nonzero → `0x7FC0`; ±0 → `+0`; denormals → `+0`. For positive normals: make an odd exponent even by doubling the significand, then search `mid ∈ [90,256]` for the largest value with `(mid*mid)/128 ≤ m` (truncating). Renormalize into `[128,256)`, update the exponent. Not correctly rounded; contract bound on positive normals is 0.3884% relative error.

```c
/* Narrowing — same idea as the harness C */
uint16_t bf16_from_f32(uint32_t f32bits)
{
    if ((f32bits & 0x7F800000u) == 0x7F800000u)
        return (uint16_t) (f32bits >> 16);
    f32bits += ((f32bits >> 16) & 1u) + 0x7FFFu;
    return (uint16_t) (f32bits >> 16);
}
```

## 2.2 Mathematical foundation

**Format.** Value of a normal encoding with sign $s$, exponent field $E$, fraction $f$:

$$
(-1)^s \cdot 2^{E-127} \cdot \bigl(1 + f/2^7\bigr),\quad E\in\{1,\ldots,254\}.
$$

Subnormals use $E=0$ and significand $f/2^7$ without the hidden one. Quiet NaN produced here is `0x7FC0`; ±Inf are `0x7F80` / `0xFF80`.

**Narrowing (RNE).** Discarding the low 16 bits of binary32 with bias `0x7FFF` plus the sticky/tie bit at position 16 is the standard “round to nearest even” fold into bf16. Error bound for finite non-overflowing values is half an ulp of the bf16 binade.

**Multiply (truncate).** With normalized 8-bit significands $m_a,m_b\in[128,255]$, the product sits in 16 bits. If bit 15 is set, shift right 8 and bump the exponent; else shift right 7. Keeping only 7 fraction bits by chopping (no sticky) means the product is a directed rounding toward zero in the significand — the homework contract, not IEEE RNE float gold.

**Square root.** $\sqrt{2^e\cdot m}=2^{e/2}\sqrt{m}$. Odd $e$ → $m\leftarrow 2m$, $e\leftarrow e-1$. The integer search implements $\lfloor\sqrt{128\cdot(m+1)}\rfloor$-style truncation used by the quiz, not a correctly rounded `sqrtf`.

## 2.3 Analysis

Homework budgets (worst retired instructions, any operands): from_f32 60 / 150 (ASM / C), mul 400 / 1000, sqrt 1500 / 4000. All three ASM leaves stay inside the ASM budgets; the C builds stay inside the C budgets.

Harness bench on rv32emu (`cycle` ≡ `instret`; 16 fixed inputs in `tests/mbf16.c`; loop baseline subtracted):

| Function | asm | best C | asm vs best C |
| :--- | ---: | ---: | ---: |
| `from_f32` | 11.2 | 11.1 (`-O1`) | 0.98× |
| `mul` | **80.8** | 83.5 (`-O2`) | **1.03×** |
| `sqrt` | **296.2** | 318.9 (`-O2`) | **1.08×** |

Full per-opt table: [`notes/bf16/bench.md`](bf16/bench.md). `.text` for the three leaves: ASM **704 B** vs C `-O2` **872 B**.

`from_f32` is not a real loss: C `-O1` and ASM both retire **279** instructions over the same 16 calls; the 0.98× only appears after subtracting slightly different empty-loop baselines (102 vs 99). Finite-path disassembly is 11 instructions on both sides (`lui`/`and`/`beq`, then the RNE `lui`+`addi` for `0x7FFF`).

`mul` and `sqrt` beat the best C build on this suite. Grade item: **bf16 15/15**.

## 2.4 Verification

- **Contract tests** (`tests/tbf16.c`): directed cases; narrowing sweeps over discarded/kept halves and tie-deciding bits; mul directed + 256×256 grid + constants×all 65536; sqrt directed + all 65536 + monotonicity / 1% bound / special classes; C↔ASM agreement; `@@perf` budgets.
- **Host sanitize:** portable C, no inline asm (`make sanitize` covers the C side).
- **Personal lab (optional, not graded):** truncate vs IEEE-RNE twins under `homework/bf16/` check that truncate mul/sqrt deliberately disagree with `float` gold — a policy check for the homework contract, not a harness failure.

## 2.5 Optimization

| Focus | Change | Harness effect |
| :--- | :--- | :--- |
| Narrow | Fall-through RNE; Inf/NaN is the taken `beq` | Ties best C after baseline noise (0.98×) |
| Mul door | Unpack from `a0`/`a1` (no spare copies into `a6`/`a7`) | Part of the leaf that lands at **1.03×** vs `-O2` |
| Mul soft product | 8-step shift-add; skip add when the multiplier bit is clear | Beats gcc’s `__mulsi3` path on the graded inputs |
| Sqrt | ±0 before sign→NaN; soft `mid*mid` bisect | **1.08×** vs best C |
| Add/sub (lab only) | Exp-first zero gate, same/opp fall-through | Local playground only; not in the graded ELF |

```text
bf16_mul (homework shape)
  unpack; sign_xor
  specials a then b (NaN / Inf×0 / Inf)
  normalize denorms; exp = ea+eb-127
  8×8 soft mul (shift-add; __mulsi3 allowed in C)
  bit15 ? >>8, exp++ : >>7   # truncate fraction
  pack / under→0 / over→Inf
```

## 2.6 RV32I improvements

No `mul`/`div`/`f*`. Mantissa products and `mid*mid` in sqrt are shift-and-add in ASM (C may call `__mulsi3`). Binary32 arrives as `uint32_t` bits, so `bf16_from_f32` never needs F.

On this harness, the hand-written `mul` and `sqrt` leaves already beat the best gcc `-O*` builds without M/F. Narrowing is short enough that gcc `-O1` matches the leaf instruction-for-instruction; further chasing the 0.98× figure would be fighting the empty-loop baseline, not the algorithm.

`__muldi3` is not required for these three functions if products stay in 16–32-bit intermediates.

## 2.7 Real-world applications

BFloat16 is the default 16-bit format in many ML frameworks (TensorFlow, large-model training) because the 8-bit exponent matches binary32’s range while cutting bandwidth and register pressure. Machine kernels often use truncate or stochastic rounding rather than full RNE on every multiply — the homework mul contract is closer to that “cheap” path. Integer-only implementations matter on microcontrollers and RV32I soft cores that lack F/D. The same special-case lattice (NaN propagation, Inf×0) shows up in every IEEE-style ISA exception model, even when the fraction rounding is relaxed.

---

# 3. Binary GCD (`gcd`)

Quiz 2 Problem A (Stein / binary GCD), graded in this fork: [`gcd_u32`](https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/gcd/gcd.c) / [`gcd_u32_asm`](https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/gcd/gcd.S), contract [`gcd.h`](https://github.com/sysprog21/arch2026-progs/blob/main/src/gcd/gcd.h). Harness bench: [`notes/gcd/bench.md`](gcd/bench.md). Early playground opt history (pre-fork) remains linked by commit in §3.5.

On the early playground ELF the timed window was `get_cycles; get_instret; <body>; …`. An empty probe was 21 cycles / 7 instret; **gcd-only retired** = `iret − 7` per Quiz pair. An optimization counts only if the six Quiz lines still match.

## 3.1 Principle of the code

Stein’s algorithm replaces Euclid’s division with shifts and subtractions. For unsigned $a$ and $b$ ([Quiz 2 solutions](https://hackmd.io/@sysprog/arch2026-quiz2-sol)):

$$
\begin{aligned}
\gcd(0, b) &= b \\
\gcd(2a, 2b) &= 2 \cdot \gcd(a, b) \\
\gcd(2a, b) &= \gcd(a, b) \quad \text{when } b \text{ is odd} \\
\gcd(a, b) &= \gcd(a, b - a) \quad \text{when } a, b \text{ are both odd and } b \ge a
\end{aligned}
$$

Order of application: (1) either side zero → return the other ($\gcd(0,0)=0$ here); (2) while both even, shift both and count shared twos; (3) strip leftover twos from each side alone; (4) while odd values differ, subtract the smaller from the larger and shift the even difference; (5) shift the odd gcd left by the shared count.

```c
/* https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/gcd/gcd.c */
unsigned gcd(unsigned a, unsigned b)
{
    unsigned count = 0;
    if (a == 0) return b;
    if (b == 0) return a;
    while (a % 2 == 0 && b % 2 == 0) {
        a >>= 1; b >>= 1; count++;
    }
    while (a != b) {
        while ((a & 1) == 0) a >>= 1;
        while ((b & 1) == 0) b >>= 1;
        if (a > b) a = (a - b) >> 1;
        else if (a < b) b = (b - a) >> 1;
        else break;
    }
    return a << count;
}
```

Why the identities hold, briefly: every integer divides 0; a shared factor of two factors out of the gcd; a two that only one side still has is not common; Euclid’s $\gcd(a,b)=\gcd(a,b-a)$ needs no remainder, and when both are odd $b-a$ is even so one right shift is free.

## 3.2 Mathematical foundation

Domain: unsigned $\{0,\ldots,2^{32}-1\}$. No rounding; error against a host `unsigned` reference is identically zero on every 32-bit pair.

**Bit 31 is data, not a sign.** Quiz pairs include $(0\text{x}80000001, 3)$ and $(0\text{xF0000000}, 0\text{x}30000000)$. Every compare is `bltu` / `bgeu` / `beq`.

**Shifts are logical** (`srli` / `srl`). After both sides were odd, $a-b$ is even; `srai` would fill ones when bit 31 of the difference is set.

**The subtract cannot wrap** on the taken arm: `bltu` establishes $a>b$ (or the swap) before `sub`.

Shared-two count: for $n\neq 0$, $v_2(\gcd(a,b))=\min(v_2(a),v_2(b))=v_2(a\lor b)$, so peel $\mathrm{ctz}(a\lor b)$, not $\mathrm{ctz}(a\land b)$. RV32I has no `ctz` (Zbb) and no `div`/`rem`.

## 3.3 Analysis

What the six Quiz pairs exercise:

| Pair | Inputs | Result | Stress |
| :--- | :--- | ---: | :--- |
| 0 | (1071, 462) | 21 | mixed odds, several subtracts |
| 1 | (4096, 3072) | 1024 | powers of two → almost all `even_loop` |
| 2 | $(0\text{xF0000000}, 0\text{x}30000000)$ | $0\text{x}30000000$ | long shared-two run (bit 31 set) |
| 3 | $(0\text{x}80000001, 3)$ | 3 | unsigned $a>b$ subtract, many times |
| 4 | (0, 91) | 91 | early return (smoke) |
| 5 | (6, 10) | 2 | shared $k=1$ canary for binary `even_loop` |

CSR baseline [`958ff64`](https://github.com/dges5202/2026-hw2-baremetal/commit/958ff64): **652** gcd-only retired over six pairs; ELF `.text` 792, `gcd` symbol 124 B. Best kept point [`9780d53`](https://github.com/dges5202/2026-hw2-baremetal/commit/9780d53): **400** gcd-only (−39%); per-pair gcd-only 53, 73, 65, 163, 7, 39; `gcd` 228 B.

## 3.4 Verification

- **Host:** twelve cases (six Quiz pairs, zeros, coprimes, composites), each also swapped.
- **Guest:** six Quiz lines exact (pair 2 prints `4026531840` as unsigned decimal).
- **Reference:** host `unsigned` gcd / Quiz oracle. Early playground work used that gate before the harness micro-test; the `arch2026-progs` port reuses the same algorithm under `tests/tgcd.c`.

## 3.5 Optimization

Every row is gcd-only retired over the six pairs (CPI 1.00 on rv32emu). Full per-pair windows: [`notes/gcd/bench.md`](gcd/bench.md). Early playground commits stay linked below.

| Commit | Change | Retired | `.text` | `gcd` B | Δ |
| :--- | :--- | ---: | ---: | ---: | ---: |
| [`958ff64`](https://github.com/dges5202/2026-hw2-baremetal/commit/958ff64) | CSR baseline | 652 | 792 | 124 |  |
| [`e7c4534`](https://github.com/dges5202/2026-hw2-baremetal/commit/e7c4534) | `even_loop` bottom-tested | 613 | 800 | 132 | −39 |
| [`2b46ee8`](https://github.com/dges5202/2026-hw2-baremetal/commit/2b46ee8) | `strip_*` bottom-tested | 593 | 808 | 140 | −20 |
| [`d489786`](https://github.com/dges5202/2026-hw2-baremetal/commit/d489786) | `a>b` falls into `gcd_loop` (**kept**) | 578 | 812 | 144 | −15 |
| [`de064c5`](https://github.com/dges5202/2026-hw2-baremetal/commit/de064c5) | `larger_b` fall-through (not kept) | 592 | 808 | 140 | +14 vs `a>b` |
| [`99e8e2b`](https://github.com/dges5202/2026-hw2-baremetal/commit/99e8e2b) | strip only the side just made even | 546 | 836 | 168 | −32 |
| [`577ecda`](https://github.com/dges5202/2026-hw2-baremetal/commit/577ecda) | `strip_b` falls into `odd_sub` | 544 | 828 | 160 | −2 |
| [`9fe12b6`](https://github.com/dges5202/2026-hw2-baremetal/commit/9fe12b6) | binary 16/8/4/2/1 `even_loop` | 439 | 860 | 192 | −105 |
| [`97c3cba`](https://github.com/dges5202/2026-hw2-baremetal/commit/97c3cba) | nibble split; delay `li t5`/`t6` | 403 | 900 | 232 | −36 |
| [`9780d53`](https://github.com/dges5202/2026-hw2-baremetal/commit/9780d53) | drop extra `or` before nibble | 400 | 896 | 228 | −3 |

**Fall-through loops.** On rv32emu a `j` always retires. Bottom-tested hot loops execute `beq` back and skip a trailing `j`. That is most of the −39 on `even_loop` (pairs 1–2) and −20 on `strip_*` (pair 3).

**Which subtract arm falls through.** At most two labels can be fall-through predecessors in a 3-block cycle. Measuring both layouts: `a>b` fall-through saved 15 (all on pair 3); `larger_b` fall-through lost 15 on pair 3. Kept `a>b`.

**Strip only the side just made even.** After `a=(a-b)>>1`, $b$ is still odd. First entry still peels both (`strip_a1`→`strip_b`); afterward `a>b`→`strip_a` only and `larger_b`→`strip_b` only (−32).

**Shared twos: nibble then binary.** $v_2(0\text{xF0000000})=28$ makes a 1-bit peel linear in $k$. A 16/8/4/2/1 walk of $\mathrm{ctz}(a\lor b)$ cut −105, but hurt pair 5 ($k=1$). Kept layout: after parity, $(a\lor b)\land 0\text{xF}$ nonzero → 1-bit shortcut; zero → binary path with `t5`/`t6` loaded only there.

```asm
/* https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/gcd/gcd.S */
even_loop:
    or      t1, a0, a1
    andi    t2, t1, 1
    bne     t2, x0, strip_a1
    andi    t2, t1, 0xF
    beq     t2, x0, even_loop_skip
even_loop_shortcut:
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    or      t1, a0, a1
    andi    t2, t1, 1
    beq     t2, x0, even_loop_shortcut
    j       strip_a1
```

Not kept on this suite: dual-path entry state machine; binary `strip_*` (leftover twos after `odd_sub` are usually 1); `sltu` min/max without a gcc listing to beat; 5-stage load-use scheduling (invisible on rv32emu).

## 3.6 RV32I improvements

The Quiz listing was already RV32I. What the homework removed was Ripes print-integer (`a7=36`) and any pretended divider. Decimal output is repeated subtraction of `pow10[]` plus `write` (64); startup is playground-style `sp` / `.bss` / `main` / `exit`. Application `gcd` does not touch CSRs (counters live in the harness / earlier `perfcounter.S` experiments).

Inside `gcd` the remaining RV32I cost is the missing `ctz`. A de Bruijn table needs a multiply (`__mulsi3`) or a load table that is not cheaper than the nibble test on $k\le 3$. The nibble/binary split is the defense on this suite. No multiply appears in this program.

Open relative to the full harness grade: same CSR/`@@bench` window against gcc `-O1`/`-O2`/`-O3`/`-Os` once the algorithm sits in `arch2026-progs` `src/gcd/`.

## 3.7 Real-world applications

Binary GCD is used where a fast divider is missing or inputs are often even (GMP, modular inverses, fraction reduction, RSA-related gcd steps). Constraints carry over: unsigned domain, bit 31 is data, strip visible twos before subtracting. Hardware `ctz` (Zbb / BMI) collapses `even_loop`; the nibble split is the RV32I stand-in. The six Quiz pairs bias the sum toward long shifts and one long unsigned subtract, with a $k=1$ canary so a pair-2-only win is visible.

---

# 4. Bitwise adders and Q11.20 (`fixed`)

Quiz 3 Problem C, graded in this fork: [`op1`/`op2`/`op3`/`q_mul`](https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/fixed/fixed.c) and [`*_asm`](https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/fixed/fixed.S), contract [`fixed.h`](https://github.com/sysprog21/arch2026-progs/blob/main/src/fixed/fixed.h). Bench: [`notes/fixed/bench.md`](fixed/bench.md). Gate-delay and sequential-circuit parts of the quiz are not programs and are not ported. Early playground opt commits remain linked in §4.5.

## 4.1 Principle of the code

Four routines. The first three rebuild addition-family ops from bitwise logic; the fourth is a Q11.20 multiply.

**`op1(a, b, n)`** is a carry-loop adder. One bit obeys $\mathrm{sum}=a\oplus b$ and $\mathrm{carry}=(a\land b)\ll 1$. Applied to whole words, each pass replaces $(a,b)$ with $(\mathrm{sum},\mathrm{carry})$ until the carry word is zero. The return value is $a+b\bmod 2^{32}$; `*n` is the number of passes (`op1(x,0)` → `*n=0`; `op1(0xFFFF,1)` → `0x10000` in 17 passes).

**`op2(a, b)`** is $a-b\bmod 2^{32}$. The bitwise model is `op1(a, op1(~b, 1))`; the budget asks for a plain `sub`, which yields the same bits.

**`op3(a, b)`** is $\lfloor(a+b)/2\rfloor$ of the exact sum. `(a+b)>>1` in `uint32_t` overflows; the overflow-free form is $(a\gg 1)+(b\gg 1)+(a\land b\land 1)$.

**`q_mul(a, b)`** multiplies two Q11.20 values: store $A$ means $A/2^{20}$. Form the 64-bit product, add $2^{19}$, arithmetic-shift right by 20 (ties toward $+\infty$), keep the low 32 bits (wrap, no saturation).

```c
/* https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/fixed/fixed.c */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    uint32_t c;
    int count = 0;
    while (b != 0) {
        c = (a & b) << 1;
        a = a ^ b;
        b = c;
        count++;
    }
    *n = count;
    return a;
}
```

## 4.2 Mathematical foundation

**Unsigned 32-bit ring.** `op1`/`op2`/`op3` live in $\{0,\ldots,2^{32}-1\}$ with wrap-around. Compares and shifts on these paths are logical (`bltu`, `srli`). Bit 31 is data, not a sign bit for these three.

**Q11.20.** One unit is $2^{20}=1048576$; $0.5$ is $2^{19}=524288$. After a full-precision product $P=a\cdot b$, the stored result is $\lfloor(P+2^{19})/2^{20}\rfloor$ truncated to 32 bits. Examples from the contract: `q_mul(3, 524288)=2`, `q_mul(-3, 524288)=-1`.

**Signed 32×32→64 under RV32I.** Zero-extending the bit patterns and multiplying as unsigned does **not** give a signed 64-bit product when either operand has bit 31 set. The implementation takes absolute values, forms an unsigned magnitude, then two's-complement-negates the 64-bit pair when the signs differ. A direct `int64_t` multiply becomes `__muldi3`, which the freestanding runtime does not supply; `__mulsi3` (32-bit) is allowed.

## 4.3 Analysis

Measured on rv32emu (`cycle` ≡ `instret`). Worst call over the grader’s 64×64 grid plus 4096 random pairs (`@@perf`), and the 16-input bench window (`@@bench`), at `-O2`:

| Function | C worst | ASM worst | Budget (ASM / C) | C bench | ASM bench | ASM / best C |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: |
| `op1` | 169 | 169 | 600 / 1500 | 453 | 453 | 1.00× |
| `op2` | 6 | 6 | 40 / 150 | 163 | 163 | 1.00× |
| `op3` | 11 | 11 | 40 / 150 | 243 | 243 | 1.00× |
| `q_mul` | 519 | 399 | 1200 / 3000 | 5199 | 3613 | **1.45×** |

`.text`: C `-O2` implementation object 348 B; hand-written 216 B (`op1` 36, `op2` 8, `op3` 28, `q_mul` 144). Checksums of C and assembly agree on every bench input.

`q_mul` is exact relative to the contract’s rounding (independent 16-bit partial-product reference in `tests/tfixed.c`). Integer ops have zero error against `uint32_t` arithmetic.

## 4.4 Verification

- **Host:** `make build/host/fixed` — 15 micro-tests (directed / grid / random / laws for `op1`; subtraction and average laws; `q_mul` cases, reference, laws).
- **Guest:** same suite for C and `_asm`, C↔ASM agreement, instruction budgets, `scripts/driver.py --prog fixed` → **55.0/55** after the `op1`–`op3` sequence below.
- **Boundaries:** `op1` pass count 0…32 and symmetry; `op2(0,1)=0xFFFFFFFF`; `op3(0xFFFFFFFF,1)=0x80000000`; Q11.20 tie cases above.

## 4.5 Optimization

| Commit | Change | `@@perf` ASM op1/op2/op3/q_mul | Effect |
| :--- | :--- | ---: | :--- |
| [`db96067`](https://github.com/dges5202/2026-hw2-baremetal/commit/db96067) | baseline `op1`: top `beqz`, `mv`, `j` | 233 / 8 / 12 / 399 | `op1` 0.81× vs C — grader fail |
| [`8a202df`](https://github.com/dges5202/2026-hw2-baremetal/commit/8a202df) | `op1` bottom-tested; `slli` into `a1` after `xor` | 169 / 8 / 12 / 399 | `op1` matches C (1.00×) |
| [`3e24f41`](https://github.com/dges5202/2026-hw2-baremetal/commit/3e24f41) | `op2`: plain `sub` | 169 / 6 / 12 / 399 | drop `bltu` two-path |
| [`2b3c782`](https://github.com/dges5202/2026-hw2-baremetal/commit/2b3c782) | `op3`: one `and` + `andi` for LSB | 169 / 6 / 11 / 399 | match gcc body length |

`op1` excerpt after the fall-through rewrite:

```asm
/* https://github.com/dges5202/arch2026-progs/blob/0286cc2/src/fixed/fixed.S */
op1_asm:
    li      t0, 0
    beqz    a1, op1_loop_skip
op1_loop:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bnez    a1, op1_loop
op1_loop_skip:
    sw      t0, 0(a2)
    ret
```

## 4.6 RV32I improvements

No `mul`/`div`. gcc’s natural `int64_t` product calls `__muldi3` and fails to link. The allowed helper is `__mulsi3` only.

- **C path (for a linkable guest):** absolute values, four 16×16 products via `__mulsi3`, reassemble a 64-bit magnitude, conditional negate, add $2^{19}$, shift. At `-O2` this is a non-leaf: stack frame, several callee-saved spills, and **four** `jal __mulsi3`. Each `__mulsi3` is itself up to a 32-iteration shift-add.
- **Hand-written `q_mul_asm`:** one leaf 32×32→64 shift-add into `(t1,t0)`, `beqz` skips the 64-bit add when the multiplier bit is clear, early exit when the remaining multiplier is zero, then the same rounding extract `(lo>>20)|(hi<<12)`.

That is why `q_mul` is ~1.45× fewer bench cycles than the best C build, while `op1`/`op2`/`op3` only needed to **match** gcc (bottom-tested loop, plain `sub`, compact LSB carry). Matching the compiler passes the automated check; beating it on `q_mul` is where the hand-written path earns its keep.

## 4.7 Real-world applications

Bitwise adders appear in soft ALUs and in code that must run without an M extension. Q11.20 is the same fixed-point pattern as the course line-drawing note: integer multiply, a rounding bias, an arithmetic shift back into the format, and wrap instead of saturation when the product does not fit in 32 bits. The RV32I-only rule forces the multiply into software; the leaf shift-add is the form that stays inside the instruction budget without `__muldi3`.
