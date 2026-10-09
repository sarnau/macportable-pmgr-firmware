# Macintosh Portable Power Manager (PMGR) firmware

Corrected and documented disassembly of the Macintosh Portable Power Manager ROM (`pmuv1.bin`, version $02,$B5).
The firmware runs on a Mitsubishi M50753 (740 family) and handles ADB, power switching, battery charging, the real-time clock, parameter RAM, LCD contrast and sleep/wake.

- [pmuv1_analysis.md](pmuv1_analysis.md) — analysis, command table, list of corrections
- [pmuv1.bin.asm](pmuv1.bin.asm) — corrected IAR 740 listing (re-assembles byte-identical to `pmuv1.bin`)
- [tools/](tools) — 740 disassembler and re-assembly checker

```bash
python3 tools/reasm740.py pmuv1.bin.asm pmuv1.bin
```

The ROM image and the vendor documents are copyright of their respective owners.
