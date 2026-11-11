# Ripes RV32_5S — rubik d11 samples

- Processor: `RV32_5S` (5-stage + forwarding)
- Binary: freestanding ELF, `main` calls only `rubik_solve_asm` then returns
- States: see `../d11_ripes_sample_states.txt` (emu min / max)
- Versions: v1, v2b, v3, v4b, v5a, v5b, v5c1, v5c2 (r0 fall-through), v5c3 (nibble), **v5c4** (apply_1q LU)

See `summary.csv` and per-run `*.json`.
