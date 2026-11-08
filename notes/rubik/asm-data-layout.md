# ASM `.data` layout — cross-array reads (HW2 draft)

Same idea as HW1: **few walking pointers + fixed offsets** to neighbouring arrays.
Order in `.data` is part of the ABI of the search loop; moving a label breaks offsets.

HW1 used `Q=&pi[g]`, `P=&path[g]`; `oi`/`ci`/`next`/`pface` were `Q+const` / `P+const`.
HW2 search state is a **cubie `state_t`** (not factored indices), so the depth stack changes; the pointer trick stays.

---

## What lives in memory

| block | size (proposed) | access |
|-------|-----------------|--------|
| depth states | 12 × **16** = 192 B | walk `Q`; stride 16 |
| path / next / pface | ~35 B | walk `P` (same as HW1) |
| face_of · turns_of · … | small | base `F`; +9 / +18 |
| apply: source / twist | 3×8 each | `f<<3` |
| sym3: sig / kk | 7+7 (+pad) | fixed from a tiny base |
| scratch (inv / σ) | **16 B** | one buffer, reused |
| `rubik_arank` | 512 B | base `A` |
| `rubik_pdb` | 76545 B (+pad?) | `A+512` or own base |

Tables alone ≈ 77 KiB; with stacks/constants still well under 128 KiB.

---

## Depth stack: AoS + stride 16

C `state_t` is 14 bytes (`p[7]|o[7]`). Pad to **16** so push/pop is `Q ± 16` (one `addi`), not `±14`.

```text
states:          # states[g]: bytes 0..6 = p[], 7..13 = o[], 14..15 = pad
  .zero 192      # 12 * 16
```

Live pointer during search:

| reg (suggested) | meaning | push | pop |
|-----------------|---------|------|-----|
| `Q` | `&states[g]` | `Q += 16` | `Q -= 16` |
| `P` | `&path[g]` | `P += 1` | `P -= 1` |
| `g`, `r` | depth / remaining | `g++`, `r--` | reverse |

Cross-array from `Q` (no second base for o):

| symbol | address |
|--------|---------|
| `states[g].p[i]` | `Q + i` |
| `states[g].o[i]` | `Q + 7 + i` |
| `states[g+1]` (child slot before accept) | `Q + 16` |

### Child write + sibling apply (locked — same as HW1)

Verified in `notes/rubik/hw1-import/rubik.S` / HW1 `rubik.S`:

1. **Direct write to next depth slot** (not a separate “accept-only” copy):
   - `sh cp, 2(s3)` / `sh co, 26(s3)` → `pi/oi[g+1]` at `Q+2` / `Q+26`
   - Comment there: stores run for **every** child, pruned or not, because the next sibling may read them.
   - Push is only `Q += 2` (HW1 halfword stride) once prune passes.

2. **Sibling incremental turn** via `from_off`:
   - `from_off: .byte 0, 2, 2, 0, 2, 2, 0, 2, 2`
   - `F = Q + from_off[m]`: first move of a face reads **parent** (`+0`); `R2`/`R'` read **previous sibling** at `g+1` (`+2`).
   - Same-face skip (`pface`) still jumps whole faces.

**HW2 adopts the same policy** with stride 16:

| | HW1 | HW2 |
|--|-----|-----|
| child slot | `Q+2` (pi halfword) | **`Q+16`** (`states[g+1]`) |
| push | `Q += 2` | **`Q += 16`** |
| `from_off` | `0,2,2, 0,2,2, 0,2,2` | **`0,16,16, 0,16,16, 0,16,16`** |
| apply source | `*(Q + from_off[m])` | same: parent or sibling state |
| apply dest | always next slot | always **`states[g+1]` at `Q+16`** |

Important: even if heuristic prunes, leave the written `states[g+1]` in place so the next sibling can `apply` one more quarter turn from it. First move of the next face uses `from_off=0` and reads the parent again.

`scratch` is **only** for heuristic views (`inv` / `σ`), not for the search child:

```text
scratch: .zero 16   # invert / σ; σ² overwrites in place
```

C (`rubik.c`) can keep “always apply from parent”; ASM may diverge with sibling chaining — same reachable children, fewer full applies.

---

## Path cluster (reuse HW1 offsets)

Keep the proven adjacency:

```text
path:   .zero 11
next:   .zero 12          # next[g]  = P + 11
pface:  .byte 3           # pface[g] = P + 23  (root sentinel 3)
        .zero 11
face_of:  .byte 0,0,0, 1,1,1, 2,2,2
turns_of: .byte 1,2,3, 1,2,3, 1,2,3   # +9
from_off: .byte 0,16,16, 0,16,16, 0,16,16   # +18; byte offsets from Q
```

`P = &path[g]` walks ±1 with `g`. Same-face skip uses `pface` like HW1.

---

## Move / sym constants (one small base)

```text
face_of:   .byte 0,0,0, 1,1,1, 2,2,2
turns_of:  .byte 1,2,3, 1,2,3, 1,2,3     # &face_of + 9
# from_off: optional
source:    # 3 rows × 8 (pad), row f at f<<3
twist:     # same
sig:       .byte 2,5,6,1,4,3,0
kk:        .byte 0,1,0,1,0,1,0            # e.g. &sig + 8 if padded
```

One register `F = &face_of[0]` (or keep `face_of[m]` via `F+m`); `turns_of[m] = F+9+m`.

---

## PDB bases (minimize table pointers)

Preferred packing:

```text
rubik_arank:   .byte ...     # 512
rubik_pdb:     .byte ...     # 76545
               .zero PAD     # optional: align whatever follows / even size
```

| access | how |
|--------|-----|
| `arank[x]` | `A + x` |
| `pdb[i]` | `A + 512 + i` **or** second base `D = A+512` if you want one fewer add in the hot nibble load |

Hot `h_pos3ori`: build index `a*729+o`, then nibble extract from `pdb[idx>>1]`. Worth one dedicated `D` if the add shows up every prune.

No HW1-style face×stride move tables — moves are cubie `apply`, not `perm_move[f][pi]`.

---

## Suggested `.data` order (top → bottom)

1. **`states`** (192) — halfword-safe pad; put early so anything `.half` after stays aligned if needed  
2. **`scratch`** (16)  
3. **`path` / `next` / `pface`** — P-cluster  
4. **`face_of` / `turns_of` / source / twist / sig / kk`** — F-cluster  
5. **`rubik_arank` then `rubik_pdb`** — A / D  

Parse buffer / `move_names` / messages can sit after constants or before tables; not on the Q/P hot path.

---

## Register map (HW2) — ASCII

Constraint: **s0 / s1 / s2 unchanged**; **r moves s10 → s3**; table bases collapse (no perm/ori/c3 farm).

Push / pop (four values still move together):

```text
  push:  g++,  P += 1,  Q += 16,  r--
  pop:   g--,  P -= 1,  Q -= 16,  r++
```

### Live across search (s-regs + dedicated a)

```text
  reg   HW1 (old)              HW2 (this)              notes
  ----  ---------------------  ----------------------  --------------------------
  s0    bound                  bound                   unchanged
  s1    MOVES (9)              MOVES (9)               unchanged
  s2    g                      g                       unchanged
  s3    Q = &pi[g]             r = bound-g-1           << was s10; freed for Q
  s4    P = &path[g]           Q = &states[g]          stride 16; was s3's job
  s5    face_of[]              P = &path[g]            was s4; next=P+11, …
  s6    perm_move_r            F = &face_of[0]         +9 turns, +18 from_off
  s7    ori_move_r             A = &rubik_arank        512 B
  s8    perm_dist              D = &rubik_pdb          = A+512 at init (hot)
  s9    ori_dist               S = &scratch            inv / σ only (16 B)
  s10   r                      (free)                  candidate: out/cap later
  s11   c3_move_r              (free)                  candidate: move_names / …
  a4    c3_dist                (free in search)        was table base; reclaim

  Table pointers in search:  HW1 used s6,s7,s8,s9,s11,a4 (6)
                             HW2 uses s7,s8 only (2)  + F/S for consts/scratch
```

Cross-array from walking pointers (no extra bases):

```text
  from Q (s4):
    states[g].p[i]     = Q + i
    states[g].o[i]     = Q + 7 + i
    states[g+1]        = Q + 16          # child slot / sibling source
    apply from         = Q + from_off[m] # 0 or 16

  from P (s5):
    path[g]            = P + 0
    next[g]            = P + 11
    pface[g]           = P + 23          # write pface[g+1] at P+24 on push

  from F (s6):
    face_of[m]         = F + m
    turns_of[m]        = F + 9 + m
    from_off[m]        = F + 18 + m      # byte 0 or 16
    source row f       = &source + (f<<3)   # place source after F-cluster
    twist row f        = &twist  + (f<<3)   # fixed label or F+const
    sig / kk           = fixed labels near F
```

### Per-child / scratch temps (not preserved across prune→search_top)

Exact t/a split can flex while coding; intended roles:

```text
  reg   role (search child)
  ----  --------------------------------------------------
  a0    face<<3  /  temp index arithmetic / ecall later
  a1    m  (current move)
  a2    turns left  /  loop counter in apply or sym3
  a3    face  or  from-base alias
  a5    face_of[m]  (like HW1 a5)
  a6    Fsrc = Q + from_off[m]   # apply source state*
  a7    (avoid in pure search if possible; ecall / ABI)

  t0..t6  apply byte moves, pdb index (a*729+o), nibble extract,
          h / run_max, compare to r (s3)
```

\* After apply, child bytes live at `Q+16`; heuristic reads that slot (view `s`) or copies through `S` for `inv`/`σ`.

### Init (once per solve, before IDA* loop)

```text
  la   s4, states          # Q
  la   s5, path            # P
  la   s6, face_of         # F
  la   s7, rubik_arank     # A
  addi s8, s7, 512         # D = A + 512  (or la s8, rubik_pdb)
  la   s9, scratch         # S
  li   s1, 9               # MOVES
  # s0 = bound, s2 = 0, s3 = bound-1  at first search entry
```

### Free vs HW1 (visual)

```text
  HW1 s-regs busy with tables:  s6 s7 s8 s9 s11 + a4
  HW2 s-regs busy with tables:  s7 s8
                                ~~~~
  Freed: s10, s11, a4  (+ s6 demoted from huge move table to tiny F)
  Compacted: r at s3  →  Q/P sit in s4/s5  (still two walkers)
```

---

## Decisions

1. **Child write:** direct to `Q+16` (HW1-style); push = `Q += 16`.  
2. **Pad 16:** yes.  
3. **`from_off` sibling apply:** yes (`0,16,16` per face).  
4. **Waterfall order:** layout-independent; default `s` then conj-on-scratch then `inv` (Round D).  
5. **Emit `tables.S`:** `rubik_arank` then `rubik_pdb` contiguous for `A+512`.

---

## Relation to C

`rubik.c` can keep `state_t state[MAX_DEPTH+1]` as today (14-byte AoS). ASM padding is an ASM-only layout choice; no need to change C for correctness.
