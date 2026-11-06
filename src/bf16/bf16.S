# Ported from 2026-hw2-baremetal/02-bf16/bf16.S
# (u32_to_bf16 / bf16_mul / bf16_sqrt only). Entry names get _asm suffix.
# Contract special-case deltas not applied — edit by hand against bf16.h.

    .text
    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    /* a0 = f32 bits  ->  a0 = bf16 bits
     *
     * Inf/NaN (exp bits == 0x7F800000): copy the top 16 bits, no rounding.
     * Else: round-to-nearest-even,
     *   x += ((x >> 16) & 1) + 0x7FFF, then x >> 16.
     *
     * Rounding is the fall-through arm: finite inputs are the common case,
     * and rv32emu still charges 1 for a taken beq.  Inf/NaN is beq away.
     * Inf/NaN is rare, so there is no branchless mux: the two arms do
     * different work, and a mask-select would cost more than this beq.
     * (The label name is leftover from when this arm was the taken path.)
     */
    lui     t0, 0x7F800                                 # t0 = 0x7F800000
    and     t1, a0, t0                                  # t1 = (a0 & 0x7F800000)
    beq     t0, t1, bf16_from_f32_asm_infnan                # Inf/NaN -> copy top 16
    srli    t0, a0, 16                                  # t0 = (a0 >> 16)
    andi    t1, t0, 1                                   # t1 = (a0 >> 16) & 1
    li      t2, 0x7FFF                                  # t2 = 0x7FFF
    add     t1, t1, t2                                  # t1 = RNE bias
    add     a0, a0, t1                                  # round
    srli    a0, a0, 16                                  # a0 = bf16 bits
    ret

bf16_from_f32_asm_infnan:
    srli    a0, a0, 16                                  # (f32bits >> 16)
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm


    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    /* a0 = a, a1 = b  ->  a0 = a*b
     *
     * Architecture (A layout + B only in the cold path):
     *
     *   ABI door: a0/a1, then mv a6=a a7=b.  Unpack once:
     *     t4=sign_a t5=exp_a t6=mant_a
     *     a3=sign_b a4=exp_b a5=mant_b
     *
     *   Gate (every call, cheap): special if exp==0xFF or (exp==0 &&
     *   mant==0), either side.  Built from t5/a4 already in registers —
     *   and slli 17 for ±0.  No 0x7F80 on the hot gate.
     *     beq  mul_specials          rare
     *     fall through               both finite nonzero
     *
     *   Hot path: implicit 1, 8x8 shift-and-add, exp_a+exp_b-bias,
     *   renormalize, XOR signs, pack into a0, ret.
     *
     *   Cold path (code sits after that ret): classify by magnitude,
     *     mag = bits 14..0 = slli 17 / srli 17  (NOT slli 1 / srli 1)
     *     class bits: NaN=1, Inf=2, zero=4  (per side; or into t0)
     *
     *   Decision fall-through (label order is load-bearing):
     *     (t0 & 1) != 0     -> nan
     *     t0 == 6           -> nan          (Inf*0 / 0*Inf; not 4&2)
     *     (t0 & 2) != 0     -> inf
     *     else fall into bf16_mul_zero      (no andi 4 / bnez)
     *
     *   Why the last arm can fall through: gate only enters specials when
     *   a side is 0xFF or ±0, so after NaN / Inf*0 / Inf are peeled off the
     *   only remainder is a zero product.  bf16_mul_zero must sit immediately
     *   after the Inf beq; nan/inf labels are out-of-line rets.
     *
     *   Do not multiply first and "fix" later: Inf*0 would not become NaN.
     *   Do not run B on the gate: 1*2 would pay lui 0x7F80 every time.
     */
    mv      a6, a0                                      # a6 = a
    mv      a7, a1                                      # a7 = b

    srli    t4, a6, 15                                  # t4 = sign_a
    srli    t5, a6, 7
    andi    t5, t5, 0xFF                                # t5 = 8-bit exp_a
    andi    t6, a6, 0x7F                                # t6 = 7-bit mant_a

    srli    a3, a7, 15                                  # a3 = sign_b
    srli    a4, a7, 7
    andi    a4, a4, 0xFF                                # a4 = 8-bit exp_b
    andi    a5, a7, 0x7F                                # a5 = 7-bit mant_b
    xor     a3, t4, a3                                  # a3 = sign_xor

    # decision exp == 0xFF
    li      t0, 0xFF
    beq     t5, t0, bf16_mul_specialcase_ff_a
    beq     a4, t0, bf16_mul_specialcase_ff_b

    # decision exp == 0 && mant == 0 (±0 via slli 17)
    slli    t0, a6, 17                                  # t0 = (a << 17)
    beqz    t0, bf16_mul_signed_zero
    slli    t0, a7, 17                                  # t0 = (b << 17)
    beqz    t0, bf16_mul_signed_zero

    # Normal case — attach implicit 1 when exp != 0
    # a side
    beqz    t5, bf16_mul_ea_zero
    ori     t6, t6, 0x80
    j       bf16_mul_ea_after

bf16_mul_ea_zero:
    li      t5, 1

bf16_mul_ea_loop:
    andi    t0, t6, 0x80
    bnez    t0, bf16_mul_ea_after
    slli    t6, t6, 1
    addi    t5, t5, -1
    j       bf16_mul_ea_loop

bf16_mul_ea_after:

    
    # b side
    beqz    a4, bf16_mul_eb_zero
    ori     a5, a5, 0x80
    j       bf16_mul_eb_after

bf16_mul_eb_zero:
    li      a4, 1

bf16_mul_eb_loop:
    andi    t0, a5, 0x80
    bnez    t0, bf16_mul_eb_after
    slli    a5, a5, 1
    addi    a4, a4, -1
    j       bf16_mul_eb_loop

bf16_mul_eb_after:

    add     a4, a4, t5
    addi    a4, a4, -127

    # After gate + this setup (hot path only):
    #   live:  a3=sign_xor  a4=exp_a+exp_b-127  a5=mant_b  t6=mant_a
    #          a6=orig a    a7=orig b   (drop when implicit-1 is on)
    #   free:  a0 a1 a2  t0 t1 t2 t3 t4 t5

    # mul_loop: mant_a * mant_b (8-bit, branchless bit via mask)
    li      a1, 0                                       # a1 = product

bf16_mul_mul_loop:
    andi    t0, a5, 1
    srli    a5, a5, 1
    sub     t1, x0, t0
    and     t2, t6, t1
    add     a1, a1, t2
    slli    t6, t6, 1
    bnez    a5, bf16_mul_mul_loop

    li      t0, 0x8000
    and     t1, a1, t0                                  # t1 = a1 & 0x8000
    beq     t1, x0, bf16_mul_shift
    srli    a1, a1, 8                                   # a1 = mant >> 8
    andi    a1, a1, 0x7F                                # a1 = (mant >> 8) & 0x7F
    addi    a4, a4, 1                                   # a4 = exp ++
    j       bf16_mul_shift_out

bf16_mul_shift:
    srli    a1, a1, 7                                   # a1 = mant >> 7
    andi    a1, a1, 0x7F                                # a1 = (mant >> 7) & 0x7F

bf16_mul_shift_out:
    li      t0, 255
    bge     a4, t0, bf16_mul_inf          # ≥255 → Inf

    bgtz    a4, bf16_mul_pack             # >0 → normal pack

    # exp <= 0
    li      t0, -6
    blt     a4, t0, bf16_mul_signed_zero  # < -6 → 0

    li      t0, 1
    sub     t0, t0, a4
    srl     a1, a1, t0
    slli    a0, a3, 15
    or      a0, a0, a1
    ret

bf16_mul_pack:
    slli    a0, a3, 15
    slli    a4, a4, 7
    or      a0, a0, a4
    or      a0, a0, a1
    ret

bf16_mul_specialcase_ff_a:
    beqz    t6, bf16_mul_ff_a_inf      # mant==0 → Inf
    mv      a0, a6                     # NaN → a
    ret

bf16_mul_ff_a_inf:
    slli    t0, a7, 17                 # mag_b
    bnez    t0, bf16_mul_inf           # b≠0 → Inf
    li      a0, 0x7FC0                 # Inf*0
    ret

bf16_mul_specialcase_ff_b:
    beqz    a5, bf16_mul_ff_b_inf      # mant==0 → Inf
    mv      a0, a7                     # NaN → b
    ret

bf16_mul_ff_b_inf:
    slli    t0, a6, 17                 # mag_a
    bnez    t0, bf16_mul_inf           # a≠0 → Inf
    li      a0, 0x7FC0                 # Inf*0
    ret

bf16_mul_inf:         
    slli    a0, a3, 15
    li      t0, 0x7F80
    or      a0, a0, t0
    ret

bf16_mul_signed_zero:
    slli    a0, a3, 15
    ret

    .size   bf16_mul_asm, .-bf16_mul_asm


    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    /*
     * bf16_sqrt — unary; mirrors bf16.c.
     *
     * Algorithm choice (current): binary search on mid in [90, 256] with
     * sq = (mid*mid)/128 each probe.  No mul insn → each square is a
     * software mask-mul (~15–20 instret); ~8 probes → often 150+ instret
     * on the hot path.  Kept because it matches bf16.c bit-exactly and is
     * easy to audit against the host tests (full 16-bit space checked).
     *
     * Alternate (not implemented): digit-recurrence / non-restoring
     * integer square root on the normalized significand — ~7–8
     * shift+add/sub steps, no multiply; likely 3–4× fewer instret on
     * rv32emu.  Requires C and asm to move together or gold is no longer
     * bit-exact with bf16.c; asm-only rewrite diverges ulps.
     *
     * Rationale (no soft-float lib):
     *   RV32I has no fpu and no mul/div.  Host C uses integer mid*mid and
     *   a fixed-point binary search; asm mirrors that with shift-and-add.
     *
     * Gate order is load-bearing (matches C: return-a before sign->NaN):
     *   1) ±0 via slli 17          -> ret a0 unchanged (-0 keeps sign)
     *   2) exp==0xFF               -> specials (NaN / ±Inf)
     *   3) sign!=0                 -> canonical NaN (negative finite)
     *   4) else                    -> hot path
     * Putting sign before 0xFF would turn -NaN into 0x7FC0; C returns a.
     *
     * +------+---------------------------+----------------------------------+
     * | reg  | gate / unpack             | hot                              |
     * +------+---------------------------+----------------------------------+
     * | a0   | ABI in; keep on ret-a     | pack at epilogue only            |
     * | a1   | —                         | mid*mid product, then sq = >>7   |
     * | a2   | —                         | mul: mid bits (right-shift)      |
     * | a3   | —                         | mul: mid addend (left-shift)     |
     * | a4   | —                         | high (init 256; pack high&0x7F)  |
     * | a5   | —                         | low  (init 90)                   |
     * | a6   | original a                | mid each bisect (never mul-clob) |
     * | a7   | — (no orig b)             | new_exp until pack               |
     * | t0-2 | gate / mul scratch        | mask-mul temps                   |
     * | t4   | sign_a                    | stays 0 on hot; pack as sign     |
     * | t5   | exp → unbiased            | free after new_exp (not a count) |
     * | t6   | mant 7-bit                | |0x80; odd<<1; bisect cmp target |
     * +------+---------------------------+----------------------------------+
     *
     * Hot math (same as C):
     *   Unbias exp, attach implicit 1.  Odd unbiased exp: mant<<=1 and
     *   exp-=1 so the remaining exp is even; then
     *     new_exp = (exp >> 1) + 127
     *   Odd and even share that formula — only the mant shift differs —
     *   so even beqz-skips the shift/addi and falls into one srai+addi.
     *   Use srai (not srli): unbiased exp can be negative (e.g. 0.5 -> -1).
     *
     *   Bisect mid in [90, 256] with sq = (mid*mid)/128 against mant.
     *   sq <= mant -> low = mid+1; else high = mid-1.  Result mant is
     *   high&0x7F (C).  Unsigned compares (bltu/bgeu): all values >= 0.
     *
     *   mid*mid: same branchless mask idiom as bf16_mul, but keep a6=mid
     *   (need mid±1 after).  Work on a2/a3 copies.  Stop with bnez a2
     *   (no fixed 9-count) — remaining zero bits cannot change the product.
     *
     *   Compare fall-through: common arm (sq <= mant) falls into low=mid+1;
     *   rare arm branches to high=mid-1.  Still one j to join.
     */
    mv      a6, a0                                      # a6 = original a (ret-a paths)

    srli    t4, a6, 15                                  # t4 = sign_a
    srli    t5, a6, 7
    andi    t5, t5, 0xFF                                # t5 = 8-bit exp_a
    andi    t6, a6, 0x7F                                # t6 = 7-bit mant_a

    # --- gate ---------------------------------------------------------------
    # ±0 first so -0 is not treated as negative finite
    li      t0, 0xFF
    beq     t0, t5, bf16_sqrt_specialcase_ff

    slli    t0, a6, 17                                  # drop sign; mag==0?
    beqz    t0, bf16_sqrt_zero

    bnez    t4, bf16_sqrt_nan                           # negative finite -> NaN

    beqz    t5, bf16_sqrt_zero                          # exp_a == 0, ret 0

    # --- hot: unbias + implicit 1 ------------------------------------------
    # a6 may be overwritten from here (only mid uses it after this)
    addi    t5, t5, -127                                # t5 = unbiased exp
    ori     t6, t6, 0x80                                # t6 = mant | implicit 1

    # odd: mant<<=1, exp-=1; even: skip into shared new_exp
    andi    t0, t5, 1
    beqz    t0, bf16_sqrt_newexp_even
    slli    t6, t6, 1                                   # odd: fold the extra 2^1 into mant
    addi    t5, t5, -1                                  # odd: make exp even

bf16_sqrt_newexp_even:
    srai    a7, t5, 1                                   # arithmetic: exp may be negative
    addi    a7, a7, 127                                 # a7 = new_exp

    # --- binary search for fixed-point sqrt(mant) --------------------------
    li      a5, 90                                      # low
    li      a4, 256                                     # high (inclusive range as in C)

bf16_sqrt_bisection_loop:
    add     a6, a4, a5
    srli    a6, a6, 1                                   # a6 = mid = (low+high)>>1

    # mid*mid with mask adds; a2=bits, a3=shifted addend; a6 stays mid
    li      a1, 0                                       # product
    mv      a2, a6
    mv      a3, a6

bf16_sqrt_mul_loop:
    andi    t0, a2, 1                                   # next multiplier bit
    srli    a2, a2, 1
    sub     t1, x0, t0                                  # 0 or 0xFFFFFFFF
    and     t2, a3, t1                                  # addend or 0
    add     a1, a1, t2
    slli    a3, a3, 1                                   # next power of mid
    bnez    a2, bf16_sqrt_mul_loop                      # early out when bits gone

    srli    a1, a1, 7                                   # sq = (mid*mid)/128
    bltu    t6, a1, bf16_sqrt_bisection_loop_high       # mant < sq -> shrink high
    addi    a5, a6, 1                                   # fall-through: low = mid+1
    j       bf16_sqrt_bisection_loop_cont

bf16_sqrt_bisection_loop_high:
    addi    a4, a6, -1                                  # high = mid-1

bf16_sqrt_bisection_loop_cont:
    bgeu    a4, a5, bf16_sqrt_bisection_loop            # while high >= low


bf16_sqrt_renorm_lo:
    beqz    a4, bf16_sqrt_renorm_hi      # high==0 就別左移
    li      t0, 0x80
    bgeu    a4, t0, bf16_sqrt_renorm_hi
    slli    a4, a4, 1
    addi    a7, a7, -1
    j       bf16_sqrt_renorm_lo
bf16_sqrt_renorm_hi:
    li      t0, 0x100
    bltu    a4, t0, bf16_sqrt_pack_check
    srli    a4, a4, 1
    addi    a7, a7, 1
    j       bf16_sqrt_renorm_hi
bf16_sqrt_pack_check:
    li      t0, 0xFF
    bge     a7, t0, bf16_sqrt_pinf       # → +Inf
    blez    a7, bf16_sqrt_zero           # 重用 +0
    # pack sign=0
    slli    a0, a7, 7
    andi    t0, a4, 0x7F
    or      a0, a0, t0
    ret
bf16_sqrt_pinf:
    li      a0, 0x7F80
    ret

    # --- cold: exp==0xFF ---------------------------------------------------
    # NaN (mant!=0): return original a (payload / sign), same as +Inf path.
    # -Inf: produce 0x7FC0.  +Inf falls through to ret with a0 unchanged.
bf16_sqrt_specialcase_ff:
    beqz    t6, bf16_sqrt_mant_0
    ret

bf16_sqrt_mant_0:
    bnez    t4, bf16_sqrt_nan
    ret

bf16_sqrt_nan:
    li      a0, 0x7FC0
    ret

bf16_sqrt_zero:
    li      a0, 0
    ret                                                 # ±0: a0 still original
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm


