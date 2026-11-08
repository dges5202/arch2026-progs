# rubik_solve_asm — HW2 IDA* (pos3ori PDB + inv/σ), tables in tables.S / .data
# Contract: a0=state, a1=out, a2=cap; result in a0 (-1 / -2 / length).
# Body still contains HW1 code; HW2 register map below is the target ABI.
# Markers: lines/blocks tagged "HW1-CUT" conflict with HW2 — drop when rewriting.
# Gas has no C preprocessor here (Makefile uses `as`); HW1 EXPECT/RENDER
# gates below are `.if 0` so bare `as` skips them.
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
#  | a0  | in ptr (then clobbered) | temp / face<<3 / index math             |
#  | a1  | out — SAVE to s10 ASAP  | m                                       |
#  | a2  | cap — SAVE to s11 ASAP  | turns / apply loop                      |
#  | a3  | parse temps             | face / from alias                       |
#  | a4  | parse temps             | (free vs HW1 c3_dist)                   |
#  | a5  | parse temps             | face_of[m]                              |
#  | a6  | parse temps             | Fsrc = Q + from_off[m]                  |
#  | a7  | (avoid)                 | (avoid)                                 |
#  | t0-6| parse / rank / h temps  | apply, pdb index, h, prune              |
#  +-----+----------------------+--------------------------------------------+
#  | ra  | ret                         | (unused in explicit DFS)            |
#  | sp  | frame if any                |                                     |
#  | gp  | unused                      |                                     |
#  | tp  | unused                      |                                     |
#  +-----+-----------------------------+-------------------------------------+
#
#  Table bases in hot loop: only A (s7) + D (s8).  HW1 needed six.
#  Child: always write states[g+1] at Q+16; sibling apply via from_off.
#
# -------
#  HOT-LOOP REGISTER PRESSURE (evaluation)
# -------
#
#  Pinned whole search (must not spill mid-child), CURRENT map:
#    s0..s9  = bound, MOVES, g, r, Q, P, F, A, D, S     (10)
#    s10,s11 = out*, cap                                 (2)  → s0..s11 FULL
#
#  Free for one child (apply → heuristic → prune → maybe push):
#    t0..t6          = 7
#    a0,a2,a3,a4     = 4   (a1=m, a5=face, a6=Fsrc pinned in child)
#    a7              = 1 optional
#    --------------------
#    ≈ 11–12 temps, all caller-saved / scratch; no spare s-reg
#
#  Peak live sets (sequential phases — NOT all at once):
#
#    (1) search_top / pick m
#        need: P, F, s1, a1=m, a5=face, t*: next/pface/from_off
#        temps ≈ 3–4          OK
#
#    (2) apply (sibling): Fsrc → Q+16, turns_of[m] quarter loops
#        pinned: Q, Fsrc(a6), face/rows, dest=Q+16
#        loop:   i, from, byte loads, source* / twist* (+turns)
#        temps ≈ 6–8 + a6,a5  OK (reuse i/from each cubie)
#        NOTE: do NOT keep 14 cubie bytes in regs — memory AoS only
#
#    (3) h_pos3ori(view*)  [s at Q+16, or S after inv/σ]
#        scan p[] for pos0/3/6 (or 7-byte pos in scratch — avoid regs)
#        ori fold o[0..5]; idx=a*729+o; nibble from D
#        temps ≈ 6–8 + A,D   OK if one view at a time
#
#    (4) waterfall: run_max vs r(s3); inv/σ through S; maybe early out
#        live: run_max, r, Q/S, A,D — views serial
#        temps ≈ 4–6          OK
#
#    (5) push: only addi on s2,s3,s4,s5 + sb path/pface
#        temps ≈ 0–2          OK
#
#  Verdict:
#    - No forced stack spill INSIDE apply/heuristic IF phases stay serial
#      and cubies stay in memory (Q/S), not in registers.
#    - Margin is THIN: s0–s11 all taken → cannot park an extra base
#      (e.g. &source) in an s-reg without dropping something.
#    - out/cap are DEAD during search (only needed at format). Keeping
#      them in s10/s11 buys convenience, costs two hot s-regs.
#
#  Safer tweak (if apply feels tight): before loop_solve
#      sw out/cap to .data (or stack); free s10,s11
#      e.g. s10=&source, s11=&twist  (or leave spare)
#      reload out/cap only when writing the move string.
#  Then hot loop has spare s-regs and pressure is clearly fine.
#
#  HW1-CUT index (grep HW1-CUT): body — parse/rank/ci/search/ecall/T5.
#  .data below is HW2; rubik_arank|rubik_pdb come from tables.S (link), not here.
#

    .data
    # Order: states → scratch → P → F → source/twist/sig/kk → move_names

    states: .zero 192                   # 12*16; Q=&states[g]; p@0..6 o@7..13
    scratch:.zero 32                    # inv; σ: y@0..13; σ²: z@14..27

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

    # -------
    # PARSE / SETUP — register assignment for this phase
    # -------
    #
    # On entry (from rubik_solve_asm):
    # a0 = state*     a1 = out*     a2 = cap
    #
    # First moves (must happen before clobbering a1/a2):
    # s10 <- a1 (out)     s11 <- a2 (cap)
    #
    # +-----+----------------------------------------------+
    # | reg | role during parse                            |
    # +-----+----------------------------------------------+
    # | a0  | in*  (or copy to s0 and walk s0)             |
    # | a1  | out* — saved to s10 immediately              |
    # | a2  | cap  — saved to s11 immediately              |
    # | s0  | walking read pointer into state string       |
    # | s1  | walking write pointer into states[0].p/.o    |
    # | s2  | optional second cursor / length checks       |
    # | s3-9| free until post-parse la of Q,P,F,A,D,S      |
    # | s10 | out*  (live through search + format)         |
    # | s11 | cap   (live through search + format)         |
    # | t0  | i                                            |
    # | t1  | limit (7 / 14)                                |
    # | t2  | loaded char                                  |
    # | t3  | char - '1' / validation                      |
    # | t4-6| seen-bitmask, ori sum, reject paths          |
    # +-----+----------------------------------------------+
    #
    # After a valid parse: write root into states[0], then:
    # la s4, states / path→s5 / face_of→s6 / arank→s7 /
    # pdb→s8 / scratch→s9;  li s1, 9;  compute bound→s0; …
    #
    # YOU write parse here (a0 → states[0]). Agent guides only.
    #
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

    # 1. parse: 14 ASCII digits → states[0] (0-based p[7] then o[7])
    #    in = PPPPPPPOOOOOOO, value = ch - '1'
    la      s1, states
    li      t0, 7

loop_p:
    lbu     t2,  0(a0)
    addi    t3, t2, -49                 # t3 = in[i] - '1'
    sb      t3,  0(s1)

    addi    t0, t0, -1
    addi    a0, a0, 1
    addi    s1, s1, 1
    bnez    t0, loop_p

    li      t0, 7

loop_o:
    lbu     t2,  0(a0)
    addi    t3, t2, -49                 # t3 = in[CUBIES + i] - '1'
    sb      t3,  0(s1)

    addi    t0, t0, -1
    addi    a0, a0, 1
    addi    s1, s1, 1
    bnez    t0, loop_o

    # 2. already solved? identity on states[0] (before rank)
    #    p[i] == i for i = 0..6, o[i] == 0 for i = 0..6
    #    yes → out="" (if cap>=1), return 0;  cap==0 → return -2
    la      s1, states                  # s1 = &states[0].p[0]

    li      t0, 0
    li      t1, 7
decision_loop_p:
    lbu     t2,  0(s1)                  # t2 = p[i]
    bne     t0, t2, rank_start

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, decision_loop_p

    li      t1, 14
decision_loop_o:
    lbu     t2,  0(s1)                  # t2 = o[i]
    bnez    t2, rank_start

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, decision_loop_o

    beqz    s11, exit_program           # cap == 0 → -2
    sb      x0, 0(s10)                  # out[0] = '\0'
    li      a0, 0
    j       epilogue

exit_program:
    li      a0, -2
    j       epilogue

rank_start:
    # 3. a5 = rank_perm(p), a6 = rank_ori(o). No mul: shifts and adds.
    #    (HW1 indices; HW2 search may drop these later for pos3ori)
    #
    # --- rank_perm ---
    # Lehmer digits into scratch[0..5]:
    #   for (i = 0; i < CUBIES - 1; ++i) {
    #     smaller = 0;
    #     for (j = i + 1; j < CUBIES; ++j)
    #       smaller += (p[j] < p[i]);
    #     scratch[i] = smaller;
    #   }
    # Then pack (factorial number system, no mul):
    #   r = scratch[0];
    #   r = (r << 2) + (r << 1) + scratch[1];  /* *6 */
    #   r = (r << 2) + r + scratch[2];         /* *5 */
    #   r = (r << 2) + scratch[3];             /* *4 */
    #   r = (r << 1) + r + scratch[4];         /* *3 */
    #   r = (r << 1) + scratch[5];             /* *2 */  → a5
    #
    la      s0, scratch                 # s0 = &scratch[0]
    la      s1, states                  # s1 = &states[0].p[0]

    addi    t0, x0, 0                   # t0 = i
    addi    t1, x0, 6                   # t1 = CUBIES - 1
    addi    t3, t1, 1                   # t3 = CUBIES

loop_rank_p_out:
    addi    t6, x0, 0                   # t6 = smaller
    addi    t2, t0, 1                   # t2 = j = i + 1
    lbu     t4,  0(s1)                  # t4 = p[i]
    addi    a1, s1, 1                   # a1 = &p[j]
loop_rank_p_in:
    lbu     t5,  0(a1)                  # t5 = p[j]
    slt     a0, t5, t4                  # a0 = (p[j] < p[i])
    add     t6, t6, a0
    addi    t2, t2, 1
    addi    a1, a1, 1

    bne     t2, t3, loop_rank_p_in

    sb      t6,  0(s0)                  # scratch[i] = smaller
    addi    t0, t0, 1
    addi    s0, s0, 1
    addi    s1, s1, 1

    bne     t0, t1, loop_rank_p_out
    addi    s1, s1, 1                   # s1 → &states[0].o[0]

    # pack scratch[] → a5
    la      s0, scratch                 # s0 = &scratch[0]
    lbu     t0,  0(s0)                  # t0 = r = scratch[0]

    lbu     t1,  1(s0)                  # t1 = scratch[1]
    slli    t2, t0, 2                   # t2 = r << 2
    slli    t3, t0, 1                   # t3 = r << 1
    add     t0, t1, t2
    add     t0, t0, t3                  # r = r*6 + scratch[1]

    lbu     t1,  2(s0)                  # t1 = scratch[2]
    slli    t2, t0, 2                   # t2 = r << 2
    add     t0, t0, t1
    add     t0, t0, t2                  # r = r*5 + scratch[2]

    lbu     t1,  3(s0)                  # t1 = scratch[3]
    slli    t2, t0, 2                   # t2 = r << 2
    add     t0, t1, t2                  # r = r*4 + scratch[3]

    lbu     t1,  4(s0)                  # t1 = scratch[4]
    slli    t2, t0, 1                   # t2 = r << 1
    add     t0, t0, t1
    add     t0, t0, t2                  # r = r*3 + scratch[4]

    lbu     t1,  5(s0)                  # t1 = scratch[5]
    slli    t2, t0, 1                   # t2 = r << 1
    add     a5, t1, t2                  # a5 = r*2 + scratch[5] = rank_perm

    # --- rank_ori ---
    # r = 0; for (i = 0; i < 6; ++i) r = r*3 + o[i];  → a6
    # (o[6] unused; s1 already at o[0])
    li      t0, 6                       # 6 iterations
    li      a6, 0                       # a6 = r
loop_rank_o:
    lbu     t2,  0(s1)                  # t2 = o[i]
    slli    t3, a6, 1                   # t3 = r << 1
    add     a6, a6, t3                  # a6 = r*3
    add     a6, a6, t2                  # a6 = r*3 + o[i]

    addi    t0, t0, -1
    addi    s1, s1, 1
    bnez    t0, loop_rank_o




    # -------
    # heuristic — admissible h = max of four pos3ori PDB lookups
    #
    # C:
    #   unsigned h = h_pos3ori(s);
    #   h = max(h, h_pos3ori(&invert(s)));
    #   state_t y = sym3(s);   h = max(h, h_pos3ori(&y));
    #   state_t z = sym3(&y);  h = max(h, h_pos3ori(&z));
    #   return h;   /* → s0 */
    #
    # Shared pdb_index: a = arank[pos0<<6 | pos3<<3 | pos6];
    #                   o = fold o[0..5] as (((o*3)+…); idx = a*729 + o;
    #                   nibble = (pdb[idx>>1] >> ((idx&1)<<2)) & 15.
    # Scratch: inv uses [0..6] as inv.p; σ writes y@0..13; σ² writes z@14..27.
    # Bases after setup: s7=A, s8=D, s9=S (live through all four views).
    # OPT later: fuse pos-scan + ori fold per view; arank still after.
    # LATER (optional): pad PDB stride 729→1024 → idx=(a<<10)+o (~2 insn);
    #   costs ~+31KB nibble pdb, needs gen_tables — only if data budget allows.
    # -------

    # ---------------------------------------------------------------------
    # h_pos3ori(s)  —  index states[0] directly, seed s0 = h
    #
    # C:  h = pdb_get(pdb_index(s));
    #     /* pos[p[i]]=i; a=arank[pos[0]<<6|pos[3]<<3|pos[6]];
    #        o=fold s.o[0..5]; return nibble(a*729+o) */
    # ---------------------------------------------------------------------
    la      s1, states                  # cursor at s.p[0]
    la      s7, rubik_arank             # s7 = A = &rubik_arank[0]
    la      s8, rubik_pdb               # s8 = D = &rubik_pdb[0]
    la      s9, scratch                 # s9 = S = &scratch[0]

    # build pos[]: scratch[p[i]] = i
    li      t0, 0
    li      t1, 7
loop_heuristic_p:
    lbu     t2, 0(s1)                  # p[i]
    add     t3, t2, s9
    sb      t0, 0(t3)                  # scratch[p[i]] = i
    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_p

    # a = arank[pos0<<6 | pos3<<3 | pos6]; s1 now at &s.o[0]
    lbu     t0, 0(s9)                  # pos0 = scratch[0]
    lbu     t1, 3(s9)                  # pos3 = scratch[3]
    lbu     t2, 6(s9)                  # pos6 = scratch[6]
    slli    t3, t0, 6                  # pos0 << 6
    slli    t4, t1, 3                  # pos3 << 3
    or      t5, t3, t4
    or      t5, t5, t2                 # pack
    add     t6, t5, s7
    lbu     t6, 0(t6)                  # a = arank[...]

    # fold s.o[0..5] → t4
    li      t0, 0
    li      t1, 6
    li      t4, 0                       # o = 0
loop_heuristic_o:
    lbu     t2, 0(s1)                  # o[i]
    slli    t3, t4, 1                  # o*2
    add     t4, t4, t3                 # o*3
    add     t4, t4, t2                 # o*3 + o[i]
    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_o

    # idx = a*729 + o; pdb nibble → s0 (first h, no max yet)
    slli    t0, t6, 9
    slli    t1, t6, 7
    add     t0, t0, t1
    slli    t1, t6, 6
    add     t0, t0, t1
    slli    t1, t6, 4
    add     t0, t0, t1
    slli    t1, t6, 3
    add     t0, t0, t1
    add     t0, t0, t6
    add     t0, t0, t4                 # idx

    srli    t1, t0, 1
    add     t2, t1, s8                 # &pdb[idx >> 1]
    lbu     t3, 0(t2)
    andi    t4, t0, 1
    slli    t4, t4, 2
    srl     t3, t3, t4
    andi    s0, t3, 15                 # s0 = h(s)

    # ---------------------------------------------------------------------
    # h_pos3ori(inv(s))  —  max into s0
    #
    # C:  r = invert(s);  /* r.p[c]=i, r.o[c]=(3-o[i])%3  where c=p[i] */
    #     h = max(h, h_pos3ori(&r));
    #
    # Asm shortcut (no full r.o[] store):
    #   Reuse scratch[0..6] from h(s) — same bytes as inv.p (pos of each cubie).
    #   pos of cubie c in inv equals s.p[c]  →  arank uses s.p[0],p[3],p[6]
    #     directly (not scratch[0,3,6]).
    #   inv.o[j]=(3-s.o[i])%3 with i=scratch[j]; fold j=0..5 via s1=&s.o[0].
    # ---------------------------------------------------------------------
    la      s1, states
    addi    s1, s1, 7                  # &s.o[0] (inv_p rebuild removed)

    # a = arank[s.p[0]<<6 | s.p[3]<<3 | s.p[6]]
    la      t0, states
    lbu     t1, 0(t0)                  # s.p[0] = pos of cubie 0 in inv
    lbu     t2, 3(t0)                  # s.p[3]
    lbu     t3, 6(t0)                  # s.p[6]
    slli    t4, t1, 6
    slli    t5, t2, 3
    or      t4, t4, t5
    or      t4, t4, t3
    add     t6, t4, s7
    lbu     t6, 0(t6)                  # a = arank[...]

    # fold inv.o[0..5]: o=(3-s.o[i])%3, i=scratch[j]
    li      t0, 0
    li      t1, 6
    li      t4, 0                       # o fold = 0
    li      t5, 3                       # for (3-x)%3
loop_heuristic_inv_o:
    add     t2, s9, t0
    lbu     t2, 0(t2)                  # i = scratch[j] = inv.p[j]
    add     t2, s1, t2
    lbu     t2, 0(t2)                  # s.o[i]
    sub     t3, t5, t2                 # 3 - s.o[i]
    bne     t3, t5, loop_heuristic_inv_o_skip
    sub     t3, t5, t3                 # if 3: → 0  ((3-0)%3)
loop_heuristic_inv_o_skip:
    slli    t2, t4, 1
    add     t4, t4, t2                 # o*3
    add     t4, t4, t3                 # + inv.o[j]
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_inv_o

    # idx = a*729 + o; pdb nibble; max into s0
    slli    t0, t6, 9
    slli    t1, t6, 7
    add     t0, t0, t1
    slli    t1, t6, 6
    add     t0, t0, t1
    slli    t1, t6, 4
    add     t0, t0, t1
    slli    t1, t6, 3
    add     t0, t0, t1
    add     t0, t0, t6
    add     t0, t0, t4

    srli    t1, t0, 1
    add     t2, t1, s8
    lbu     t3, 0(t2)
    andi    t4, t0, 1
    slli    t4, t4, 2
    srl     t3, t3, t4
    andi    t0, t3, 15
    blt     t0, s0, heuristic_skip1

    mv      s0, t0

heuristic_skip1:

    # ---------------------------------------------------------------------
    # h_pos3ori(σ(s))  —  y = sym3(s), pdb_index(y), max into s0
    #
    # C:  state_t y = sym3(s);
    #     h = max(h, h_pos3ori(&y));
    #     /* y.p[sig[i]] = sig[p[i]];
    #        y.o[sig[i]] = (o[i]+3+kk[i]-kk[p[i]])%3 */
    #
    # Bases: s7=A, s8=D, s9=S live. Reload: s1=&states, t5=&sig (kk at t5+7).
    # Index packing clobbers t5 — σ² must la t5,sig again.
    # After this block scratch: [0..6]=y.p [7..13]=y.o | [14..27] for z.
    # ---------------------------------------------------------------------
    la      s1, states                  # cursor at s.p[0]
    la      t5, sig                     # &sig[0]; kk at t5+7

    # build y.p[sig[i]] = sig[p[i]]
    li      t0, 0
    li      t1, 7
loop_heuristic_sym_p_build:
    lbu     t2, 0(s1)                  # p[i]
    add     t3, t2, t5
    lbu     t3, 0(t3)                  # sig[p[i]]

    add     t2, t0, t5
    lbu     t2, 0(t2)                  # sig[i]

    add     t2, t2, s9
    sb      t3, 0(t2)                  # y.p[sig[i]]

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_sym_p_build

    # build y.o[sig[i]] = (o[i]+3+kk[i]-kk[p[i]]) % 3; s1 at &s.o[0]
    li      t0, 0
    li      t1, 7
    li      t6, 3                       # %3 threshold
loop_heuristic_sym_o_build:
    lbu     t2, 0(s1)                  # o[i]
    addi    t3, t2, 3
    add     t2, t5, t0
    lbu     t2, 7(t2)                  # kk[i]
    add     t4, t2, t3                 # o[i]+3+kk[i]
    lbu     t2, -7(s1)                 # p[i]
    add     t3, t2, t5
    lbu     t3, 7(t3)                  # kk[p[i]]
    sub     t4, t4, t3                 # o[i]+3+kk[i]-kk[p[i]]

    blt     t4, t6, loop_heuristic_sym_o_skip
    sub     t4, t4, t6
    blt     t4, t6, loop_heuristic_sym_o_skip
    sub     t4, t4, t6                 # %3 (t4 was in 2..6)

loop_heuristic_sym_o_skip:
    add     t2, t0, t5
    lbu     t3, 0(t2)                  # sig[i]
    add     t2, t3, s9
    sb      t4, 7(t2)                  # y.o[sig[i]]

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_sym_o_build

    # pdb_index(y): pack pos of cubies 0,3,6 from y.p into t6, then arank
    li      t0, 0
    li      t1, 7
    li      t3, 3                       # cubie 3
    li      t4, 6                       # cubie 6
    li      t6, 0
loop_heuristic_sym_p_index:
    add     t2, t0, s9
    lbu     t2, 0(t2)                  # y.p[i]
    bne     t2, x0, loop_heuristic_sym_p_index_skip1
    slli    t5, t0, 6                  # clobbers &sig
    or      t6, t5, t6                 # | pos0<<6
loop_heuristic_sym_p_index_skip1:
    bne     t2, t3, loop_heuristic_sym_p_index_skip2
    slli    t5, t0, 3
    or      t6, t5, t6                 # | pos3<<3
loop_heuristic_sym_p_index_skip2:
    bne     t2, t4, loop_heuristic_sym_p_index_skip3
    or      t6, t0, t6                 # | pos6
loop_heuristic_sym_p_index_skip3:
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_sym_p_index

    add     t6, t6, s7
    lbu     t6, 0(t6)                  # a = arank[...]

    # fold y.o[0..5] → t4; keep a in t6
    li      t0, 0
    li      t1, 6
    li      t4, 0
loop_heuristic_sym_o_index:
    add     t2, s9, t0
    lbu     t2, 7(t2)                  # y.o[j]
    slli    t3, t4, 1
    add     t4, t4, t3
    add     t4, t4, t2
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_sym_o_index

    # idx = a*729 + o; pdb nibble; max into s0
    slli    t0, t6, 9
    slli    t1, t6, 7
    add     t0, t0, t1
    slli    t1, t6, 6
    add     t0, t0, t1
    slli    t1, t6, 4
    add     t0, t0, t1
    slli    t1, t6, 3
    add     t0, t0, t1
    add     t0, t0, t6
    add     t0, t0, t4

    srli    t1, t0, 1
    add     t2, t1, s8
    lbu     t3, 0(t2)
    andi    t4, t0, 1
    slli    t4, t4, 2
    srl     t3, t3, t4
    andi    t0, t3, 15
    blt     t0, s0, heuristic_skip2

    mv      s0, t0

heuristic_skip2:

    # ---------------------------------------------------------------------
    # h_pos3ori(σ²(s))  —  z = sym3(y), pdb_index(z), max into s0
    #
    # C:  state_t z = sym3(&y);   /* same sym3, input = y */
    #     h = max(h, h_pos3ori(&z));
    #
    # Same loops as σ; only bases change (cannot overwrite y in-place —
    # sym3 scatters via sig[i]):
    #   in  = y @ S+0   (p[0..6], o[7..13])   — left by σ(s)
    #   out = z @ S+14  (p[14..20], o[21..27])
    #
    # Bases: s7=A, s8=D, s9=S live. Must la t5,sig again (σ index clobbered).
    # s1 walks y, not states.
    # ---------------------------------------------------------------------
    mv      s1, s9                      # cursor at y.p[0]
    la      t5, sig                     # &sig[0]; kk at t5+7

    # build z.p[sig[i]] = sig[y.p[i]]
    li      t0, 0
    li      t1, 7
loop_heuristic_sym2_p_build:
    lbu     t2, 0(s1)                  # y.p[i]
    add     t3, t2, t5
    lbu     t3, 0(t3)                  # sig[y.p[i]]

    add     t2, t0, t5
    lbu     t2, 0(t2)                  # sig[i]

    add     t2, t2, s9
    sb      t3, 14(t2)                 # z.p[sig[i]]

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_sym2_p_build

    # build z.o[sig[i]] = (y.o[i]+3+kk[i]-kk[y.p[i]]) % 3; s1 at &y.o[0]
    li      t0, 0
    li      t1, 7
    li      t6, 3                       # %3 threshold
loop_heuristic_sym2_o_build:
    lbu     t2, 0(s1)                  # y.o[i]
    addi    t3, t2, 3
    add     t2, t5, t0
    lbu     t2, 7(t2)                  # kk[i]
    add     t4, t2, t3                 # y.o[i]+3+kk[i]
    lbu     t2, -7(s1)                 # y.p[i]
    add     t3, t2, t5
    lbu     t3, 7(t3)                  # kk[y.p[i]]
    sub     t4, t4, t3                 # y.o[i]+3+kk[i]-kk[y.p[i]]

    blt     t4, t6, loop_heuristic_sym2_o_skip
    sub     t4, t4, t6
    blt     t4, t6, loop_heuristic_sym2_o_skip
    sub     t4, t4, t6                 # %3 (t4 was in 2..6)

loop_heuristic_sym2_o_skip:
    add     t2, t0, t5
    lbu     t3, 0(t2)                  # sig[i]
    add     t2, t3, s9
    sb      t4, 21(t2)                 # z.o[sig[i]]

    addi    t0, t0, 1
    addi    s1, s1, 1
    bne     t0, t1, loop_heuristic_sym2_o_build

    # pdb_index(z): pack pos of cubies 0,3,6 from z.p into t6, then arank
    li      t0, 0
    li      t1, 7
    li      t3, 3                       # cubie 3
    li      t4, 6                       # cubie 6
    li      t6, 0
loop_heuristic_sym2_p_index:
    add     t2, t0, s9
    lbu     t2, 14(t2)                 # z.p[i]
    bne     t2, x0, loop_heuristic_sym2_p_index_skip1
    slli    t5, t0, 6                  # clobbers &sig
    or      t6, t5, t6                 # | pos0<<6
loop_heuristic_sym2_p_index_skip1:
    bne     t2, t3, loop_heuristic_sym2_p_index_skip2
    slli    t5, t0, 3
    or      t6, t5, t6                 # | pos3<<3
loop_heuristic_sym2_p_index_skip2:
    bne     t2, t4, loop_heuristic_sym2_p_index_skip3
    or      t6, t0, t6                 # | pos6
loop_heuristic_sym2_p_index_skip3:
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_sym2_p_index

    add     t6, t6, s7
    lbu     t6, 0(t6)                  # a = arank[...]

    # fold z.o[0..5] → t4; keep a in t6
    li      t0, 0
    li      t1, 6
    li      t4, 0
loop_heuristic_sym2_o_index:
    add     t2, s9, t0
    lbu     t2, 21(t2)                 # z.o[j]
    slli    t3, t4, 1
    add     t4, t4, t3
    add     t4, t4, t2
    addi    t0, t0, 1
    bne     t0, t1, loop_heuristic_sym2_o_index

    # idx = a*729 + o; pdb nibble; max into s0
    slli    t0, t6, 9
    slli    t1, t6, 7
    add     t0, t0, t1
    slli    t1, t6, 6
    add     t0, t0, t1
    slli    t1, t6, 4
    add     t0, t0, t1
    slli    t1, t6, 3
    add     t0, t0, t1
    add     t0, t0, t6
    add     t0, t0, t4

    srli    t1, t0, 1
    add     t2, t1, s8
    lbu     t3, 0(t2)
    andi    t4, t0, 1
    slli    t4, t4, 2
    srl     t3, t3, t4
    andi    t0, t3, 15
    blt     t0, s0, heuristic_skip3

    mv      s0, t0

heuristic_skip3:




    # -------
    #  REG MAP at ida_start (after parse / identity / rank)
    # -------
    #
    #  Live now:
    #    s10 = out,  s11 = cap
    #    a5  = rank_perm (HW1; may drop),  a6 = rank_ori (HW1; may drop)
    #    states[0] = root cubie state
    #
    #  Target HOT LOOP (rewrite below to this; cut HW1 pi/oi/ci/dist):
    #
    #  Push/pop together:  g++|P+1|Q+16|r--   /   g--|P-1|Q-16|r++
    #  Layout: Q+i=p[i], Q+7+i=o[i], Q+16=states[g+1]
    #          P+0=path[g], P+11=next[g], P+23=pface[g]
    #          F+m=face_of, F+9+m=turns_of, F+18+m=from_off (0|16)
    #          D = A+512 = &rubik_pdb ;  S = &scratch
    #
    #  +-----+------------------+------------------------------------------+
    #  | reg | now (setup)      | hot loop (search)                        |
    #  +-----+------------------+------------------------------------------+
    #  | s0  | (free)           | bound                                    |
    #  | s1  | (free)           | MOVES = 9                                |
    #  | s2  | (free)           | g                                        |
    #  | s3  | (free)           | r = bound - g - 1                        |
    #  | s4  | (free)           | Q = &states[g]                           |
    #  | s5  | (free)           | P = &path[g]                             |
    #  | s6  | (free)           | F = &face_of[0]                          |
    #  | s7  | (free)           | A = &rubik_arank                         |
    #  | s8  | (free)           | D = &rubik_pdb                           |
    #  | s9  | (free)           | S = &scratch                             |
    #  | s10 | out              | out (format only; optional spill)        |
    #  | s11 | cap              | cap (format only; optional spill)        |
    #  +-----+------------------+------------------------------------------+
    #  | a0  | clobbered        | temp / index math                        |
    #  | a1  | clobbered        | m                                        |
    #  | a2  | (free)           | turns / apply                            |
    #  | a3  | (free)           | face / from                              |
    #  | a4  | (free)           | temp                                     |
    #  | a5  | rank_perm        | face_of[m]                               |
    #  | a6  | rank_ori         | Fsrc = Q + from_off[m]                   |
    #  | a7  | (avoid)          | (avoid)                                  |
    #  | t0-6| temps            | apply / h_pos3ori / prune                |
    #  +-----+------------------+------------------------------------------+
    #
    #  Before loop_solve: la Q,P,F,A,D,S ; bound = heuristic(states[0])
    #  (h = max h_pos3ori on s / inv / σ / σ²).  Then IDA* core.
    # -------

ida_start:
    # 4. IDA* outer: bound = h(root) .. MAX_DEPTH; each bound → DFS (step 5).
    #    HW1 body below still uses pi/oi/ci — replace with HW2 map above.
    #
    addi    s1, x0, 9                   # s1 = const = 9


    la      s6, face_of                 # s6 = F = &face_of[0]


loop_solve:

    li      s2, 0                       # s2 = g = 0
    addi    s3, s0, -1                  # s3 = r = bound - 1
    la      s4, states                  # s4 = Q = &states[0]
    la      s5, path                    # s5 = P = &path[0]
    sb      x0, 11(s5)                  # next[0] = 0 (next[0] = P + 11)

    # same_face and pop sit right above search_top so both fall into
    # it. Jumping over them costs a taken branch once per bound,
    # instead of one per pop.
    j       search_top                  # skip same_face and pop

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
    addi    a1, t2, 2                   # a1 = m + 3: first turn of the next face
    bne     a1, s1, child               # m + 3 != MOVES: try the next face

    # All moves of depth g tried: back to the parent, then fall into
    # search_top. The parent's next[g] and pface[g] are no longer in any
    # register, so search_top must load them.
    #
    # if (g == 0) goto bound_failed;
    # --g;
    # continue;
pop:
    beq     s2, x0, bound_failed        # all moves tried at the root

    addi    s2, s2, -1                  # s2 = g = g - 1
    addi    s3, s3, 1                   # s3 = r = r + 1
    addi    s4, s4, -1                  # P = &path[g - 1]


    # if (next[g] == MOVES) goto pop;
    #
    # pface[g] is loaded before the beq to fill the slot after lbu a1;
    # a pop loads it for nothing (one instruction).
search_top:
    lbu     a1, 11(s4)                  # a1 = m = next[g] = *(P + 11)
    lbu     t5, 23(s4)                  # t5 = pface[g] = face_of[path[g - 1]]
    beq     a1, s1, pop                 # next[g] == MOVES: all moves tried

    # unsigned m = next[g]++;
    # if (face_of[m] == pface[g])     /* pface[0] = 3: never at the root */
    # goto same_face;
    #
    # The next[g] store sits between lbu a5 and the beq that reads a5.
child:
    add     t3, s5, a1                  # face_of[m]'s memory
    lbu     a5,  0(t3)                  # a5 = face_of[m]
    addi    t2, a1, 1                   # t2 = m + 1
    sb      t2, 11(s4)                  # next[g] = m + 1
    beq     t5, a5, same_face           # same face as path[g - 1]: skip it

    # pi[g + 1] holds the previous sibling, so each child is one turn:
    # unsigned from = turns_of[m] == 1 ? g : g + 1;
    # A table instead of a compare and branch: F = Q + from_off[m].
no_prev:
    # perm_move[face_of[m]], ori_move[face_of[m]]: pick the face's tables.
    # slli a0 fills the slot between lbu t1 and the add that reads it.
    lbu     t1, 18(t3)                  # t1 = from_off[m] = *(&face_of[m] + 18)
    slli    a0, a5, 14                  # a0 = face << 14 = face * 16384
    add     a6, s3, t1                  # F = Q + from_off[m] = &pi[from]
    add     t0, a0, s6                  # t0 = perm_move_r + face * 16384

    slli    t1, a5, 11                  # t1 = face << 11 = face * 2048
    add     t1, t1, s7                  # t1 = ori_move_r + face * 2048

    # unsigned cp = perm_move[face_of[m]][pi[from]];
    # unsigned co = ori_move[face_of[m]][oi[from]];
    #
    # Both indices are loaded first, so neither load is used by the
    # instruction right after it.
selected:
    lhu     t3,  0(a6)                  # t3 = pi[from] = *F
    lhu     a3, 24(a6)                  # a3 = oi[from] = *(F + 24)

    # cp
    slli    t4, t3, 1                   # t4 = pi[from] << 1, .half entries
    add     t2, t4, t0                  # t2 = perm_move_x[0]'s memory + pi[from]
    lhu     t6,  0(t2)                  # t6 = perm_move[face_of[m]][pi[from]]

    # co
    slli    t4, a3, 1                   # t4 = oi[from] << 1, .half entries
    add     t2, t4, t1                  # t2 = ori_move_x[0]'s memory + oi[from]
    lhu     t5,  0(t2)                  # t5 = ori_move[face_of[m]][oi[from]]

    # pi[g + 1] = cp; oi[g + 1] = co;
    #
    # g + 1 + max(hp, ho, hc) > bound is hp > r || ho > r || hc > r with
    # r = bound - g - 1, so each table can prune on its own and the
    # later loads are skipped whenever an earlier one prunes:
    #
    # if (perm_dist[cp] > r) continue;
    # if (ori_dist[co] > r) continue;
    # cc = ci[g], turned turns_of[m] times;     /* see below */
    # if (c3_dist[cc] > r) continue;
    # ci[g + 1] = cc;
    # if (cp == 0 && co == 0) goto found;       /* tested after the push */
    #
    # The goal test can come last: the solved state has hp = ho = hc = 0
    # and r >= 0, so it is never pruned. Last, it runs only for children
    # that pass all three tables. pi and oi alone fix the cube, so cc
    # needs no test.
    #
    # The two stores must run for every child, pruned or not: the next
    # sibling reads them back as pi/oi[from] with from = g + 1. So they
    # can sit between the lbu and the bltu that uses t4: on a pipelined
    # model that slot would otherwise be a load-use stall.
    add     t2, t6, s8                  # perm_dist[cp]'s memory
    sh      t6,  2(s3)                  # pi[g + 1] = cp (Q + 2)
    lbu     t4,  0(t2)                  # t4 = hp = perm_dist[cp]
    sh      t5, 26(s3)                  # oi[g + 1] = co (Q + 26)
    bltu    s10, t4, search_top         # r < hp: prune

    # add t0 is the c3 setup, done early to fill the load-use slot. It is
    # wasted when ori prunes, but that happens less often than the stall.
    add     t2, t5, s9                  # ori_dist[co]'s memory
    lbu     t4,  0(t2)                  # t4 = ho = ori_dist[co]
    add     t0, a0, s11                 # t0 = c3_move_r + face * 16384
    bltu    s10, t4, search_top         # r < ho: prune

    # ci is not chained through siblings: a pruned sibling never computes
    # its cc, so ci[g + 1] may be stale. Only the children that survive
    # perm and ori (about 29%) turn the parent's ci[g] turns_of[m] times
    # and write ci[g + 1]; it is read only by children of a pushed node.
    #
    # cc = ci[g];
    # for (t = turns_of[m]; t != 0; --t)
    # cc = c3_move[face_of[m]][cc];
    lhu     t3, 48(s3)                  # t3 = cc = ci[g] = *(Q + 48)
    add     t2, s5, a1                  # t2 = face_of[m]'s memory
    lbu     a2,  9(t2)                  # a2 = t = turns_of[m]

loop_c3:
    slli    t4, t3, 1                   # t4 = cc << 1, .half entries
    add     t2, t4, t0                  # t2 = c3_move[face_of[m]][cc]'s memory
    lhu     t3,  0(t2)                  # t3 = cc = c3_move[face_of[m]][cc]

    addi    a2, a2, -1                  # --t
    bne     a2, x0, loop_c3             # one more quarter turn

    add     t2, t3, a4                  # c3_dist[cc]'s memory
    lbu     t4,  0(t2)                  # t4 = hc = c3_dist[cc]
    sh      t3, 50(s3)                  # ci[g + 1] = cc (Q + 50)
    bltu    s10, t4, search_top         # r < hc: prune

    # Push first, then test for the goal with the branch that loops
    # back, so one taken branch does both jobs and found falls through:
    #
    # path[g] = m;
    # pface[g + 1] = face_of[m];
    # ++g;
    # if (cp != 0 || co != 0) goto child;   /* with m = 0, pf = face */
    # found:                                /* length g */
    #
    # The child starts at m = 0 with pf = face_of[m], both already in
    # registers, so search_top's two loads and MOVES test are skipped,
    # and child stores next[g] = 1 itself, so next[g] = 0 is not needed.
    # pface[g] must still be stored: search_top reloads it after every
    # prune and pop. a1 and t5 are overwritten only after their old
    # values (m, co) are last read.
    sb      a1,  0(s4)                  # path[g] = m
    li      a1, 0                       # a1 = m = 0 for the child
    sb      a5, 24(s4)                  # pface[g + 1] = face_of[m] (P + 24)

    addi    s2, s2, 1                   # ++g
    addi    s4, s4, 1                   # P = &path[g + 1]
    addi    s3, s3, 2                   # Q = &pi[g + 1]
    addi    s10, s10, -1                # s10 = bound - 1 - (g + 1) = h

    or      t2, t5, t6                  # t2 = co | cp
    mv      t5, a5                      # t5 = pface[g] = face_of[m]
    bne     t2, x0, child               # not solved: search the child's moves

    # Solved: the path is path[0..g-1], length g.
found:
.if 0                                  # HW1 EXPECT gate (needs cpp + EXPECT)
    # if (EXPECT != g) goto len_failed;
    li      t0, EXPECT                  # t0 = EXPECT
    addi    t1, s2, 0                   # t1 = len = g
    bne     t0, t1, len_failed          # EXPECT != len
.endif

    # 6. Print the path as move names separated by spaces, then a newline.
    #
    # for (i = 0; i < len; ++i)            /* len = g */
    # printf("%s%s", i ? " " : "", move_names[path[i]]);
    # putchar('\n');
    addi    t0, x0, 0                   # t0 = i = 0
    addi    t1, s2, 0                   # t1 = len = g

    la      t3, move_names              # move_names[0]'s memory

    sub     s4, s4, s2                  # s4 = &path[g] - g = &path[0]

loop_print:


    add     t2, s4, t0                  # t2 = path[i]'s memory
    lbu     t4,  0(t2)                  # t4 = path[i]
    slli    t4, t4, 1                   # t4 = t4*2

    add     t6, t3, t4                  # t6 = move_names[path[i]]'s memory
    lbu     t5,  0(t6)                  # t5 = first char of move_names[path[i]]

    beq     t0, x0, print_equal

    li      a0, 32
    li      a7, 11
    ecall

print_equal:
    mv      a0, t5
    li      a7, 11
    ecall

    addi    t6, t6, 1                   # second char's memory
    lbu     t5,  0(t6)                  # t5 = second char, 0 if none

    beq     t5, x0, print_equal2

    mv      a0, t5
    li      a7, 11
    ecall

print_equal2:

    addi    t0, t0, 1

    bne     t0, t1, loop_print

    li      a0, 10
    li      a7, 11
    ecall

    # 7. Gate T5: replay the path on the independent cube model (source,
    # twist) and check that it reaches solved. On failure print a
    # message and exit with code 1.
    # ida.c: replay_solves
    #
    # for (k = 0; k < len; ++k)
    # for (t = 0; t < turns_of[path[k]]; ++t) {
    # f = face_of[path[k]];
    # for (j = 0; j < CUBIES; ++j) {
    # rp[j] = p[source[f][j]];
    # ro[j] = (o[source[f][j]] + twist[f][j]) % 3;
    # }
    # p = rp; o = ro;
    # }

    addi    s0, x0, 0                   # s0 = i = 0
    addi    s1, s2, 0                   # s1 = len = g

    la      a3, turns_of                # turns_of[0]'s memory
    la      s8, face_of                 # face_of[0]'s memory
    la      a5, source                  # source[0]'s memory
    la      a6, twist                   # twist[0]'s memory
    la      a1, rp                      # rp[0]'s memory
    la      a2, ro                      # ro[0]'s memory
    la      s10, p                      # p[0]'s memory
    la      s11, o                      # o[0]'s memory

    addi    s9, x0, 3                   # s9 = 3

.if 0                                  # HW1 RENDER
    jal     ra, render                  # show the scrambled state
.endif

test_loop:
    add     t2, s4, s0                  # t2 = path[i]'s memory
    lbu     t3,  0(t2)                  # t3 = m = path[i]

    add     t4, s8, t3                  # t4 = face_of[m]'s memory
    add     t5, a3, t3                  # t5 = turns_of[m]'s memory

    lbu     s3,  0(t4)                  # s3 = f = face_of[m]
    lbu     s7,  0(t5)                  # s7 = t = turns_of[m]

turn_loop:

    addi    t2, x0, 0                   # t2 = j = 0
    addi    t3, x0, 7                   # t3 = 7

test_loop_inner:
    # source 1 line is 8 byte, source[f][j] == source's memory + (f << 3) + j
    slli    a4, s3, 3                   # a4 = f << 3
    add     t6, t2, a4                  # t6 = (f << 3) + j
    add     t0, a5, t6                  # t0 = source[f][j]'s memory
    lbu     t1,  0(t0)                  # t1 = k = source[f][j]

    add     t0, s10, t1                 # t0 = p[k]'s memory
    lbu     t5,  0(t0)                  # t5 = p[k]

    add     t4, a1, t2                  # t4 = rp[j]'s memory
    sb      t5,  0(t4)                  # store p[k] to rp[j]

    # t0, t4, t5 can be used
    add     t4, s11, t1                 # o[k]'s memory
    lbu     t5,  0(t4)                  # t5 = o[k]

    add     t0, a6, t6                  # t0 = twist[f][j]'s memory
    lbu     t1,  0(t0)                  # t1 = twist[f][j]

    add     t0, t5, t1                  # t0 = o[k] + twist[f][j] = sum

    # sum <= 4, so sum % 3 is one compare and one subtract
    bltu    t0, s9, test_smaller_disc   # if sum < 3, jump to test_smaller_disc

    addi    t0, t0, -3                  # t0 = sum - 3

test_smaller_disc:
    add     t5, a2, t2                  # t5 = ro[j]'s memory
    sb      t0,  0(t5)                  # store sum to ro[j]

    addi    t2, t2, 1
    bne     t2, t3, test_loop_inner

    # p = rp; o = ro;
    addi    t2, x0, 0                   # t2 = j = 0

test_loop_inner2:
    add     t0, a1, t2                  # t0 = rp[j]'s memory
    lbu     t1,  0(t0)                  # t1 = rp[j]

    add     t0, s10, t2                 # t0 = p[j]'s memory
    sb      t1,  0(t0)                  # store rp[j] to p[j]

    add     t0, a2, t2                  # t0 = ro[j]'s memory
    lbu     t1,  0(t0)                  # t1 = ro[j]

    add     t0, s11, t2                 # t0 = o[j]'s memory
    sb      t1,  0(t0)                  # store ro[j] to o[j]

    addi    t2, t2, 1
    bne     t2, t3, test_loop_inner2

    addi    s7, s7, -1
    bne     s7, x0, turn_loop

.if 0                                  # HW1 RENDER
    jal     ra, render                  # redraw after move path[i]
.endif

    addi    s0, s0, 1
    bne     s0, s1, test_loop

    # ------------------------------------------------------
    # for (i = 0; i < CUBIES; ++i)
    # if (p[i] != i || o[i] != 0) goto t5_failed;

    addi    s0, x0, 0                   # s0 = i = 0
    addi    s1, s0, 7                   # s1 = 7

test_loop2:
    # p[i] == i && o[i] == 0, pass
    add     t0, s0, s10                 # t0 = p[i]'s memory
    lbu     t1,  0(t0)                  # t1 = p[i]

    bne     t1, s0, t5_failed

    add     t0, s0, s11                 # t0 = o[i]'s memory
    lbu     t1,  0(t0)                  # t1 = o[i]

    bne     t1, x0, t5_failed

    addi    s0, s0, 1
    bne     s0, s1, test_loop2

    # 8. Exit with code 0.
    li      a7, 10
    ecall

    # No path within bound: ++bound and search again (step 4). Placed
    # after the exit so that nothing falls into it; pop's beq reaches
    # anywhere in this .text (B-type: +-4 KiB). A valid state is always
    # solved by bound 11, so falling through means a bug and lands on
    # t5_failed.
bound_failed:

    addi    s0, s0, 1                   # ++bound
    addi    t0, x0, 11                  # t0 = MAX_DEPTH = 11
    bleu    s0, t0, loop_solve          # bound <= 11: search again

    # puts("T5 failed"); exit(1);
t5_failed:

    la      t0, message                 # t0 = message's memory

    li      a7, 4
    mv      a0, t0
    ecall

    li      a7, 11
    li      a0, 10
    ecall

    li      a7, 93
    li      a0, 1
    ecall

.if 0                                  # HW1 EXPECT gate
    # puts("wrong length"); exit(2);
len_failed:
    la      t0, message2                # t0 = message2's memory

    li      a7, 4
    mv      a0, t0
    ecall

    li      a7, 11
    li      a0, 10
    ecall

    li      a7, 93
    li      a0, 2
    ecall
.endif

.if 0                                  # HW1 RENDER (needs LED_MATRIX_0_BASE)
    # ------------------------------------------------------
    # 8. LED matrix renderer: unfolded net of the cube in p[], o[], redrawn
    # before the replay and after every move of the path.
    #
    # for (i = 0; i < 24; ++i) {
    # pos = fl_pos[i], slot = fl_slot[i];
    # cubie = p[pos], tw = o[pos];
    # k = (slot + tw) % 3;
    # draw_select(color6[corner_face[cubie][k]],
    # LED_MATRIX_0_BASE + face_off[i]);
    # }
    #
    # Called from T5 with live values in s0-s11 and a1-a6, so it saves and
    # restores every register it writes except t0-t6. ra is saved too: the
    # jal to draw_select overwrites it.
render:
    addi    sp, sp, -64
    sw      ra,  0(sp)
    sw      s1,  4(sp)
    sw      s2,  8(sp)
    sw      s4, 12(sp)
    sw      s5, 16(sp)
    sw      s6, 20(sp)
    sw      s7, 24(sp)
    sw      s8, 28(sp)
    sw      a0, 32(sp)
    sw      a1, 36(sp)
    sw      a2, 40(sp)
    sw      a3, 44(sp)
    sw      a4, 48(sp)
    sw      a5, 52(sp)
    sw      a6, 56(sp)

    li      s1, LED_MATRIX_0_BASE       # s1 = LED (0, 0)'s memory
    la      s2, face_off                # s2 = &face_off[i], .half entries
    la      s4, fl_pos                  # s4 = &fl_pos[i]; fl_slot[i] = 24(s4)
    la      s5, p                       # s5 = p[0]'s memory; o[pos] = 8(p + pos)
    la      s6, corner_face             # s6 = corner_face[0][0]'s memory
    la      s7, color6                  # s7 = color6[0]'s memory
    addi    s8, x0, 3                   # s8 = 3

    addi    a0, x0, 0                   # a0 = i = 0
    addi    a1, x0, 24                  # a1 = 24 facelets

loop_faces:
    lhu     t1,  0(s2)                  # t1 = face_off[i]
    add     t1, t1, s1                  # t1 = facelet i's top-left LED's memory

    lbu     a2,  0(s4)                  # a2 = fl_pos[i] = pos
    lbu     a3, 24(s4)                  # a3 = fl_slot[i] = slot

    add     a4, s5, a2                  # a4 = p[pos]'s memory
    lbu     a5,  0(a4)                  # a5 = p[pos] = cubie
    lbu     a6,  8(a4)                  # a6 = o[pos] = p[pos + 8]

    add     a3, a3, a6                  # a3 = slot + tw
    bltu    a3, s8, smaller_disc        # if slot + tw < 3, jump to smaller_disc
    addi    a3, a3, -3                  # a3 = k = (slot + tw) % 3

smaller_disc:
    mv      a2, a5                      # a2 = cubie (pos no longer needed)
    slli    a5, a5, 1                   # a5 = cubie * 2
    add     a5, a5, a2                  # a5 = cubie * 3

    add     a5, a5, a3                  # a5 = cubie * 3 + k

    add     a3, s6, a5                  # a3 = corner_face[cubie*3 + k]'s memory
    lbu     a4,  0(a3)                  # a4 = corner_face[cubie*3 + k] = face

    slli    a4, a4, 2                   # a4 = face * 4, .word entries
    add     a5, s7, a4                  # a5 = color6[face]'s memory
    lw      t0,  0(a5)                  # t0 = color6[face]

    jal     ra, draw_select             # draw facelet i

    addi    a0, a0, 1                   # ++i
    addi    s2, s2, 2                   # next .half
    addi    s4, s4, 1                   # next fl_pos
    bne     a0, a1, loop_faces

    lw      ra,  0(sp)
    lw      s1,  4(sp)
    lw      s2,  8(sp)
    lw      s4, 12(sp)
    lw      s5, 16(sp)
    lw      s6, 20(sp)
    lw      s7, 24(sp)
    lw      s8, 28(sp)
    lw      a0, 32(sp)
    lw      a1, 36(sp)
    lw      a2, 40(sp)
    lw      a3, 44(sp)
    lw      a4, 48(sp)
    lw      a5, 52(sp)
    lw      a6, 56(sp)
    addi    sp, sp, 64
    jalr    x0, ra, 0                   # return

    # ------------------------------------------------------
    # draw_select: fill one facelet, 4 LEDs wide and 3 rows tall.
    # in:  t0 = color, t1 = top-left LED's memory
    # uses t2, t5, t6; leaves t0 and t1 unchanged
    #
    # for (dy = 0; dy < 3; ++dy) {
    # p[0] = p[1] = p[2] = p[3] = color;
    # p += 35;                      # next row: 35 LEDs = 140 bytes
    # }
draw_select:
    addi    t5, x0, 0                   # t5 = dy = 0
    addi    t6, x0, 3                   # t6 = 3 rows
    mv      t2, t1                      # t2 = p, so t1 survives the call

draw_label:
    sw      t0,  0(t2)                  # 4 LEDs of this row
    sw      t0,  4(t2)
    sw      t0,  8(t2)
    sw      t0, 12(t2)

    addi    t2, t2, 140                 # next row

    addi    t5, t5, 1
    bne     t5, t6, draw_label

    jalr    x0, ra, 0                   # return
.endif

    # epilogue (KEEP): restore callee-saved; all HW2 exits should land here
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
