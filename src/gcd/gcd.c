#include "gcd.h"

/* Binary GCD (Quiz 2 Problem A).  Same algorithm as the host harness in
 * 2026-hw2-baremetal/03-gcd; only the symbol name matches the contract.
 */
uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    unsigned count = 0;

    if (a == 0)
        return b;
    if (b == 0)
        return a;

    while ((a % 2 == 0) && (b % 2 == 0)) {
        a >>= 1;
        b >>= 1;
        count++;
    }

    while (a != b) {
        while ((a & 1) == 0)
            a >>= 1;
        while ((b & 1) == 0)
            b >>= 1;

        if (a > b)
            a = (a - b) >> 1;
        else if (a < b)
            b = (b - a) >> 1;
        else
            break;
    }

    return a << count;
}
