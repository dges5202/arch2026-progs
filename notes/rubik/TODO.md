# rubik — HW1 skeleton in `src/rubik/` (you edit C/ASM)

## What’s in `src/rubik/` now

| File | Source |
|------|--------|
| `tables.h` | **New** pos3ori PDB (`rubik_arank` + `rubik_pdb` nibble) ≈ 77 KiB |
| `tables_hw1.h` | HW1 perm/ori/c3 (C still includes this until search rewrite) |
| `tables.S` | HW1 tables for ASM skeleton |
| `rubik.c` | HW1 `ida.c` → `rubik_solve`; include still `tables_hw1.h` |
| `rubik.S` | Stub + `hw1_main` |

Regenerate pos3ori: `gcc -O2 -o /tmp/rubik_gen_tables notes/rubik/tools/gen_tables.c && /tmp/rubik_gen_tables`

C host + guest micro-tests: **all `rubik_c_*` pass**. ASM still returns `-1` until you wire `hw1_main`.

Budgets (HW1 tables): C ≈ 82 KiB, ASM ≈ 106 KiB — under 128 KiB.

## Your next edits

1. **C**: change tables/heuristic when you move off HW1 PDBs (optional later).
2. **ASM**: `rubik_solve_asm` — use `a0/a1/a2`, call into `hw1_main` logic, replace ecalls with write-to-`out` + `ret`.

Original HW1 tree also at `notes/rubik/hw1-import/` and `homework/2026-hw1-minirubik/minirubik/`.

## Experiment notes

- Waterfall 4-view order (24 perms, full-space GCC timing): [`exp-waterfall-order.md`](exp-waterfall-order.md)
- ASM `.data` cross-array layout draft: [`asm-data-layout.md`](asm-data-layout.md)
