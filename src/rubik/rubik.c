/* Port of HW1 ida.c → rubik_solve. Same search and tables; API matches rubik.h.
 * Edit this file yourself for HW2 (new tables / heuristic / etc.).
 */
#include "rubik.h"
#include "tables.h"

#include <stddef.h>
#include <stdint.h>


enum { CUBIES = 7, FACES = 3, MOVES = 9, MAX_DEPTH = 11 };
/* o = o0*3^5 + ... + o5  (first six orientations) */
typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

static unsigned rank_ori_state(const state_t *s)
{
    unsigned o = 0;
    for (unsigned i = 0; i < 6; ++i)
        o = (o << 1) + o + s->o[i]; /* *3 + digit */
    return o;
}

/* index = (a<<10) + o ; a from positions of cubies 0,3,6 (stride 1024) */
static unsigned pdb_index(const state_t *s)
{
    uint8_t pos[CUBIES];
    for (unsigned i = 0; i < CUBIES; ++i)
        pos[s->p[i]] = (uint8_t) i;
    unsigned a = rubik_arank[pos[0] << 6 | pos[3] << 3 | pos[6]];
    unsigned o = rank_ori_state(s);
    return (a << 10) + o;
}

static unsigned pdb_get(unsigned idx)
{
    return (rubik_pdb[idx >> 1] >> ((idx & 1u) << 2)) & 15u;
}

static unsigned h_pos3ori(const state_t *s)
{
    return pdb_get(pdb_index(s));
}



static const char *const move_names[MOVES] = {"R",  "R2", "R'", "B", "B2",
                                              "B'", "D",  "D2", "D'"};

static const uint8_t face_of[MOVES] = {0, 0, 0, 1, 1, 1, 2, 2, 2};
static const uint8_t turns_of[MOVES] = {1, 2, 3, 1, 2, 3, 1, 2, 3};
static const uint8_t source[3][8] = {
    {1, 4, 2, 0, 3, 5, 6, 9},
    {0, 1, 2, 4, 5, 6, 3, 9},
    {0, 2, 5, 3, 1, 4, 6, 9},
};
static const uint8_t twist[3][8] = {
    {1, 2, 0, 2, 1, 0, 0, 9},
    {0, 0, 0, 1, 2, 1, 2, 9},
    {0, 0, 0, 0, 0, 0, 0, 9},
};
static const uint8_t sig[7] = {2, 5, 6, 1, 4, 3, 0};
static const uint8_t kk[7] = {0, 1, 0, 1, 0, 1, 0};
/* Admissible h = max of pos3ori lookups. For now only h0(s).
 * TODO later (same table, tighter bound):
 *   - inverse s^{-1}: build inv state, h = max(h, h_pos3ori(&inv))
 *   - conjugate σ / σ² (diagonal sym3): h = max(h, h_pos3ori(&conj), ...)
 * Do not use N-index tricks; transform the cubie state, then re-index.
 */
/* RV32I bare-metal: no libgcc __modsi3 — keep ori in 0..2 by subtract. */
static unsigned mod3(unsigned x)
{
    while (x >= 3)
        x -= 3;
    return x;
}

static state_t invert(const state_t *s)
{
    state_t r;
    for (unsigned i = 0; i < CUBIES; ++i) {
        unsigned c = s->p[i];
        r.p[c] = i;
        r.o[c] = (uint8_t) mod3(3 - s->o[i]);
    }
    return r;
}

static state_t sym3(const state_t *s)
{
    state_t y;
    for (unsigned i = 0; i < CUBIES; ++i) {
        y.p[sig[i]] = sig[s->p[i]];
        y.o[sig[i]] = (uint8_t) mod3(s->o[i] + 3 + kk[i] - kk[s->p[i]]);
    }
    return y;
}

static unsigned heuristic(const state_t *s)
{
    unsigned h = h_pos3ori(s);
    /* TODO: inv + sym3 max here */
    state_t inv = invert(s);
    unsigned inv_h = h_pos3ori(&inv);
    if (inv_h > h)
        h = inv_h;

    state_t sym = sym3(s);
    unsigned sym3_h = h_pos3ori(&sym);
    if (sym3_h > h)
        h = sym3_h;

    state_t conj = sym3(&sym);
    unsigned conj_h = h_pos3ori(&conj);
    if (conj_h > h)
        h = conj_h;

    return h;
}

static int solved(const state_t *s)
{
    for (unsigned i = 0; i < CUBIES; ++i) {
        if (s->p[i] != i)
            return 0;
        if (s->o[i] != 0)
            return 0;
    }
    return 1;
}

static state_t apply(const state_t s, unsigned m)
{
    unsigned f = face_of[m];
    unsigned from;
    state_t cur = s;
    state_t nxt;

    for (unsigned t = 0; t < turns_of[m]; ++t) {
        for (unsigned i = 0; i < 7; ++i) {
            from = source[f][i];
            nxt.p[i] = cur.p[from];
            nxt.o[i] = (uint8_t) mod3(cur.o[from] + twist[f][i]);
        }
        cur = nxt;
    }
    return cur;
}

static int search(const state_t *s, unsigned bound, uint8_t path[MAX_DEPTH])
{
    state_t state[MAX_DEPTH + 1];
    uint8_t next[MAX_DEPTH + 1];

    unsigned g = 0;
    state[0] = *s;
    next[0] = 0;
    for (;;) {
        if (next[g] == MOVES) {
            if (g == 0)
                return -1;
            --g;
            continue;
        }
        unsigned m = next[g]++;

        if (g > 0 && face_of[m] == face_of[path[g - 1]]) {
            next[g] += 2;
            continue;
        }

        state_t child = apply(state[g], m);

        path[g] = (uint8_t) m;

        if (solved(&child))
            return (int) g + 1;

        /* Need room for this child under bound. Also avoids unsigned
         * underflow when bound==0 (pos3ori can give h==0 on unsolved). */
        if (bound < g + 1)
            continue;
        unsigned r = bound - g - 1;
        if (r == 0)
            continue;
        if (heuristic(&child) > r)
            continue;

        state[g + 1] = child;
        next[g + 1] = 0;
        ++g;
    }
}

static int solve(const state_t *s, uint8_t path[MAX_DEPTH])
{
    if (solved(s))
        return 0;

    for (unsigned bound = heuristic(s); bound <= MAX_DEPTH; ++bound) {
        int len = search(s, bound, path);
        if (len >= 0)
            return len;
    }
    return -1;
}

/* Reject short inputs before reading past NUL (empty string / ASan). */
static int parse_state(const char *in, state_t *s)
{
    unsigned seen = 0, sum = 0;
    for (unsigned i = 0; i < 2 * CUBIES; ++i)
        if (in[i] == '\0')
            return 0;
    if (in[2 * CUBIES] != '\0')
        return 0;
    for (unsigned i = 0; i < 2 * CUBIES; ++i) {
        unsigned limit = i < CUBIES ? CUBIES : 3;
        if (in[i] < '1' || (unsigned) (in[i] - '0') > limit)
            return 0;
        unsigned v = (unsigned) (in[i] - '1');
        if (i < CUBIES) {
            if (seen & (1U << v))
                return 0;
            seen |= 1U << v;
            s->p[i] = (uint8_t) v;
        } else {
            sum += v;
            s->o[i - CUBIES] = (uint8_t) v;
        }
    }
    while (sum >= 3)
        sum -= 3;
    return sum == 0;
}

static size_t format_need(const uint8_t *path, int n)
{
    if (n == 0)
        return 1;
    size_t len = 0;
    for (int i = 0; i < n; ++i) {
        const char *name = move_names[path[i]];
        while (*name++)
            ++len;
        if (i + 1 < n)
            ++len;
    }
    return len + 1;
}

static void format_path(const uint8_t *path, int n, char *out)
{
    char *p = out;
    for (int i = 0; i < n; ++i) {
        if (i)
            *p++ = ' ';
        const char *name = move_names[path[i]];
        while (*name)
            *p++ = *name++;
    }
    *p = '\0';
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    state_t s;
    if (!parse_state(state, &s))
        return -1;

    uint8_t path[MAX_DEPTH];
    int n = solve(&s, path);
    if (n < 0)
        return -1;

    size_t need = format_need(path, n);
    if (need > cap) {
        if (cap >= 1)
            out[0] = '\0';
        return -2;
    }
    format_path(path, n, out);
    return n;
}
