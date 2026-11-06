#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int count = 0;

    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a = a ^ b;
        b = c;
        count++;
    }
    *n = count;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    if (a >= b)
        return a - b;
    return -(b - a);
}

uint32_t op3(uint32_t a, uint32_t b)
{
    int a_last_bit = a & 1;
    int b_last_bit = b & 1;
    a >>= 1;
    b >>= 1;
    return a + b + (a_last_bit & b_last_bit);
}

int32_t q_mul(int32_t a, int32_t b)
{
    /* Soft 64-bit product with 16x16 parts so the RV32I link needs no __muldi3.
     */
    int neg = (a < 0) != (b < 0);
    uint32_t ua = (a < 0) ? -(uint32_t) a : (uint32_t) a;
    uint32_t ub = (b < 0) ? -(uint32_t) b : (uint32_t) b;
    uint32_t a_lo = ua & 0xffffu;
    uint32_t a_hi = ua >> 16;
    uint32_t b_lo = ub & 0xffffu;
    uint32_t b_hi = ub >> 16;
    uint32_t p00 = a_lo * b_lo;
    uint32_t p01 = a_lo * b_hi;
    uint32_t p10 = a_hi * b_lo;
    uint32_t p11 = a_hi * b_hi;
    uint32_t mid = p01 + p10;
    uint32_t mid_hi = mid < p01;
    uint32_t lo = p00 + (mid << 16);
    uint32_t t = lo < p00;
    uint32_t hi = p11 + (mid >> 16) + (mid_hi << 16) + t;
    uint32_t round = 1u << 19;

    if (neg) {
        t = lo;
        lo = -lo;
        hi = (t == 0) ? -hi : ~hi;
    }

    t = lo;
    lo = lo + round;
    if (lo < t)
        hi++;

    return (int32_t) ((lo >> 20) | (hi << 12));
}
