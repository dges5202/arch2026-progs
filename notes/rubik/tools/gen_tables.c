/* Host generator for the HW2 C/ASM pattern database.
 *
 * Abstraction: ordered positions of cubies {0,3,6} (210) times the full
 * orientation rank (729). The cube's order-3 diagonal conjugation (sig/kk
 * from ripe/symfind) lets the same table be looked up on three conjugates.
 * Inverse states keep the true distance, so the solver also takes max with
 * h(inverse(s)).
 *
 * Storage stride is 1024 (not 729) so the guest index is (a<<10)+o — one
 * shift+add instead of a*729. Slots o=729..1023 are unused padding.
 * Output: src/rubik/tables.h + tables.S (nibble-packed pdb + arank).
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum {
    CUBIES = 7,
    FACES = 3,
    MOVES = 9,
    NA = 210,
    NORI = 729,
    STRIDE = 1024,        /* pad past NORI for (a<<10)+o */
    NPDB = NA * NORI,     /* live entries (BFS dense) */
    NSTORE = NA * STRIDE, /* nibble index space */
};

typedef struct {
    uint8_t p[CUBIES], o[CUBIES];
} state_t;

static const uint8_t source[FACES][CUBIES] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[FACES][CUBIES] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};
static const uint8_t subset[3] = {0, 3, 6};

static state_t apply_move(state_t s, int m)
{
    int f = m / 3, turns = m % 3 + 1;
    for (int t = 0; t < turns; ++t) {
        state_t n;
        for (int i = 0; i < CUBIES; ++i) {
            int from = source[f][i];
            n.p[i] = s.p[from];
            n.o[i] = (uint8_t) ((s.o[from] + twist[f][i]) % 3);
        }
        s = n;
    }
    return s;
}

static unsigned rank3(unsigned x, unsigned y, unsigned z)
{
    unsigned y1 = y - (y > x);
    unsigned z1 = z - (z > x) - (z > y);
    return x * 30u + y1 * 5u + z1;
}

static unsigned rank_a(const state_t *s)
{
    unsigned pos[CUBIES];
    for (int i = 0; i < CUBIES; ++i)
        pos[s->p[i]] = (unsigned) i;
    return rank3(pos[subset[0]], pos[subset[1]], pos[subset[2]]);
}

static unsigned rank_o(const state_t *s)
{
    unsigned o = 0;
    for (int i = 0; i < 6; ++i)
        o = o * 3u + s->o[i];
    return o;
}

/* Dense BFS index (generation only). Guest uses a*STRIDE + o. */
static unsigned pdb_index_dense(const state_t *s)
{
    return rank_a(s) * NORI + rank_o(s);
}

int main(void)
{
    uint16_t arank[512];
    unsigned triple[NA][3];
    memset(arank, 0xFF, sizeof arank);
    for (unsigned x = 0; x < 7; ++x)
        for (unsigned y = 0; y < 7; ++y)
            for (unsigned z = 0; z < 7; ++z) {
                if (x == y || x == z || y == z)
                    continue;
                unsigned a = rank3(x, y, z);
                triple[a][0] = x;
                triple[a][1] = y;
                triple[a][2] = z;
                arank[x << 6 | y << 3 | z] = (uint16_t) a;
            }

    /* Abstract move tables from a representative of each (a, o). */
    uint16_t amove[MOVES][NA], omove[MOVES][NORI];
    for (unsigned a = 0; a < NA; ++a) {
        state_t s;
        memset(&s, 0, sizeof s);
        unsigned used = 0;
        for (int j = 0; j < 3; ++j) {
            s.p[triple[a][j]] = subset[j];
            used |= 1u << triple[a][j];
        }
        static const uint8_t filler[4] = {1, 2, 4, 5};
        int fi = 0;
        for (int i = 0; i < CUBIES; ++i)
            if (!(used >> i & 1))
                s.p[i] = filler[fi++];
        for (int m = 0; m < MOVES; ++m) {
            state_t t = apply_move(s, m);
            amove[m][a] = (uint16_t) rank_a(&t);
        }
    }
    for (unsigned o = 0; o < NORI; ++o) {
        state_t s;
        for (int i = 0; i < CUBIES; ++i)
            s.p[i] = (uint8_t) i;
        unsigned r = o, sum = 0;
        for (int i = 5; i >= 0; --i) {
            s.o[i] = (uint8_t) (r % 3);
            sum += s.o[i];
            r /= 3;
        }
        s.o[6] = (uint8_t) ((3 - sum % 3) % 3);
        for (int m = 0; m < MOVES; ++m) {
            state_t t = apply_move(s, m);
            omove[m][o] = (uint16_t) rank_o(&t);
        }
    }

    static uint8_t dist[NPDB];
    memset(dist, 0xFF, sizeof dist);
    state_t solved;
    for (int i = 0; i < CUBIES; ++i) {
        solved.p[i] = (uint8_t) i;
        solved.o[i] = 0;
    }
    unsigned ig_dense = pdb_index_dense(&solved);
    unsigned ig = rank_a(&solved) * STRIDE + rank_o(&solved);
    dist[ig_dense] = 0;
    unsigned reached = 1, maxd = 0;
    for (unsigned level = 0;; ++level) {
        unsigned found = 0;
        for (unsigned a = 0; a < NA; ++a)
            for (unsigned o = 0; o < NORI; ++o) {
                unsigned u = a * NORI + o;
                if (dist[u] != level)
                    continue;
                for (int m = 0; m < MOVES; ++m) {
                    unsigned v = (unsigned) amove[m][a] * NORI + omove[m][o];
                    if (dist[v] == 0xFF) {
                        dist[v] = (uint8_t) (level + 1);
                        if (level + 1 > maxd)
                            maxd = level + 1;
                        ++found;
                    }
                }
            }
        if (!found)
            break;
        reached += found;
    }
    if (reached != NPDB) {
        fprintf(stderr, "PDB incomplete: %u / %u\n", reached, (unsigned) NPDB);
        return 1;
    }
    fprintf(stderr,
            "pos3ori: %u entries, maxd %u, solved dense %u stride-idx %u\n",
            reached, maxd, ig_dense, ig);

    /* Pack into stride-1024 layout: idx = a*1024 + o (o < 729 live). */
    static uint8_t packed[NSTORE / 2];
    memset(packed, 0, sizeof packed);
    for (unsigned a = 0; a < NA; ++a)
        for (unsigned o = 0; o < NORI; ++o) {
            unsigned src = a * NORI + o;
            unsigned dst = a * STRIDE + o;
            uint8_t v = dist[src] & 15;
            packed[dst >> 1] |= (uint8_t) (v << ((dst & 1) * 4));
        }

    const char *out_path = "src/rubik/tables.h";
    FILE *h = fopen(out_path, "w");
    if (!h) {
        perror(out_path);
        return 1;
    }
    fputs("/* Generated by notes/rubik/tools/gen_tables.c. Do not edit. */\n",
          h);
    fputs("#pragma once\n#include <stdint.h>\n", h);
    fprintf(h, "#define RUBIK_NA %u\n#define RUBIK_NORI %u\n", (unsigned) NA,
            (unsigned) NORI);
    fprintf(h, "#define RUBIK_PDB_STRIDE %u\n", (unsigned) STRIDE);
    fprintf(h, "#define RUBIK_PDB_SOLVED %u\n", ig);
    fputs("/* arank[x<<6|y<<3|z] = rank of positions of cubies 0,3,6 */\n", h);
    fputs("static const uint8_t rubik_arank[512] = {\n", h);
    for (int i = 0; i < 512; ++i)
        fprintf(h, "%u,%s", arank[i] == 0xFFFF ? 255u : (unsigned) arank[i],
                i % 16 == 15 ? "\n" : "");
    fputs("};\n/* two 4-bit distances per byte; index = (a<<10) + o */\n", h);
    fprintf(h, "static const uint8_t rubik_pdb[%u] = {\n",
            (unsigned) (NSTORE / 2));
    for (unsigned i = 0; i < NSTORE / 2; ++i)
        fprintf(h, "%u,%s", packed[i], i % 24 == 23 ? "\n" : "");
    fputs("};\n", h);
    fclose(h);
    fprintf(stderr, "wrote %s (%u pdb bytes + 512 arank, stride %u)\n",
            out_path, (unsigned) (NSTORE / 2), (unsigned) STRIDE);

    /* ASM twin: contiguous rubik_arank then rubik_pdb so D = A + 512. */
    const char *asm_path = "src/rubik/tables.S";
    FILE *s = fopen(asm_path, "w");
    if (!s) {
        perror(asm_path);
        return 1;
    }
    fputs("# Generated by notes/rubik/tools/gen_tables.c. Do not edit.\n", s);
    fputs("# Linked with rubik.S (separate TU). C uses tables.h.\n", s);
    fprintf(s, "# PDB index = (a<<10)+o ; stride %u (was a*729+o).\n",
            (unsigned) STRIDE);
    fputs(".data\n", s);
    fputs(".globl rubik_arank, rubik_pdb\n", s);
    fputs("rubik_arank:\n", s);
    for (int i = 0; i < 512; ++i) {
        if (i % 16 == 0)
            fputs("    .byte ", s);
        fprintf(s, "%u%s", arank[i] == 0xFFFF ? 255u : (unsigned) arank[i],
                i % 16 == 15 ? "\n" : ", ");
    }
    fputs("rubik_pdb:\n", s);
    for (unsigned i = 0; i < NSTORE / 2; ++i) {
        if (i % 16 == 0)
            fputs("    .byte ", s);
        fprintf(s, "%u%s", (unsigned) packed[i],
                i % 16 == 15 || i + 1 == NSTORE / 2 ? "\n" : ", ");
    }
    fclose(s);
    fprintf(stderr, "wrote %s (rubik_arank@0 + rubik_pdb@512, %u pdb bytes)\n",
            asm_path, (unsigned) (NSTORE / 2));
    return 0;
}
