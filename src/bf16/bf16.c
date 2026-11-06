#include "bf16.h"

/* Ported from 2026-hw2-baremetal/02-bf16/bf16.c (from_f32 / mul / sqrt only).
 * Symbol names match src/bf16/bf16.h.  Contract special-case deltas are
 * intentionally not applied here — edit by hand against bf16.h / golden.
 */

#define BF16_QNAN 0x7FC0u
#define BF16_PINF 0x7F80u

static uint16_t bf16_sign(uint16_t a)
{
    return (uint16_t) ((a & 0x8000u) >> 15);
}

static uint16_t bf16_exp(uint16_t a)
{
    return (uint16_t) ((a & 0x7F80u) >> 7);
}

static uint16_t bf16_mant(uint16_t a)
{
    return (uint16_t) (a & 0x7Fu);
}

static uint16_t bf16_pack(uint16_t sign, uint16_t exp, uint16_t mant)
{
    return (uint16_t) ((sign << 15) | (exp << 7) | mant);
}

static int bf16_iszero(uint16_t a)
{
    return bf16_exp(a) == 0 && bf16_mant(a) == 0;
}

uint16_t bf16_from_f32(uint32_t f32bits)
{
    if ((f32bits & 0x7F800000u) == 0x7F800000u)
        return (uint16_t) (f32bits >> 16);
    f32bits += ((f32bits >> 16) & 1u) + 0x7FFFu;
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t sign = (uint16_t) (bf16_sign(a) ^ bf16_sign(b));

    if (bf16_exp(a) == 0xFF) {
        if (bf16_mant(a))
            return a;
        if (bf16_iszero(b))
            return BF16_QNAN;
        return bf16_pack(sign, 0xFF, 0);
    }

    if (bf16_exp(b) == 0xFF) {
        if (bf16_mant(b))
            return b;
        if (bf16_iszero(a))
            return BF16_QNAN;
        return bf16_pack(sign, 0xFF, 0);
    }

    if (bf16_iszero(a) || bf16_iszero(b))
        return bf16_pack(sign, 0, 0);

    uint32_t ea = bf16_exp(a), eb = bf16_exp(b);
    uint32_t ma = bf16_mant(a), mb = bf16_mant(b);
    int32_t exp_a, exp_b;

    if (ea == 0) {
        exp_a = 1;
        while ((ma & 0x80u) == 0) {
            ma <<= 1;
            exp_a--;
        }
    } else {
        ma |= 0x80u;
        exp_a = (int32_t) ea;
    }

    if (eb == 0) {
        exp_b = 1;
        while ((mb & 0x80u) == 0) {
            mb <<= 1;
            exp_b--;
        }
    } else {
        mb |= 0x80u;
        exp_b = (int32_t) eb;
    }

    int32_t exp = exp_a + exp_b - 127;
    uint32_t mant = ma * mb;

    if (mant & 0x8000u) {
        mant >>= 8;
        exp++;
    } else {
        mant >>= 7;
    }

    mant &= 0x7Fu;

    if (exp >= 255)
        return bf16_pack(sign, 0xFF, 0);
    if (exp > 0)
        return bf16_pack(sign, exp, mant);
    if (exp < -6)
        return bf16_pack(sign, 0, 0);
    mant >>= (1 - exp);
    return bf16_pack(sign, 0, (uint16_t) mant);
}

uint16_t bf16_sqrt(uint16_t a)
{
    if (bf16_exp(a) == 0xFF) {
        if (bf16_mant(a))
            return a;
        if (bf16_sign(a))
            return BF16_QNAN;
        return a;
    }

    if (bf16_iszero(a))
        return 0;

    if (bf16_sign(a))
        return BF16_QNAN;

    if (bf16_exp(a) == 0)
        return 0;



    int32_t exp = (int32_t) bf16_exp(a) - 127;
    int32_t mant = (int32_t) bf16_mant(a);
    int32_t new_exp;

    mant |= 0x80;
    if (exp & 1) {
        mant <<= 1;
        new_exp = ((exp - 1) >> 1) + 127;
    } else {
        new_exp = (exp >> 1) + 127;
    }

    int32_t low = 90;
    int32_t high = 256;
    while (low <= high) {
        int32_t mid = (low + high) >> 1;
        int32_t sq = (mid * mid) / 128;
        if (sq <= mant)
            low = mid + 1;
        else
            high = mid - 1;
    }
    while (high > 0 && high < 0x80) {
        high <<= 1;
        new_exp--;
    }
    while (high >= 0x100) {
        high >>= 1;
        new_exp++;
    }
    if (new_exp >= 0xFF)
        return BF16_PINF;
    if (new_exp <= 0)
        return 0;
    return bf16_pack(0, new_exp, high & 0x7F);
}
