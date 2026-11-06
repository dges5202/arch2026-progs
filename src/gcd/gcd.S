# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# Core only: the arch2026-progs harness owns start, tests, print, and counters.
# No ecall, CSR, or frame.  Ported from 2026-hw2-baremetal/03-gcd/gcd.S
# (label gcd … return_b), with symbols renamed under the gcd_ prefix.
#
# Leaf (a / t only):
#   a0 = a / return     a1 = b
#   t0 = count (shared twos)
#   t1 = scratch (a|b; parity of a or of b)
#   t2 = scratch (parity, nibble, (a|b) & mask)
#   t5 = mask width k (16..1), even_loop_skip only
#   t6 = low-ones mask,         even_loop_skip only
#
# Layout notes (keep the fall-throughs):
#   - strip_a cannot sit above larger_b without that `j`: falling would
#     subtract the wrong way.
#   - After a>b, b is still odd, so only strip_a runs.  After larger_b,
#     only strip_b.  First entry uses strip_a1 then falls into strip_b
#     so both sides are odd before the first odd_sub.
#   - even_loop_skip, if taken, falls into strip_a1 (no j).  The 1-bit
#     shortcut cannot: it sits above skip, so it `j strip_a1`.
#
# Branchless odd_sub was measured slower on rv32emu; keep branched fall-through.

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beq     a0, x0, gcd_return_a                # a == 0: return b
    beq     a1, x0, gcd_return_b                # b == 0: return a
    li      t0, 0                               # t0 = count

# even_loop: fold shared twos into t0.  k = ctz(a|b) can be large, so a
# nibble peek then a binary 16/8/4/2/1 walk.
gcd_even_loop:
    or      t1, a0, a1                          # t1 = a | b
    andi    t2, t1, 1                           # t2 = parity
    bne     t2, x0, gcd_strip_a1                # one side odd: stop

    andi    t2, t1, 0xF                         # t2 = (a | b) & 0xF
    beq     t2, x0, gcd_even_loop_skip          # k >= 4: binary

gcd_even_loop_shortcut:
    srli    a0, a0, 1                           # a >>= 1
    srli    a1, a1, 1                           # b >>= 1
    addi    t0, t0, 1                           # count++
    or      t1, a0, a1                          # t1 = a | b
    andi    t2, t1, 1                           # t2 = parity
    beq     t2, x0, gcd_even_loop_shortcut      # still both even
    j       gcd_strip_a1

gcd_even_loop_skip:
    li      t5, 16                              # t5 = k
    li      t6, 0xFFFF                          # t6 = 16 low ones

gcd_even_loop_inner:
    or      t1, a0, a1                          # t1 = a | b
    and     t2, t1, t6                          # t2 = (a | b) & mask
    bne     t2, x0, gcd_even_loop_inner1        # low t5 bits not all 0

    srl     a0, a0, t5                          # a >>= k
    srl     a1, a1, t5                          # b >>= k
    add     t0, t0, t5                          # count += k

gcd_even_loop_inner1:
    srli    t5, t5, 1                           # k /= 2
    srl     t6, t6, t5                          # mask = low k ones
    or      t1, a0, a1                          # t1 = a | b
    andi    t2, t1, 1                           # t2 = parity
    beq     t2, x0, gcd_even_loop_inner         # still both even

# strip_*: 1-bit peels.  After odd_sub both sides were odd, so a-b is even.
gcd_strip_a1:
    andi    t1, a0, 1                           # t1 = a & 1
    bne     t1, x0, gcd_strip_b                 # a odd
gcd_strip_a1_inner:
    srli    a0, a0, 1                           # a >>= 1
    andi    t1, a0, 1                           # t1 = a & 1
    beq     t1, x0, gcd_strip_a1_inner          # a still even

gcd_loop:
gcd_strip_b:
    andi    t1, a1, 1                           # t1 = b & 1
    bne     t1, x0, gcd_odd_sub                 # b odd
gcd_strip_b_inner:
    srli    a1, a1, 1                           # b >>= 1
    andi    t1, a1, 1                           # t1 = b & 1
    beq     t1, x0, gcd_strip_b_inner           # b still even
                                                # fall into odd_sub

# odd_sub: both odd.  Equal before sub.  Unsigned, srli.
gcd_odd_sub:
    beq     a0, a1, gcd_done                    # equal: before sub
    bltu    a0, a1, gcd_larger_b                # a < b
    sub     a0, a0, a1                          # a = a - b
    srli    a0, a0, 1                           # fall into strip_a

gcd_strip_a:
    andi    t1, a0, 1                           # t1 = a & 1
    bne     t1, x0, gcd_odd_sub                 # a odd
gcd_strip_a_inner:
    srli    a0, a0, 1                           # a >>= 1
    andi    t1, a0, 1                           # t1 = a & 1
    beq     t1, x0, gcd_strip_a_inner           # a still even
    j       gcd_odd_sub                         # do not fall into larger_b

gcd_larger_b:
    sub     a1, a1, a0                          # b = b - a
    srli    a1, a1, 1
    j       gcd_strip_b

gcd_done:
    sll     a0, a0, t0                          # put shared twos back
    ret

gcd_return_a:
    mv      a0, a1                              # a0 = b
    ret

gcd_return_b:
    ret                                         # a0 already holds a
    .size   gcd_u32_asm, .-gcd_u32_asm
