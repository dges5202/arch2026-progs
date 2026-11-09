---
tags: computer-arch
---

# Assignment 2: Complete Applications on Bare-Metal RV32I
> contributed by [dges5202](https://github.com/dges5202)

NCKU CSIE Computer Architecture, Fall 2026. Follows [Assignment 2](https://hackmd.io/@sysprog/2026-arch-homework2). Graded sources are in this fork under `src/`; long-form experiment trees sit in `notes/` and `labs/`.

Style references: [2D line drawing (fixed-point)](https://hackmd.io/@sysprog/linux2022-linedraw), [BF16 sine](https://hackmd.io/@sysprog/linux2023-bf16-sine).

## Environment

| Item | Value |
| :--- | :--- |
| Repository | https://github.com/dges5202/arch2026-progs |
| Host | AMD Ryzen 7 9800X3D, Linux 6.6 (WSL2) |
| Toolchain | `riscv64-unknown-elf-gcc` 16.1.0, `-march=rv32i_zicsr -mabi=ilp32` |
| Emulator | [rv32emu](https://github.com/sysprog21/rv32emu) system emulation + `ELF_LOADER` |
| Note on timing | rv32emu: `cycle` ≡ `instret` (CPI = 1); size weighed separately with `size -A` |

---

# 1. minirubik (`rubik`)

Port of Homework 1’s 2×2 cube solver to the `arch2026-progs` contract (`rubik_solve` / `rubik_solve_asm`).

## 1.1 Principle of the code

<!-- Algorithm: IDA* + pattern database / distance tables; why it finds a shortest solution. -->

## 1.2 Mathematical foundation

<!-- State space size; move generators; distance metric; encoding of the 14-character state; what “shortest” means. -->

## 1.3 Analysis

<!-- Error / correctness against a host reference; instruction and cycle counts (`@@perf` / `make cycles`); footprint vs `RUBIK_DATA_BUDGET`. -->

## 1.4 Verification

<!-- micro-test coverage: distance-0..11 samples, single moves, invalid states, buffer sizes; how they establish correctness. -->

## 1.5 Optimization

Baseline numbers: [`notes/rubik/bench-v1.md`](rubik/bench-v1.md). Depth-11 = hardest God’s-number layer (**2644** states); full 3.67M C check is separate.

| Ver | Change | d11 mean (ASM) | vs GCC `-O2` d11 | 5ST (Ripes) | Why |
|-----|--------|---------------:|-----------------:|------------:|-----|
| **v1** | IDA* + waterfall `s→inv→σ→σ²`; C-style apply; parse `sll` | **824,948** | **2.17× faster** (C mean 1,789,077) | *TBD* | First correct ASM; beats `-O2` on all 2644 d11 states |
| | | p50 757k / max 4.54M; harness 6-depth: ASM 162k vs C 331k (2.04×) | | | Detail: [`rubik/bench-v1.md`](rubik/bench-v1.md) |
| **v2** | Reorder `s→σ→σ²→inv`; `PDB_NIBBLE`; `r==0` gate | **909,588** | **1.97× faster** | *TBD* | **+10.3% vs v1** (regress); 52/52, d11 bad=0; still beats C on all 2644 |
| | | p50 828k / max 5.06M; harness ASM 174k (+6.9% vs v1) | | | Lesson: measure each micro-step; log [`d11_cmp_cO2_vs_asm_v2.txt`](rubik/results/d11_cmp_cO2_vs_asm_v2.txt) |

Ripes **5ST**: same `rubik_solve_asm` on min/max sample states in `notes/rubik/results/d11_ripes_sample_states.txt` (emu does not model 5-stage).

## 1.6 RV32I improvements

<!-- Cost of no M/F, no Ripes ecall/LED; how hand-written assembly recovers speed/size vs gcc. -->

## 1.7 Real-world applications

<!-- Where IDA* / pattern databases show up; how memory and instruction budgets map to embedded constraints. -->

---

# 2. BFloat16 (`bf16`)

Quiz 1 Problem B, graded in this fork: three leaves — [`bf16_from_f32`](https://github.com/dges5202/arch2026-progs/blob/main/src/bf16/bf16.c) / [`bf16_mul`](https://github.com/dges5202/arch2026-progs/blob/main/src/bf16/bf16.c) / [`bf16_sqrt`](https://github.com/dges5202/arch2026-progs/blob/main/src/bf16/bf16.c) and the matching `*_asm` in [`bf16.S`](https://github.com/dges5202/arch2026-progs/blob/main/src/bf16/bf16.S) — contract in [`bf16.h`](https://github.com/sysprog21/arch2026-progs/blob/main/src/bf16/bf16.h). Harness numbers below come from `scripts/driver.py --prog bf16` on this tree; a short log sits in [`notes/bf16/bench.md`](bf16/bench.md). The separate personal truncate/IEEE lab lives outside this repo at `homework/bf16` (add/sub/div and twins; not graded here).

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

Quiz 2 Problem A (Stein / binary GCD). Sources and the full optimization log: [`03-gcd/`](https://github.com/dges5202/2026-hw2-baremetal/tree/9780d53/03-gcd). Standalone draft that this section consolidates: [`03-gcd/notes/hackmd.md`](https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/notes/hackmd.md). Bench detail: [`03-gcd/notes/bench.md`](https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/notes/bench.md).

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
/* https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/gcd.c#L12-L40 */
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

Every row is gcd-only retired over the six pairs (CPI 1.00 on rv32emu). Full per-pair windows: [`bench.md`](https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/notes/bench.md).

| Commit | Change | Retired | `.text` | `gcd` B | Δ |
| :--- | :--- | ---: | ---: | ---: | ---: |
| [`958ff64`](https://github.com/dges5202/2026-hw2-baremetal/commit/958ff64) | CSR baseline | 652 | 792 | 124 | — |
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
/* https://github.com/dges5202/2026-hw2-baremetal/blob/9780d53/03-gcd/gcd.S#L225-L264 */
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

Quiz 3 Problem C, ported as `src/fixed/` in the harness. Contract: [`fixed.h`](https://github.com/dges5202/2026-hw2-baremetal/blob/2b3c782/04-logic/fixed.h). Working copies and the commit log live under [`04-logic/`](https://github.com/dges5202/2026-hw2-baremetal/tree/2b3c782/04-logic) until they are synced into an `arch2026-progs` fork. Gate-delay and sequential-circuit parts of the quiz are not programs and are not ported.

Pinned assembly at the end of the `op1`–`op3` tightening sequence: [`fixed.S@2b3c782`](https://github.com/dges5202/2026-hw2-baremetal/blob/2b3c782/04-logic/fixed.S). Bench log: [`notes/bench.md`](https://github.com/dges5202/2026-hw2-baremetal/blob/2b3c782/04-logic/notes/bench.md).

## 4.1 Principle of the code

Four routines. The first three rebuild addition-family ops from bitwise logic; the fourth is a Q11.20 multiply.

**`op1(a, b, n)`** is a carry-loop adder. One bit obeys $\mathrm{sum}=a\oplus b$ and $\mathrm{carry}=(a\land b)\ll 1$. Applied to whole words, each pass replaces $(a,b)$ with $(\mathrm{sum},\mathrm{carry})$ until the carry word is zero. The return value is $a+b\bmod 2^{32}$; `*n` is the number of passes (`op1(x,0)` → `*n=0`; `op1(0xFFFF,1)` → `0x10000` in 17 passes).

**`op2(a, b)`** is $a-b\bmod 2^{32}$. The bitwise model is `op1(a, op1(~b, 1))`; the budget asks for a plain `sub`, which yields the same bits.

**`op3(a, b)`** is $\lfloor(a+b)/2\rfloor$ of the exact sum. `(a+b)>>1` in `uint32_t` overflows; the overflow-free form is $(a\gg 1)+(b\gg 1)+(a\land b\land 1)$.

**`q_mul(a, b)`** multiplies two Q11.20 values: store $A$ means $A/2^{20}$. Form the 64-bit product, add $2^{19}$, arithmetic-shift right by 20 (ties toward $+\infty$), keep the low 32 bits (wrap, no saturation).

```c
/* https://github.com/dges5202/2026-hw2-baremetal/blob/2b3c782/04-logic/fixed.c */
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
/* https://github.com/dges5202/2026-hw2-baremetal/blob/2b3c782/04-logic/fixed.S */
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
