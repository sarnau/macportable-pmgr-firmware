# Macintosh Portable Power Manager (PMGR) firmware – `pmuv1.bin`

## CPU

**Mitsubishi M50753**, a single-chip MCU in the MELPS 740 family. The 740 is a 6502 derivative with extra bit instructions and a few other additions.

The evidence from the ROM image and the code matches the M50753 datasheet in `1989_Mitsubishi_Single-Chip_8-Bit_Microcomputers.pdf`, p. 2-199ff (extract: `docs/M50753_datasheet_extract.txt`):

| Item | Datasheet | Firmware |
|---|---|---|
| ROM | 6144 bytes, `$E800-$FFFF` | Image is `$1800` bytes, reset vector `$E800`, special page routines at `$FF00` |
| RAM | 192 bytes, `$0000-$00BF` | Stack top `$BF`; the RAM test runs from `$BF` down to `$00` |
| A-D | `$EE` IN, `$EF` A-D result, `$F2` start, `$F3` control | Battery voltage is read on IN1 and IN0 |
| PWM | `$F5` bit 0, timer 1 = high time, timer 2 = low time | LCD contrast |
| Vectors | `$FFF4` INT2, `$FFF6` T2/SIO, `$FFF8` T1/A-D, `$FFFA` TX, `$FFFC` INT1, `$FFFE` RESET | Same order in the image |

The keyboard controller is a different chip, an M50740 (the firmware resets it through P14). The M50740 has no A-D and no PWM, so it can't be the chip running this ROM.

**Clock:** f(XIN) = 4 MHz, so φ = 1 MHz and one cycle takes 1 µs. Counting the cycles in the ADB loops gives the timings the ADB spec requires (see `docs/Microchip AN591 Apple Desktop Bus.pdf`):

- 800 µs attention
- about 70 µs sync
- 65 µs low for a '0' bit, 35 µs low for a '1' bit
- 65 µs stop bit
- about 160 µs Tlt
- about 4.6 ms reset pulse

## What the firmware does

The PMGR does much more than run the ADB. It also handles:

- power plane switching
- battery monitoring and high-rate charge control
- the real-time clock (seconds since 1904) and the wakeup alarm
- 128 bytes of XPRAM with a checksum
- the LCD contrast PWM
- modem and sound power
- sleep and wake
- a self test

It talks to the 68000 through the VIA:

- P2 is the data bus.
- P37 is PMREQ (input) and P36 is PMACK (output).
- P35 drives /PMINT to VIA CB1.
- P34 sends a 1 Hz pulse to VIA CA1.

| Cmd | Function |
|---|---|
| `$10/$18` | powerCntl / powerRead |
| `$20/$21/$28` | pMgrADB / ADB auto-poll off / readADB |
| `$30/$31/$32` | timeWrite / pramWrite (20 bytes) / xPramWrite |
| `$38/$39/$3A` | timeRead / pramRead / xPramRead |
| `$40/$48` | contrast set / read |
| `$50/$58` | modemSet / modemRead |
| `$68/$69` | batteryRead / batteryNow: flags, voltage, IN0 |
| `$78` | readINT (bit0 ADB, bit1 battery, bit3 cold reset) |
| `$7F` | sleepReq, needs the signature `'MATT'`; reply `$70` ok / `$AA` bad |
| `$80/$82/$88` | timerSet / timerDisable / timerRead |
| `$90/$98` | soundSet / soundRead |
| `$E0/$E8/$EA/$EC/$EF` | write RAM / read RAM / version (`$02,$B5`) / self test / soft reset |

**Power-up behaviour:** after a cold reset the PMGR goes straight into the sleep loop, as long as P32 is high, which is the normal case. The Mac only powers on when a key is pressed. A low battery voltage forces the same sleep path.

**ADB receive:** the receive routine moves the stack pointer to `$10` and uses PHA to store each received byte into the 8-byte buffer at `$08-$0F`.

## Corrections applied to the IDA output

The listing re-assembles byte-identical to `pmuv1.bin` (checked with `tools/reasm740.py`). Every correction is marked `[FIX]` in `pmuv1.bin.asm`.

1. **Wrong addressing mode syntax (5 places):**
   - `lda (PARAMETER+3), Y` at `$EEC5`
   - `lda (PARAMETER+2), Y` at `$F221`
   - `sta/lda (PARAMETER+1), Y` at `$F28A` and `$F2D2`
   - `lda (command_table+1), X`

   The opcodes are **absolute indexed** (`$B9`/`$99`/`$BD`). In IAR syntax, `(zp),Y` means indirect indexed (`$B1`/`$91`). This changes both the meaning and the instruction size.
2. **`#!X` used as a bitwise complement:** in IAR, `!` is a logical NOT and `~` is the bitwise one. `#!M_P06_neg5_EN|M_P07_SYS_PWR` also had the wrong precedence: it gives `$BF`, but the ROM contains `$3F`.
3. **IRQ_CTRL (`$FE`) bits 2–5:** Timer 1 and Timer 2 were swapped. Bits 4/5 belong to Timer 1 *or A-D*. That is why the A-D wait loops poll bit 5, which IDA had named `TIM2_REQ`.
4. **PWM_CTRL (`$F5`):** the bit descriptions came from a different 740 part. On the M50753, only bit 0 (PWM output enable) exists.
5. **`clb M_P30_RESET, PORT_P3`** in the INT2 handler: a mask constant was used as a bit number. The opcode `$3F` clears **bit 1 = P31 SYS_RST**, which holds the 68000 in reset while the reset/interrupt switch is pressed.
6. **Port P4 initial value** was written with P3 mask names. `$0E` is P41, P42 and P43.
7. **`ROM_CHECKSUM WORD $4476`:** this is really a big-endian `$7644`, compared as X=`$76`, Y=`$44`. I recomputed it with the ROM's algorithm and it is valid.
8. **Wrong comments:**
   - `$38`/`$39`/`$3A` were shifted by one.
   - The INT2 request bit was labelled INT1.
   - Two loops carried an auto-propagated "Test if 60Hz IRQ triggered" that doesn't apply (the AKD wait and the reset switch wait).
   - "Erase 0x2F…0xAF" should be `$2F…$AE`.
   - The ADB reset was labelled ">824µs"; it is about 4.6 ms.
9. **Bogus symbol `byte_E7`:** IDA took the low byte of `CHECK_RAM_DATA_TAB` (`$F2E7`) as a zero-page reference. `$E7` is not an SFR.
10. **Header** said "Range: E000h-F800h". The ROM is at `$E800-$FFFF`.

## Symbol names

`VIA_TEST_PIN`→`ENTER_SLEEP`, `NOT_CHARGING`→`CHARGER_CONNECTED` (the branch is taken when P13 /CHRG_ON is low), `FLAGS_Bits_1/6/7`→`PMINT_SENT/SLEEPING/RING_WAKEUP`, `FLAGS_Bits_AKD`→`AKD_IDLE_SEEN`. I also gave names to the battery-flag bits, the ADB status bits, the battery state variables and the XPRAM battery thresholds (`$42` low = 78, `$43` dead = 62). The battery and ADB bit names are my reading of the code, not Apple's names.

## Bugs or oddities in the original firmware (not disassembly errors)

- `CHECK_BAT_STATUS` compares `PRAM_BAT_44` with IN0 and then branches to the next instruction, so the result is never used (dead code).
- `TIMERX_PRES` is written twice; the second write was probably meant for `TIMERX`. Timer X is unused anyway.
- `$EF` soft reset jumps into the init code from inside a subroutine. The stack pointer isn't reset, and A/Y are left over from the command.
- Incoming parameter counts (`READ_PARAMETER`, `xPramWrite`) are never checked against the 8-byte buffer or the 128-byte XPRAM.
- `readINT` bit 2 is cleared by batteryRead but never set anywhere.
- `DELAY_SMALL` at `$FF00` is never called.
- In `COMMAND_8x_WAKEUP`, the `bbs 3, COMMAND` test right after `cmp #$80` can never branch.

## Files in this folder

| File | Content |
|---|---|
| `pmuv1.bin.asm` | Corrected and documented listing |
| `tools/m740.py` | 740 opcode table and decoder |
| `tools/dis740.py` | Independent recursive disassembler → `pmuv1_independent_disassembly.txt` |
| `tools/reasm740.py` | Re-assembles the listing and compares it with the ROM: `python3 tools/reasm740.py pmuv1.bin.asm pmuv1.bin` |
| `docs/` | CPU documentation (M50753 datasheet extract, 740 Software Manual PDF + text) and ADB documentation (Microchip AN591 PDF + text) |
