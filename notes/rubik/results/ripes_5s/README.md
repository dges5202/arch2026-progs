# Ripes RV32_5S — rubik d11 samples

- Processor: `RV32_5S` (5-stage + forwarding)
- Binary: freestanding ELF, `main` calls only `rubik_solve_asm` then returns
- States: see `../d11_ripes_sample_states.txt` (emu min / max)
- Versions: v1, v2b, v3, v4b, v5a, v5b, v5c1–c5, v5c6–c14, v5c15–c17, **v5c18** (σ/σ² CSE keep `&sig[i]`); also `cO3flto_*` GCC samples

See `summary.csv` and per-run `*.json`.
