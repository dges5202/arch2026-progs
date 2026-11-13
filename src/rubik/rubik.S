# rubik_solve_asm — HW2 IDA* (pos3ori PDB + inv/σ), tables in tables.S / .data
# Contract: a0=state, a1=out, a2=cap; result in a0 (-1 / -2 / length).
# Outer: parse / identity / root heuristic / IDA* shell — HW2.
# Hot child: apply (source/twist) → four-view h waterfall vs r → push / found.
#
# -------
#  COMPLETE REGISTER ARCHITECTURE (HW2)
# -------
#
#  Entry (ABI):
#    a0 = state (14 chars)     a1 = out     a2 = cap
#
#  Push / pop (hot loop; four values move together):
#    push:  g++ | P += 1 | Q += 16 | r--
#    pop:   g-- | P -= 1 | Q -= 16 | r++
#
#  Cross-array (fixed offsets; .data order is part of the ABI):
#    Q+i = p[i],  Q+7+i = o[i],  Q+16 = states[g+1]
#    P+0 = path[g],  P+11 = next[g],  P+23 = pface[g]  (write pface[g+1] @ P+24)
#    F+m = face_of[m],  F+9+m = turns_of[m],  F+18+m = from_off[m]  (0 or 16)
#    D = A + 512 = &rubik_pdb     S = &scratch (inv/σ only)
#
#  +-----+----------------------+--------------------------------------------+
#  | reg | PARSE / setup        | HOT LOOP (search)                          |
#  +-----+----------------------+--------------------------------------------+
#  | s0  | walk *in  / temps    | bound                                      |
#  | s1  | walk dest p/o        | MOVES (9)                                  |
#  | s2  | (spare / root walk)  | g                                          |
#  | s3  | (spare)              | r = bound - g - 1     << was HW1 s10       |
#  | s4  | (spare until la Q)   | Q = &states[g]                             |
#  | s5  | (spare until la P)   | P = &path[g]                               |
#  | s6  | (spare until la F)   | F = &face_of[0]                            |
#  | s7  | (spare until la A)   | A = &rubik_arank                           |
#  | s8  | (spare until la D)   | D = &rubik_pdb                             |
#  | s9  | (spare until la S)   | S = &scratch                               |
#  | s10 | SAVE out (from a1)   | out (kept for format)                      |
#  | s11 | SAVE cap (from a2)   | cap (kept for format)                      |
#  +-----+----------------------+--------------------------------------------+
#  | a0  | in ptr (then clobbered) | temp / dest / index math               |
#  | a1  | out — SAVE to s10 ASAP  | m                                       |
#  | a2  | cap — SAVE to s11 ASAP  | σ/σ² arank pack temp (cleared each view) |
#  | a3  | parse temps             | &sig (kk at a3+7); pin whole search     |
#  | a4  | parse temps             | walk cursor in heuristic_core           |
#  | a5  | parse temps             | face_of[m]                              |
#  | a6  | parse temps             | Fsrc = Q + from_off[m]                  |
#  | a7  | (spare)                 | &mod3tab[0..6]; pin whole search        |
#  | t0-6| parse / rank / h temps  | apply, pdb index, h, prune              |
#  +-----+----------------------+--------------------------------------------+
#  | ra  | ret                         | (unused in explicit DFS)            |
#  | sp  | frame if any                |                                     |
#  | gp  | unused                      |                                     |
#  | tp  | unused                      |                                     |
#  +-----+-----------------------------+-------------------------------------+
#
#  Table bases in hot loop: A (s7) + D (s8) + sig (a3).  HW1 needed six.
#  Child: always write states[g+1] at Q+16; sibling apply via from_off.
#  s1 stays MOVES=9 for the whole search (walk uses a4, not s1).
#
# -------
#  HOT-LOOP REGISTER PRESSURE (evaluation)
# -------
#
#  Pinned whole search (must not spill mid-child), CURRENT map:
#    s0..s9  = bound, MOVES, g, r, Q, P, F, A, D, S     (10)
#    s10,s11 = out, cap                                  (2)  → kept for found
#    a3      = &sig                                      (1)  → do not clobber
#
#  Free for one child (apply → heuristic → prune → maybe push):
#    t0..t6          = 7
#    a0,a4           = 2   (a1=m, a5=face, a6=Fsrc; a4 = h walk)
#    a2              = pack during σ/σ² p_build only
#    --------------------
#    ≈ 9 temps; s1 is NOT a walk pointer; a7 pinned to mod3tab
#
#  Peak live sets (sequential phases — NOT all at once):
#
#    (1) search_top / pick m
#        need: P, F, s1=MOVES, a1=m, a5=face, t*: next/pface
#        temps ≈ 3–4          OK
#
#    (2) apply (sibling): Fsrc → Q+16, one quarter
#        pinned: Q, Fsrc(a6), face/rows, dest
#        loop:   i, from, byte loads, source* / twist*
#        temps ≈ 6–8 + a6,a5  OK (reuse i/from each cubie)
#        NOTE: do NOT keep 14 cubie bytes in regs — memory AoS only
#
#    (3) h_pos3ori(view*)  [s at Q+16, or S after inv/σ]; walk = a4
#    (4) waterfall vs r(s3); inv/σ through S; σ/σ² use a3=&sig
#        σ/σ²: while writing y.p[sig[i]]=sig[p[i]] (z at +14), if value
#        is cubie 0|3|6 then pack |= sig[i]<<6|<<3|<<0 into a2 — no 7-scan
#    (5) push: addi s2,s3,s4,s5 + sb path/pface
#
#  out/cap stay in s10/s11 (no spill). Pin &sig in a3; a7=&mod3tab; a2=pack.
#  Hot %3 (apply / inv / σ·σ² ori): lbu from mod3tab — no blt/sub loop.
#  .data below is HW2; rubik_arank|rubik_pdb from tables.S (link).
#
# -------
#  OPT LOG (hackmd §1.5) — where each row lives in this file
# -------
#  v1    IDA* + waterfall s→inv→σ→σ²; C-style apply; parse sll
#        → steps 1–5; heuristic_core waterfall; child apply (later v4b)
#  v2/v2b order matter: KEEP s→inv→σ→σ² (v2 σ-first regressed; v2b restore)
#        → root heuristic_start + hot heuristic_core same order
#  v3    PDB stride 1024; idx=(a<<10)+o
#        → every PDB_NIBBLE / root nibble: slli t0,t6,10
#  v4a   turns==1 fast path (superseded)
#  v4b   sibling 1q via from_off (always one quarter)
#        → no_prev / apply_1q / apply_sw_loop
#  v5a   pin a3=&sig, walk a4; s1=MOVES whole search (no per-PDB li s1,9)
#        → ida_start la a3; heuristic_core uses a4; PDB_NIBBLE keeps s1
#  v5b   σ/σ² pack-while-scatter (drop 7-scan index)
#        → loop_heuristic_core_sym*_p_build packs a2; mv t6,a2 → arank
#  v5c1  hot %3 → mod3tab, a7 pin
#        → ida_start la a7; apply_1q / inv_o / sym_o use lbu (a7)
#  v5c2  r==0 cold: beqz → r0_id_path; r≠0 falls into waterfall
#        → heuristic_core: beqz s3, r0_id_path
#  v5c3  nibble slli; andi 4 (≡ andi 1; slli 2)
#        → PDB_NIBBLE + root nibble sites
#  v5c4  apply_1q LU: dest / &twist fills between loads and uses
#        → apply_1q body
#  v5c5  pos-build LU: addi a4 between lbu p and add
#        → loop_heuristic_core_p
#  v5c6  sibling scratch→Q+16: 4×lw/4×sw (was 14×lbu/sb loop)
#        → apply_sw_loop; d11 mean −10% / 5ST cycles ~−10%
#

    .data
    # Order: states → scratch → P → F → source/twist/sig/kk/mod3tab → move_names

    states: .zero 192                              # 12*16; Q=&states[g]; p@0..6 o@7..13
    scratch:.zero 32                               # inv; σ: y@0..13; σ²: z@14..27

    # P-cluster: next=P+11, pface=P+23
    path:   .zero 11
    next:   .zero 12
    pface:  .byte 3
    .zero   11

    # F-cluster: turns_of=F+9, from_off=F+18 (Q byte offsets 0|16)
    face_of:.byte 0, 0, 0, 1, 1, 1, 2, 2, 2
    turns_of:.byte 1, 2, 3, 1, 2, 3, 1, 2, 3
    from_off:.byte 0, 16, 16, 0, 16, 16, 0, 16, 16

source:
    .byte   1, 4, 2, 0, 3, 5, 6, 9
    .byte   0, 1, 2, 4, 5, 6, 3, 9
    .byte   0, 2, 5, 3, 1, 4, 6, 9
twist:
    .byte   1, 2, 0, 2, 1, 0, 0, 9
    .byte   0, 0, 0, 1, 2, 1, 2, 9
    .byte   0, 0, 0, 0, 0, 0, 0, 9
    sig:    .byte 2, 5, 6, 1, 4, 3, 0
    kk:     .byte 0, 1, 0, 1, 0, 1, 0
    mod3tab: .byte 0, 1, 2, 0, 1, 2, 0

    # format only (m<<1); 'R'=82 'B'=66 'D'=68 '2'=50 '\''=39
move_names:
    .byte   82, 0
    .byte   82, 50
    .byte   82, 39
    .byte   66, 0
    .byte   66, 50
    .byte   66, 39
    .byte   68, 0
    .byte   68, 50
    .byte   68, 39

    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
rubik_solve_asm:
    addi    sp, sp, -64
    sw      s0,  0(sp)
    sw      s1,  4(sp)
    sw      s2,  8(sp)
    sw      s3, 12(sp)
    sw      s4, 16(sp)
    sw      s5, 20(sp)
    sw      s6, 24(sp)
    sw      s7, 28(sp)
    sw      s8, 32(sp)
    sw      s9, 36(sp)
    sw      s10, 40(sp)
    sw      s11, 44(sp)

    mv      s10, a1
    mv      s11, a2

    # 1. parse (rubik.c parse_state) → states[0]; fail → a0=-1, out untouched
    #    in = PPPPPPPOOOOOOO + NUL; value = ch - '1'
    #    (a) length: in[0..13] != '\0', in[14] == '\0'
    #    (b) i=0..6: p=in[i]-'1' ∈0..6 unique (seen); o=in[7+i]-'1' ∈0..2;
    #        sum += o; store p→states[i], o→states[7+i]
    #    (c) sum % 3 == 0 (subtract 3 until <3, must be 0)
    mv      t4, a0                                 # length cursor (keep a0 at in[0])

    li      t0, 0
    li      t1, 14
loop_parse:
    lbu     t3, 0(t4)
    beqz    t3, loop_parse_failed                  # too short

    addi    t0, t0, 1
    addi    t4, t4, 1
    bne     t0, t1, loop_parse

    lbu     t3, 0(t4)
    bnez    t3, loop_parse_failed                  # in[14] must be NUL

    la      s1, states
    li      t0, 7                                  # 7 cubies
    li      t1, 7                                  # p reject if >= 7
    li      a4, 3                                  # o reject if >= 3; mod3 step
    li      a5, 0                                  # seen bitmask
    li      a6, 0                                  # ori sum

loop_build:
    lbu     t2, 0(a0)                              # in[i]
    lbu     t3, 7(a0)                              # in[7+i]
    addi    t4, t2, -49                            # t4 = p = in[i] - '1'
    addi    t5, t3, -49                            # t5 = o = in[7+i] - '1'
    bgeu    t4, t1, loop_parse_failed              # p not in 0..6
    li      t6, 1
    sll     t6, t6, t4                             # 1 << p
    and     a3, a5, t6
    bnez    a3, loop_parse_failed                  # duplicate cubie
    or      a5, a5, t6                             # seen |= 1<<p

    bgeu    t5, a4, loop_parse_failed              # o not in 0..2
    add     a6, a6, t5                             # sum += o

    sb      t4,  0(s1)                             # states.p[i]
    sb      t5,  7(s1)                             # states.o[i]

    addi    t0, t0, -1
    addi    a0, a0, 1
    addi    s1, s1, 1
    bnez    t0, loop_build

parse_mod3:
    bltu    a6, a4, parse_mod3_skip                # while sum >= 3: sum -= 3
    sub     a6, a6, a4
    j       parse_mod3

parse_mod3_skip:
    bnez    a6, loop_parse_failed                  # need sum ≡ 0 (mod 3)


    # 2. already solved? identity on states[0] (NOT h==0 — pos3ori can
    #    be 0 on unsolved). Else → heuristic_start.
    #    p[i]==i (i=0..6), o[i]==0 (i=0..6)
    #    yes → out="" (cap>=1), return 0;  cap==0 → return -2
    la      s1, states                             # s1 = &states[0].p[0]

    li      t0, 0
    li      t1, 7
decision_loop: 
    lbu     t2, 0(s1)                              # t2 = p[i]
    bne     t0, t2, heuristic_start
    lbu     t2, 7(s1)                              # t2 = o[i]
    bnez    t2, heuristic_start

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, decision_loop

    beqz    s11, exit_program                      # cap == 0 → -2
    sb      x0, 0(s10)                             # out[0] = '\0'
    li      a0, 0
    j       epilogue

loop_parse_failed:
    li      a0, -1                                 # invalid state
    j       epilogue

exit_program:
    li      a0, -2                                 # cap too small for empty solution
    j       epilogue

heuristic_start:
    # 3. Root heuristic → s0 = bound seed (no prune vs r; full max of 4 views)
    #    Matches rubik.c heuristic() / IDA* initial bound (v1 / v2b order):
    #      h = max( h_pos3ori(s), h(inv), h(σ(s)), h(σ²(s)) )
    #    (a) pdb_index: a=arank[pos0<<6|pos3<<3|pos6]; o=fold o[0..5]
    #    (b) v3: idx=(a<<10)+o; nibble from rubik_pdb (stride 1024)
    #    (c) scratch: after h(s), [0..6]=pos=inv.p; σ y@0..13; σ² z@14..27
    #    (d) s7=A, s8=D, s9=S live through all four views
    #    Note: root σ still uses subtract-%3 + 7-scan index; hot path is v5b/c1.

    # 3a. h_pos3ori(s) — index states[0] directly, seed s0 = h
    #     C: pos[p[i]]=i; a=arank[...]; o=fold s.o[0..5]; nibble((a<<10)+o)
    la      s1, states                             # cursor at s.p[0]
    la      s7, rubik_arank                        # s7 = A = &rubik_arank[0]
    la      s8, rubik_pdb                          # s8 = D = &rubik_pdb[0]
    la      s9, scratch                            # s9 = S = &scratch[0]

    # build pos[]: scratch[p[i]] = i
    li      t0, 0
    li      t1, 7
loop_heuristic_p:
    lbu     t2, 0(s1)                              # p[i]
    add     t3, t2, s9
    sb      t0, 0(t3)                              # scratch[p[i]] = i
    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_p

    # a = arank[pos0<<6 | pos3<<3 | pos6]; s1 now at &s.o[0]
    lbu     t0, 0(s9)                              # pos0 = scratch[0]
    lbu     t1, 3(s9)                              # pos3 = scratch[3]
    lbu     t2, 6(s9)                              # pos6 = scratch[6]
    slli    t3, t0, 6                              # pos0 << 6
    slli    t4, t1, 3                              # pos3 << 3
    or      t5, t3, t4
    or      t5, t5, t2                             # pack
    add     t6, t5, s7
    lbu     t6, 0(t6)                              # a = arank[...]

    # fold s.o[0..5] → t4
    li      t0, 0
    li      t1, 6
    li      t4, 0                                  # o = 0
loop_heuristic_o:
    lbu     t2, 0(s1)                              # o[i]
    slli    t3, t4, 1                              # o*2
    add     t4, t4, t3                             # o*3
    add     t4, t4, t2                             # o*3 + o[i]
    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_o

    # v3+v5c3 nibble: idx=(a<<10)+o; (idx&1)<<2 via slli;andi 4
    slli    t0, t6, 10
    add     t0, t0, t4                             # idx = a*1024 + o

    srli    t1, t0, 1
    add     t2, t1, s8                             # &pdb[idx>>1]
    lbu     t3, 0(t2)
    slli    t4, t0, 2                              # (idx&1)<<2
    andi    t4, t4, 4
    srl     t3, t3, t4
    andi    s0, t3, 15                             # s0 = h(s)

    # 3b. h_pos3ori(inv(s)) — max into s0 (v2b: inv before σ; reuse pos)
    #     C invert: r.p[c]=i, r.o[c]=mod3(3-s.o[i]), c=s.p[i]
    #     (a) arank from s.p[0|3|6]
    #     (b) scratch[j] from h(s) = inv.p[j]
    #     (c) fold inv.o[j]=mod3(3-s.o[scratch[j]]), j=0..5
    la      s1, states
    addi    s1, s1, 7                              # &s.o[0] (inv_p rebuild removed)

    # a = arank[s.p[0]<<6 | s.p[3]<<3 | s.p[6]]
    la      t0, states
    lbu     t1, 0(t0)                              # s.p[0] = pos of cubie 0 in inv
    lbu     t2, 3(t0)                              # s.p[3]
    lbu     t3, 6(t0)                              # s.p[6]
    slli    t4, t1, 6
    slli    t5, t2, 3
    or      t4, t4, t5
    or      t4, t4, t3
    add     t6, t4, s7
    lbu     t6, 0(t6)                              # a = arank[...]

    # fold inv.o[0..5]: o=(3-s.o[i])%3, i=scratch[j]
    li      t0, 0
    li      t1, 6
    li      t4, 0                                  # o fold = 0
    li      t5, 3                                  # for (3-x)%3
loop_heuristic_inv_o:
    add     t2, s9, t0
    lbu     t2, 0(t2)                              # i = scratch[j] = inv.p[j]
    add     t2, s1, t2
    lbu     t2, 0(t2)                              # s.o[i]
    sub     t3, t5, t2                             # 3 - s.o[i]
    bne     t3, t5, loop_heuristic_inv_o_skip
    sub     t3, t5, t3                             # if 3: → 0  ((3-0)%3)
loop_heuristic_inv_o_skip:
    slli    t2, t4, 1
    add     t4, t4, t2                             # o*3
    add     t4, t4, t3                             # + inv.o[j]
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_inv_o

    # v3+v5c3 nibble → max into s0
    slli    t0, t6, 10
    add     t0, t0, t4                             # idx = a*1024 + o

    srli    t1, t0, 1
    add     t2, t1, s8                             # &pdb[idx>>1]
    lbu     t3, 0(t2)
    slli    t4, t0, 2                              # (idx&1)<<2
    andi    t4, t4, 4
    srl     t3, t3, t4
    andi    t0, t3, 15
    blt     t0, s0, heuristic_skip1

    mv      s0, t0

heuristic_skip1:

    # 3c. h_pos3ori(σ(s)) — y=sym3(s), pdb_index(y), max into s0
    #     C: y.p[sig[i]]=sig[p[i]]; y.o[sig[i]]=(o+3+kk[i]-kk[p[i]])%3
    #     (a) s1=&states; t5=&sig (kk at t5+7); s7/s8/s9 live
    #     (b) root: subtract-%3 + 7-scan index (hot path = v5b/v5c1)
    #     (c) index pack clobbers t5 → σ² must la t5,sig again
    la      s1, states                             # cursor at s.p[0]
    la      t5, sig                                # &sig[0]; kk at t5+7

    # build y.p[sig[i]] = sig[p[i]]
    li      t0, 0
    li      t1, 7

loop_heuristic_sym_p_build:
    lbu     t2, 0(s1)                              # p[i]
    add     t3, t2, t5
    lbu     t3, 0(t3)                              # sig[p[i]]

    add     t2, t0, t5
    lbu     t2, 0(t2)                              # sig[i]

    add     t2, t2, s9
    sb      t3, 0(t2)                              # y.p[sig[i]]
    

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_sym_p_build

    # build y.o[sig[i]] = (o[i]+3+kk[i]-kk[p[i]]) % 3; s1 at &s.o[0]
    li      t0, 0
    li      t1, 7
    li      t6, 3                                  # %3 threshold
loop_heuristic_sym_o_build:
    lbu     t2, 0(s1)                              # o[i]
    addi    t3, t2, 3
    add     t2, t5, t0
    lbu     t2, 7(t2)                              # kk[i]
    add     t4, t2, t3                             # o[i]+3+kk[i]
    lbu     t2, -7(s1)                             # p[i]
    add     t3, t2, t5
    lbu     t3, 7(t3)                              # kk[p[i]]
    sub     t4, t4, t3                             # o[i]+3+kk[i]-kk[p[i]]

    blt     t4, t6, loop_heuristic_sym_o_skip
    sub     t4, t4, t6
    blt     t4, t6, loop_heuristic_sym_o_skip
    sub     t4, t4, t6                             # %3 (t4 was in 2..6)

loop_heuristic_sym_o_skip:
    add     t2, t0, t5
    lbu     t3, 0(t2)                              # sig[i]
    add     t2, t3, s9
    sb      t4, 7(t2)                              # y.o[sig[i]]

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_sym_o_build

    # pdb_index(y): pack pos of cubies 0,3,6 from y.p into t6, then arank
    li      t0, 0
    li      t1, 7
    li      t3, 3                                  # cubie 3
    li      t4, 6                                  # cubie 6
    li      t6, 0
loop_heuristic_sym_p_index:
    add     t2, t0, s9
    lbu     t2, 0(t2)                              # y.p[i]
    bne     t2, x0, loop_heuristic_sym_p_index_skip1
    slli    t5, t0, 6                              # clobbers &sig
    or      t6, t5, t6                             # | pos0<<6
loop_heuristic_sym_p_index_skip1:
    bne     t2, t3, loop_heuristic_sym_p_index_skip2
    slli    t5, t0, 3
    or      t6, t5, t6                             # | pos3<<3
loop_heuristic_sym_p_index_skip2:
    bne     t2, t4, loop_heuristic_sym_p_index_skip3
    or      t6, t0, t6                             # | pos6
loop_heuristic_sym_p_index_skip3:
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_sym_p_index

    add     t6, t6, s7
    lbu     t6, 0(t6)                              # a = arank[...]

    # fold y.o[0..5] → t4; keep a in t6
    li      t0, 0
    li      t1, 6
    li      t4, 0
loop_heuristic_sym_o_index:
    add     t2, s9, t0
    lbu     t2, 7(t2)                              # y.o[j]
    slli    t3, t4, 1
    add     t4, t4, t3
    add     t4, t4, t2
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_sym_o_index

    # idx = a*1024 + o; pdb nibble → s0 (first h, no max yet)
    slli    t0, t6, 10
    add     t0, t0, t4                             # idx = a*1024 + o

    srli    t1, t0, 1
    add     t2, t1, s8                             # &pdb[idx>>1]
    lbu     t3, 0(t2)
    slli    t4, t0, 2                              # (idx&1)<<2 via slli; andi 4
    andi    t4, t4, 4
    srl     t3, t3, t4
    andi    t0, t3, 15
    blt     t0, s0, heuristic_skip2

    mv      s0, t0

heuristic_skip2:

    # 3d. h_pos3ori(σ²(s)) — z=sym3(y), pdb_index(z), max into s0
    #     Same loops as σ; bases differ (cannot overwrite y in-place):
    #       (a) in  = y @ S+0   (p[0..6], o[7..13])
    #       (b) out = z @ S+14  (p[14..20], o[21..27])
    #       (c) must la t5,sig again (σ index clobbered t5)
    mv      s1, s9                                 # cursor at y.p[0]
    la      t5, sig                                # &sig[0]; kk at t5+7

    # build z.p[sig[i]] = sig[y.p[i]]
    li      t0, 0
    li      t1, 7
loop_heuristic_sym2_p_build:
    lbu     t2, 0(s1)                              # y.p[i]
    add     t3, t2, t5
    lbu     t3, 0(t3)                              # sig[y.p[i]]

    add     t2, t0, t5
    lbu     t2, 0(t2)                              # sig[i]

    add     t2, t2, s9
    sb      t3, 14(t2)                             # z.p[sig[i]]

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_sym2_p_build

    # build z.o[sig[i]] = (y.o[i]+3+kk[i]-kk[y.p[i]]) % 3; s1 at &y.o[0]
    li      t0, 0
    li      t1, 7
    li      t6, 3                                  # %3 threshold
loop_heuristic_sym2_o_build:
    lbu     t2, 0(s1)                              # y.o[i]
    addi    t3, t2, 3
    add     t2, t5, t0
    lbu     t2, 7(t2)                              # kk[i]
    add     t4, t2, t3                             # y.o[i]+3+kk[i]
    lbu     t2, -7(s1)                             # y.p[i]
    add     t3, t2, t5
    lbu     t3, 7(t3)                              # kk[y.p[i]]
    sub     t4, t4, t3                             # y.o[i]+3+kk[i]-kk[y.p[i]]

    blt     t4, t6, loop_heuristic_sym2_o_skip
    sub     t4, t4, t6
    blt     t4, t6, loop_heuristic_sym2_o_skip
    sub     t4, t4, t6                             # %3 (t4 was in 2..6)

loop_heuristic_sym2_o_skip:
    add     t2, t0, t5
    lbu     t3, 0(t2)                              # sig[i]
    add     t2, t3, s9
    sb      t4, 21(t2)                             # z.o[sig[i]]

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_sym2_o_build

    # pdb_index(z): pack pos of cubies 0,3,6 from z.p into t6, then arank
    li      t0, 0
    li      t1, 7
    li      t3, 3                                  # cubie 3
    li      t4, 6                                  # cubie 6
    li      t6, 0
loop_heuristic_sym2_p_index:
    add     t2, t0, s9
    lbu     t2, 14(t2)                             # z.p[i]
    bne     t2, x0, loop_heuristic_sym2_p_index_skip1
    slli    t5, t0, 6                              # clobbers &sig
    or      t6, t5, t6                             # | pos0<<6
loop_heuristic_sym2_p_index_skip1:
    bne     t2, t3, loop_heuristic_sym2_p_index_skip2
    slli    t5, t0, 3
    or      t6, t5, t6                             # | pos3<<3
loop_heuristic_sym2_p_index_skip2:
    bne     t2, t4, loop_heuristic_sym2_p_index_skip3
    or      t6, t0, t6                             # | pos6
loop_heuristic_sym2_p_index_skip3:
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_sym2_p_index

    add     t6, t6, s7
    lbu     t6, 0(t6)                              # a = arank[...]

    # fold z.o[0..5] → t4; keep a in t6
    li      t0, 0
    li      t1, 6
    li      t4, 0
loop_heuristic_sym2_o_index:
    add     t2, s9, t0
    lbu     t2, 21(t2)                             # z.o[j]
    slli    t3, t4, 1
    add     t4, t4, t3
    add     t4, t4, t2
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_sym2_o_index

    # idx = a*1024 + o; pdb nibble → s0 (first h, no max yet)
    slli    t0, t6, 10
    add     t0, t0, t4                             # idx = a*1024 + o

    srli    t1, t0, 1
    add     t2, t1, s8                             # &pdb[idx>>1]
    lbu     t3, 0(t2)
    slli    t4, t0, 2                              # (idx&1)<<2 via slli; andi 4
    andi    t4, t4, 4
    srl     t3, t3, t4
    andi    t0, t3, 15
    blt     t0, s0, heuristic_skip3

    mv      s0, t0

heuristic_skip3:

    # -------
    #  REG MAP at ida_start (after parse / identity / root heuristic)
    # -------
    #
    #  Live now:
    #    s0  = bound = heuristic(states[0])   (four-view max, verified vs C)
    #    s7/s8/s9 may still hold A/D/S from heuristic (re-la below OK)
    #    s10 = out,  s11 = cap
    #    states[0] = root cubie state
    #
    #  HOT LOOP map (apply + h prune + push):
    #
    #  Push/pop:  g++|P+1|Q+16|r--   /   g--|P-1|Q-16|r++
    #  Layout: Q+i=p[i], Q+7+i=o[i], Q+16=states[g+1]
    #          P+0=path[g], P+11=next[g], P+23=pface[g]
    #          F+m=face_of, F+9+m=turns_of, F+18+m=from_off (0|16)
    #          D = A+512 = &rubik_pdb ;  S = &scratch
    #
    #  +-----+------------------+------------------------------------------+
    #  | reg | now              | hot loop                                 |
    #  +-----+------------------+------------------------------------------+
    #  | s0  | bound            | bound                                    |
    #  | s1  | (free)           | MOVES = 9                                |
    #  | s2  | (free)           | g                                        |
    #  | s3  | (free)           | r = bound - g - 1                        |
    #  | s4  | (free)           | Q = &states[g]                           |
    #  | s5  | (free)           | P = &path[g]                             |
    #  | s6  | (free)           | F = &face_of[0]                          |
    #  | s7  | A (or free)      | A = &rubik_arank                         |
    #  | s8  | D (or free)      | D = &rubik_pdb                           |
    #  | s9  | S (or free)      | S = &scratch                             |
    #  | s10 | out              | out (format; kept)                       |
    #  | s11 | cap              | cap (format; kept)                       |
    #  +-----+------------------+------------------------------------------+
    #  | a0  | clobbered        | temp / dest / index math                 |
    #  | a1  | clobbered        | m                                        |
    #  | a2  | (free)           | σ/σ² pack = pos0<<6|pos3<<3|pos6 (v5b)   |
    #  | a3  | (free)           | &sig pin (v5a); kk at a3+7               |
    #  | a4  | (free)           | heuristic walk cursor (v5a)              |
    #  | a5  | (free)           | face_of[m]                               |
    #  | a6  | (free)           | Fsrc = Q + from_off[m]                   |
    #  | a7  | (free)           | &mod3tab pin (v5c1)                      |
    #  | t0-6| temps            | apply / h_pos3ori / prune                |
    #  +-----+------------------+------------------------------------------+

    #  HOT LOOP CFG (one bound; fall-through = common)
    #
    #                    ┌── bound_failed → ++bound → loop_solve
    #                    │
    #   same_face ──┐    │
    #               ▼    │
    #             pop ───┴── g>0: g++/r++/Q/P rewind ──┐
    #                                                   │ fall
    #                                                   ▼
    #                                             search_top
    #                                          load m=next[g], pf
    #                                           m==MOVES? ──yes──► pop
    #                                               │ no
    #                                               ▼
    #                                             child
    #                                      next[g]=m+1; face?
    #                               same face? ──yes──► same_face
    #                                       │ no
    #                                       ▼
    #                                    apply_1q
    #                                       │
    #                                       ▼
    #                                 heuristic_core
    #                            r==0? ──yes──► r0_id_path
    #                              │ no              │
    #                              ▼                 ├─ id → found
    #                         waterfall              └─ else → search_top
    #                         h>r? → search_top
    #                              │ all h≤r
    #                              ▼
    #                            PUSH (g++/r--/Q/P)
    #                              │
    #                              ▼
    #                          solve_loop (id?)
    #                         yes → found
    #                         no  → child   ◄── deepen at m=0 (a1=0)
    #
    #  Edges that skip search_top on purpose:
    #    push → child | same_face (m+3≠MOVES) → child

ida_start:
    # 4. IDA* outer: bound = h(root) .. MAX_DEPTH; each bound → DFS (step 5)
    #    v5a: s1=MOVES for whole search; a3=&sig pinned
    #    v5c1: a7=&mod3tab pinned (hot %3 = lbu, no subtract loop)
    li      s1, 9                                  # s1 = MOVES (fixed for search)

    la      s6, face_of                            # s6 = F = &face_of[0]
    la      s7, rubik_arank                        # s7 = A = &rubik_arank[0]
    la      s8, rubik_pdb                          # s8 = D = &rubik_pdb[0]
    la      s9, scratch                            # s9 = S = &scratch[0]
    la      a3, sig                                # a3 = &sig; kk at a3+7 (do not clobber)
    la      a7, mod3tab                            # a7 = &mod3tab[0..6] (do not clobber)


loop_solve:

    li      s2, 0                                  # s2 = g = 0
    addi    s3, s0, -1                             # s3 = r = bound - 1
    la      s4, states                             # s4 = Q = &states[0]
    la      s5, path                               # s5 = P = &path[0]
    sb      x0, 11(s5)                             # next[0] = 0 (next[0] = P + 11)

    # same_face and pop sit right above search_top so both fall into
    # it. Jumping over them costs a taken branch once per bound,
    # instead of one per pop.
    j       search_top                             # skip same_face and pop

    # 5. One bounded depth-first pass with the explicit stack.
    # ida.c: search
    # Every "return" goes back to search_top (a push or a same-face skip
    # goes straight to child), so no return address is needed: pop is
    # g--, push is g++.
    #
    # Laid out for the 5-stage pipeline: the common case, a move left to
    # try, falls through every branch, and no load is used by the very
    # next instruction. The two rarer paths, same_face and pop, come
    # first and fall through into search_top.

    # m is the first turn of the parent's face (moves are tried in
    # order), so skip all three turns of it at once. Kept out of line:
    # the common case, a different face, falls through the beq instead
    # of paying for a taken branch.
    #
    # if (face_of[m] == face_of[path[g - 1]]) { next[g] += 2; continue; }
    #
    # Like a push, this knows what search_top would load: m + 3 and the
    # same pf, still in t5. So it tests m + 3 == MOVES itself and goes
    # straight to child, which stores next[g] = m + 4. When m + 3 ==
    # MOVES it falls into pop; next[g] is not stored then, since a later
    # push to this depth enters child at m = 0 without reading it.
same_face:
    addi    a1, t2, 2                              # a1 = m + 3: first turn of the next face
    bne     a1, s1, child                          # m + 3 != MOVES: try the next face

    # All moves of depth g tried: back to the parent, then fall into
    # search_top. The parent's next[g] and pface[g] are no longer in any
    # register, so search_top must load them.
    #
    # if (g == 0) goto bound_failed;
    # --g;
    # continue;
pop:
    beq     s2, x0, bound_failed                   # all moves tried at the root

    addi    s2, s2, -1                             # s2 = g = g - 1
    addi    s3, s3, 1                              # s3 = r = r + 1
    addi    s4, s4, -16                            # Q = &states[g - 1]
    addi    s5, s5, -1                             # P = &path[g - 1]


    # if (next[g] == MOVES) goto pop;
    #
    # pface[g] is loaded before the beq to fill the slot after lbu a1;
    # a pop loads it for nothing (one instruction).
search_top:
    lbu     a1, 11(s5)                             # a1 = m = next[g] = *(P + 11)
    lbu     t5, 23(s5)                             # t5 = pface[g] = face_of[path[g - 1]]
    beq     a1, s1, pop                            # next[g] == MOVES: all moves tried

    # unsigned m = next[g]++;
    # if (face_of[m] == pface[g])     /* pface[0] = 3: never at the root */
    # goto same_face;
    #
    # The next[g] store sits between lbu a5 and the beq that reads a5.
child:
    add     t3, s6, a1                             # face_of[m]'s memory
    lbu     a5,  0(t3)                             # a5 = face_of[m]
    addi    t2, a1, 1                              # t2 = m + 1
    sb      t2, 11(s5)                             # next[g] = m + 1
    beq     t5, a5, same_face                      # same face as path[g - 1]: skip it

    # 5a. apply (v4b): always ONE quarter; src = Q + from_off[m]
    #     (a) R/B/D:  off=0  → parent Q → dest Q+16
    #     (b) R2/R':  off=16 → sibling Q+16 → scratch → copy to Q+16
    #     (c) ≡ C apply(parent,m) in face order; do NOT also use turns_of
    #     (d) v5c1: ori via mod3tab[a7]; v5c4: LU fills in apply_1q
    #     (e) v5c6: sibling copy = 4×lw/4×sw (16B slot; live bytes 0..13)
no_prev:
    la      t4, source
    slli    t1, a5, 3                              # face * 8
    add     t4, t4, t1                             # t4 = &source[face][0]
    la      t5, twist
    add     t5, t5, t1                             # t5 = &twist[face][0]

    lbu     t0, 18(t3)                             # t0 = from_off[m]
    add     a6, s4, t0
    addi    a0, s4, 16                             # Q + 16

    beqz    t0, apply_1q_skip
    mv      a0, s9                                 # sibling: dest = scratch
apply_1q_skip:
    li      t0, 7

    # v5c4 apply_1q LU schedule:
    #   (a) add dest (t3) fills from→use
    #   (b) add &twist (t2) fills p→sb
    #   (c) lbu twist fills o→add; mod3→sb may still stall 1
apply_1q:
    addi    t0, t0, -1
    add     t1, t4, t0
    lbu     t1, 0(t1)                              # from = source[face][i]

    add     t3, a0, t0                             # &dest.p[i] (fill from)
    add     t6, a6, t1
    lbu     t6, 0(t6)                              # p

    add     t2, t5, t0                             # &twist[face][i] (fill p→sb)
    sb      t6, 0(t3)

    add     t6, a6, t1
    lbu     t6, 7(t6)                              # o
    lbu     t1, 0(t2)                              # twist[face][i] (fill o)
    add     t6, t6, t1                             # o + twist

    add     t6, a7, t6                             # &mod3tab[o + twist]
    lbu     t6, 0(t6)                              # mod3tab[o + twist]

    sb      t6, 7(t3)                              # may load-use stall 1
    bnez    t0, apply_1q


    addi    t1, s4, 16
    beq     a0, t1, heuristic_core


apply_sw_loop:
    # v5c6: sibling copy scratch → Q+16 as words (aligned 16B slots)
    #   was: 14× (addi/add/lbu/add/sb/bnez) ≈ 84 insn; now 8 insn
    #   a0 = &scratch; t1 = Q+16; bytes 14..15 are slot pad (ok to copy)
    lw      t2,  0(a0)
    lw      t3,  4(a0)
    lw      t4,  8(a0)
    lw      t5, 12(a0)
    sw      t2,  0(t1)
    sw      t3,  4(t1)
    sw      t4,  8(t1)
    sw      t5, 12(t1)
    mv      a6, t1

heuristic_core:
    # 5b. Hot child heuristic — keep a1=m, a5=face; child @ Q+16
    #     v5c2: beqz s3 → r0_id_path (cold); r≠0 falls into waterfall
    #     v2b:  s → inv → σ → σ²; each PDB_NIBBLE, h>r → search_top
    #     v5a:  walk=a4; s1 stays MOVES (no li s1,9 in nibble)

    beqz    s3, r0_id_path                         # v5c2: rare r==0

    # PDB_NIBBLE (v3 idx + v5c3 form): t6=a, t4=o → t0=h; prune if h>r
    #   (a) idx=(a<<10)+o; nibble extract; bltu s3,t0,search_top
    #   (b) slli;andi 4 ≡ (idx&1)<<2 (same length as andi 1;slli 2)
    #   (c) lbu→srl has 2-insn gap; s1=MOVES untouched
    .macro  PDB_NIBBLE
    slli    t0, t6, 10
    add     t0, t0, t4                             # idx = a*1024 + o

    srli    t1, t0, 1
    add     t2, t1, s8                             # &pdb[idx>>1]
    lbu     t3, 0(t2)
    slli    t4, t0, 2                              # (idx&1)<<2
    andi    t4, t4, 4
    srl     t3, t3, t4
    andi    t0, t3, 15                             # t0 = h

    bltu    s3, t0, search_top                     # r < h → prune
    .endm

    # --- h(s): pos in scratch; fold o; PDB_NIBBLE ---
    addi    a4, s4, 16                             # a4 = &child.p[0]

    # build pos[]: scratch[p[i]]=i  (v5c5: addi a4 fills lbu→add)
    li      t0, 0
    li      t1, 7
loop_heuristic_core_p:
    lbu     t2, 0(a4)                              # p[i]
    addi    a4, a4, 1                              # v5c5 fill p→use
    add     t3, t2, s9
    sb      t0, 0(t3)                              # scratch[p[i]] = i
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_core_p

    # a = arank[pos0<<6 | pos3<<3 | pos6]; a4 now at &child.o[0]
    lbu     t0, 0(s9)                              # pos0 = scratch[0]
    lbu     t1, 3(s9)                              # pos3 = scratch[3]
    lbu     t2, 6(s9)                              # pos6 = scratch[6]
    slli    t3, t0, 6                              # pos0 << 6
    slli    t4, t1, 3                              # pos3 << 3
    or      t5, t3, t4
    or      t5, t5, t2                             # pack
    add     t6, t5, s7
    lbu     t6, 0(t6)                              # a = arank[...]

    # fold s.o[0..5] → t4
    li      t0, 0
    li      t1, 6
    li      t4, 0                                  # o = 0
loop_heuristic_core_o:
    lbu     t2, 0(a4)                              # o[i]
    slli    t3, t4, 1                              # o*2
    add     t4, t4, t3                             # o*3
    add     t4, t4, t2                             # o*3 + o[i]
    addi    t0, t0, 1
    addi    a4, a4, 1
    bne     t0, t1, loop_heuristic_core_o

    PDB_NIBBLE

    # --- h(inv): reuse pos from h(s); arank from child.p[0|3|6] (v2b) ---
    #     v5c1: inv.o via mod3tab[a7]
    addi    a4, s4, 16
    addi    a4, a4, 7                              # &child.o[0] (no inv_p rebuild)

    # a = arank[child.p[0]<<6 | p[3]<<3 | p[6]]
    addi    t0, s4, 16
    lbu     t1, 0(t0)                              # child.p[0]
    lbu     t2, 3(t0)                              # child.p[3]
    lbu     t3, 6(t0)                              # child.p[6]
    slli    t4, t1, 6
    slli    t5, t2, 3
    or      t4, t4, t5
    or      t4, t4, t3
    add     t6, t4, s7
    lbu     t6, 0(t6)                              # a = arank[...]

    # fold inv.o[0..5]: o=(3-s.o[i])%3, i=scratch[j]
    li      t0, 0
    li      t1, 6
    li      t4, 0                                  # o fold = 0
    li      t5, 3                                  # for (3-x)%3
loop_heuristic_core_inv_o:
    add     t2, s9, t0
    lbu     t2, 0(t2)                              # i = scratch[j] = inv.p[j]
    add     t2, a4, t2
    lbu     t2, 0(t2)                              # s.o[i]
    sub     t3, t5, t2                             # 3 - s.o[i]

    add     t3, a7, t3
    lbu     t3, 0(t3)                              # mod3tab[3 - s.o[i]]

    slli    t2, t4, 1
    add     t4, t4, t2                             # o*3
    add     t4, t4, t3                             # + inv.o[j]
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_core_inv_o

    PDB_NIBBLE


    # --- h(σ(child)): y @ scratch[0..13]; then PDB_NIBBLE ---
    #     y.p[sig[i]]=sig[p[i]]; y.o[sig[i]]=(o+3+kk[i]-kk[p[i]])%3
    #     v5b: while scattering y.p, if value is cubie 0|3|6 fold sig[i]
    #          into a2=pos0<<6|pos3<<3|pos6 — no 7-scan index
    #     v5c1: %3 via mod3tab[a7]; a3=&sig pinned (v5a)
    addi    a4, s4, 16


    # build y.p[sig[i]] = sig[p[i]] + arank pack in a2 (v5b)
    li      t0, 0
    li      t1, 7
    li      t4, 3                                  # cubie 3
    li      t5, 6                                  # cubie 6
    li      a2, 0                                  # a2 = pack
loop_heuristic_core_sym_p_build:
    lbu     t2, 0(a4)                              # p[i]
    add     t3, t2, a3
    lbu     t3, 0(t3)                              # sig[p[i]] = value

    add     t2, t0, a3
    lbu     t2, 0(t2)                              # sig[i] = dest index

    # pack before t2 += S (need bare sig[i])
    bnez    t3, loop_heuristic_core_sym_p_build_skip1
    slli    t6, t2, 6
    or      a2, a2, t6                             # | pos0<<6

loop_heuristic_core_sym_p_build_skip1:
    bne     t3, t4, loop_heuristic_core_sym_p_build_skip2
    slli    t6, t2, 3
    or      a2, a2, t6                             # | pos3<<3

loop_heuristic_core_sym_p_build_skip2:
    bne     t3, t5, loop_heuristic_core_sym_p_build_skip3
    or      a2, a2, t2                             # | pos6

loop_heuristic_core_sym_p_build_skip3:

    add     t2, t2, s9
    sb      t3, 0(t2)                              # y.p[sig[i]]

    addi    t0, t0, 1
    addi    a4, a4, 1
    bne     t0, t1, loop_heuristic_core_sym_p_build


    # build y.o[...]; a2 pack live; v5c1 %3 via mod3tab (a7)
    li      t0, 0
    li      t1, 7

loop_heuristic_core_sym_o_build:
    lbu     t2, 0(a4)                              # o[i]
    addi    t3, t2, 3
    add     t2, a3, t0
    lbu     t2, 7(t2)                              # kk[i]
    add     t4, t2, t3                             # o[i]+3+kk[i]
    lbu     t2, -7(a4)                             # p[i]
    add     t3, t2, a3
    lbu     t3, 7(t3)                              # kk[p[i]]
    sub     t4, t4, t3                             # o[i]+3+kk[i]-kk[p[i]]

    add     t4, a7, t4
    lbu     t4, 0(t4)                              # mod3tab[o[i]+3+kk[i]-kk[p[i]]]

    add     t2, t0, a3
    lbu     t3, 0(t2)                              # sig[i]
    add     t2, t3, s9
    sb      t4, 7(t2)                              # y.o[sig[i]]

    addi    t0, t0, 1
    addi    a4, a4, 1
    bne     t0, t1, loop_heuristic_core_sym_o_build

    # v5b: arank from pack in a2 (no sym_p_index 7-scan)
    mv      t6, a2
    add     t6, t6, s7
    lbu     t6, 0(t6)                              # a = arank[pack]

    # fold y.o[0..5] → t4; keep a in t6
    li      t0, 0
    li      t1, 6
    li      t4, 0
loop_heuristic_core_sym_o_index:
    add     t2, s9, t0
    lbu     t2, 7(t2)                              # y.o[j]
    slli    t3, t4, 1
    add     t4, t4, t3
    add     t4, t4, t2

    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_core_sym_o_index

    PDB_NIBBLE


    # --- h(σ²): z=sym3(y); in=y@S+0, out=z@S+14; same v5b pack-while-scatter ---
    mv      a4, s9                                 # y.p[0], not child


    # build z.p[sig[i]] = sig[y.p[i]] at S+14; pack into a2 (v5b)
    li      t0, 0
    li      t1, 7
    li      t4, 3
    li      t5, 6
    li      a2, 0                                  # a2 = pack (fresh for z)
loop_heuristic_core_sym2_p_build:
    lbu     t2, 0(a4)                              # y.p[i]
    add     t3, t2, a3
    lbu     t3, 0(t3)                              # sig[y.p[i]] = value

    add     t2, t0, a3
    lbu     t2, 0(t2)                              # sig[i] = dest

    bnez    t3, loop_heuristic_core_sym2_p_build_skip1
    slli    t6, t2, 6
    or      a2, a2, t6

loop_heuristic_core_sym2_p_build_skip1:
    bne     t3, t4, loop_heuristic_core_sym2_p_build_skip2
    slli    t6, t2, 3
    or      a2, a2, t6

loop_heuristic_core_sym2_p_build_skip2:
    bne     t3, t5, loop_heuristic_core_sym2_p_build_skip3
    or      a2, a2, t2

loop_heuristic_core_sym2_p_build_skip3:

    add     t2, t2, s9
    sb      t3, 14(t2)                             # z.p[sig[i]] (not y.p @0)

    addi    t0, t0, 1
    addi    a4, a4, 1
    bne     t0, t1, loop_heuristic_core_sym2_p_build

    # build z.o; a2 pack live
    li      t0, 0
    li      t1, 7

loop_heuristic_core_sym2_o_build:
    lbu     t2, 0(a4)                              # y.o[i]
    addi    t3, t2, 3
    add     t2, a3, t0
    lbu     t2, 7(t2)                              # kk[i]
    add     t4, t2, t3                             # y.o[i]+3+kk[i]
    lbu     t2, -7(a4)                             # y.p[i]
    add     t3, t2, a3
    lbu     t3, 7(t3)                              # kk[y.p[i]]
    sub     t4, t4, t3                             # y.o[i]+3+kk[i]-kk[y.p[i]]

    add     t4, a7, t4
    lbu     t4, 0(t4)                              # mod3tab[y.o[i]+3+kk[i]-kk[y.p[i]]]

    add     t2, t0, a3
    lbu     t3, 0(t2)                              # sig[i]
    add     t2, t3, s9
    sb      t4, 21(t2)                             # z.o[sig[i]]

    addi    t0, t0, 1
    addi    a4, a4, 1
    bne     t0, t1, loop_heuristic_core_sym2_o_build


    # v5b: arank from z pack in a2 (no sym2_p_index 7-scan)
    mv      t6, a2
    add     t6, t6, s7
    lbu     t6, 0(t6)                              # a = arank[pack]

    # fold z.o[0..5] → t4; keep a in t6
    li      t0, 0
    li      t1, 6
    li      t4, 0
loop_heuristic_core_sym2_o_index:
    add     t2, s9, t0
    lbu     t2, 21(t2)                             # z.o[j]
    slli    t3, t4, 1
    add     t4, t4, t3
    add     t4, t4, t2
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_core_sym2_o_index

    PDB_NIBBLE

    # all views h<=r: push; identity → found, else deepen at child (m=0)
    sb      a1,  0(s5)                             # path[g] = m
    li      a1, 0                                  # a1 = m = 0 for the child
    sb      a5, 24(s5)                             # pface[g + 1] = face_of[m] (P + 24)

    addi    s2, s2, 1                              # s2 = g = g + 1
    addi    s3, s3, -1                             # s3 = r = r - 1
    addi    s4, s4, 16                             # Q = &states[g + 1]
    addi    s5, s5, 1                              # P = &path[g + 1]

    mv      t5, a5                                 # pface for next depth
    li      t0, 0
    li      t1, 7
    mv      t6, s4
solve_loop:
    lbu     t2, 0(t6)                              # t2 = p[i]
    bne     t0, t2, child
    lbu     t2, 7(t6)
    bnez    t2, child

    addi    t0, t0, 1
    addi    t6, t6, 1
    bne     t0, t1, solve_loop


found:
    # 6. format path[0..g) into out
    #    (a) need = sum(name lens) + (g-1) spaces + 1 NUL
    #    (b) if cap < need → -2; else write names + NUL; return a0=g
    la      s5, path
    la      t6, move_names

    li      t0, 0
    li      t5, 0                                  # t5 = need
found_length_loop:
    add     t1, t0, s5
    lbu     t2, 0(t1)                              # t2 = path[i]
    
    slli    t1, t2, 1
    add     t1, t6, t1                             # t1 = &move_names[path[i]]
    lbu     t2, 1(t1)                              # t2 = move_names[path[i]][1]
    addi    t5, t5, 1
    beqz    t2, found_length_loop_skip1
    addi    t5, t5, 1

found_length_loop_skip1:
    addi    t1, t0, 1
    beq     t1, s2, found_length_loop_skip2
    addi    t5, t5, 1

found_length_loop_skip2:
    addi    t0, t0, 1
    
    bne     t0, s2, found_length_loop

    addi    t5, t5, 1

    bltu    s11, t5, found_cap_fail 

    li      t0, 0
    mv      t4, s10                                # out cursor
found_index_loop:
    beqz    t0, found_index_loop_skip1                
    li      t2, 32                                 # ' '
    sb      t2, 0(t4)
    addi    t4, t4, 1

found_index_loop_skip1:
    add     t1, s5, t0
    lbu     t2, 0(t1)                              # m
    slli    t1, t2, 1
    add     t1, t6, t1                             # &move_names[m]
    lbu     t2, 0(t1)                              # name[0]
    sb      t2, 0(t4)
    addi    t4, t4, 1
    lbu     t2, 1(t1)                              # name[1]
    beqz    t2, found_index_loop_skip2
    sb      t2, 0(t4)
    addi    t4, t4, 1

found_index_loop_skip2:
    addi    t0, t0, 1
    bne     t0, s2, found_index_loop



found_index_done:
    sb      x0, 0(t4)                              # NUL
    mv      a0, s2
    j       epilogue

    # v5c2 cold path: r==0 → identity check (align C); success → found
r0_id_path:
    addi    t6, s4, 16                             # &child
    li      t0, 0
    li      t1, 7
r0_id:
    lbu     t2, 0(t6)                              # p[i]
    bne     t0, t2, search_top                     # unsolved, r==0 → prune
    lbu     t2, 7(t6)                              # o[i]
    bnez    t2, search_top
    addi    t0, t0, 1
    addi    t6, t6, 1
    bne     t0, t1, r0_id

    sb      a1, 0(s5)                              # path[g] = m
    addi    s2, s2, 1                              # length = g+1 for found
    j       found

found_cap_fail:
    beqz    s11, found_cap_fail_skip1              # cap == 0: don't write NUL
    sb      x0, 0(s10)
found_cap_fail_skip1: 
    li      a0, -2                                 # cap < need: return -2
    j       epilogue

bound_failed:
    addi    s0, s0, 1                              # ++bound
    addi    t0, x0, 11                             # MAX_DEPTH
    bleu    s0, t0, loop_solve
    li      a0, -1                                 # should not happen on valid states

epilogue:
    lw      s0,  0(sp)
    lw      s1,  4(sp)
    lw      s2,  8(sp)
    lw      s3, 12(sp)
    lw      s4, 16(sp)
    lw      s5, 20(sp)
    lw      s6, 24(sp)
    lw      s7, 28(sp)
    lw      s8, 32(sp)
    lw      s9, 36(sp)
    lw      s10, 40(sp)
    lw      s11, 44(sp)
    addi    sp, sp, 64
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm
