# Macintosh Portable Power Manager (PMGR) firmware

A corrected and fully commented disassembly of the Macintosh Portable Power Manager ROM (`pmuv1.bin`, version $02,$B5, "Written by Michael Hanlon", 1987–1989). The firmware runs on a Mitsubishi M50753 and handles the ADB, power switching, battery charging, the real-time clock, parameter RAM, LCD contrast, and sleep/wake.

The listing [`pmuv1.bin.asm`](pmuv1.bin.asm) re-assembles byte-identical to the ROM.

## CPU

**Mitsubishi M50753**, a single-chip MCU in the MELPS 740 family. The 740 is a 6502 derivative with extra bit instructions and a few other additions.

The evidence from the ROM image and the code matches the M50753 datasheet in the 1989 Mitsubishi *Single-Chip 8-Bit Microcomputers* data book, p. 2-199ff (the data book itself is not included; the relevant pages are extracted in `docs/M50753_datasheet_extract.txt`):

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

These errors were in the original IDA export and are fixed in `pmuv1.bin.asm`, which re-assembles byte-identical to `pmuv1.bin`.

1. **Wrong addressing mode syntax (5 places):**
   - `lda (PARAMETER+3), Y` at `$EEC5`
   - `lda (PARAMETER+2), Y` at `$F221`
   - `sta/lda (PARAMETER+1), Y` at `$F28A` and `$F2D2`
   - `lda (command_table+1), X`

   The opcodes are **absolute indexed** (`$B9`/`$99`/`$BD`). In IAR syntax, `(zp),Y` means indirect indexed (`$B1`/`$91`). This changes both the meaning and the instruction size.
2. **`#!X` used as a bitwise complement:** in IAR, `!` is a logical NOT and `~` is the bitwise one. `#!M_P06_neg5_EN|M_P07_SYS_PWR` also had the wrong precedence: it gives `$BF`, but the ROM contains `$3F`.
3. **IRQ_CTRL (`$FE`) bits 2–5:** Timer 1 and Timer 2 were swapped. Bits 4/5 belong to Timer 1 *or A-D*. That is why the A-D wait loops poll bit 5, which IDA had named `TIM2_REQ` (now `IRQ_T1_AD_REQ`).
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

All auto-generated `loc_xxxx` labels have descriptive names. The main renames:

| Old (IDA) | New |
|---|---|
| `PowerManagerCommands_xx_name` | `PM_name` (e.g. `PM_readINT`, `PM_SLEEP_ACK`) |
| `CMD_78_STATE`, `CMD_78_BITS_*` | `INT_STATE`, `INT_ADB` / `INT_BATT` / `INT_BATT2` / `INT_RESET` |
| `FLAGS_Bits_1/2/4/5/6/7` | `FLAG_PMINT_SENT` / `FLAG_AKD_IDLE_SEEN` / `FLAG_ALARM_SET` / `FLAG_ALARM_HIT` / `FLAG_SLEEPING` / `FLAG_RING_WAKEUP` |
| `ADB_STATUS_BITS_*`, `BAT_CHG_BITS_*` | `ADBF_*`, `BATF_*` |
| `IRQ_CTRL_FLAGS_*`, `PWM_CTRL_FLAGS_COUNT` | `IRQ_INT1_REQ`, `IRQ_T1_AD_REQ`, ..., `PWM_EN` |
| `VIA_TEST_PIN`, `NOT_CHARGING` | `ENTER_SLEEP`, `BAT_CHARGER` (the branch is taken when P13 is low) |
| `IRQ_60Hz`, `CHECK_BAT_STATUS`, `BATTERY_READ_SUM` | `TICK`, `CHECK_BATTERY`, `BATTERY_SAMPLE` |
| `VECTOR_INT2_RESET_CONTINUE` | `WARM_RESET` / `INIT` |
| `PRAM_BUFFER*`, `PRAM_CHKSUM` | `XPRAM*`, `XPRAM_CHKSUM`; `XPRAM_BAT_LOW` ($42, default 78), `XPRAM_BAT_DEAD` ($43, default 62) |
| `BUFFER`, `BUFFER_CNT` | `ADB_BUFFER`, `ADB_COUNT` |

The battery and ADB bit names are my reading of the code, not Apple's names.

## Bugs or oddities in the original firmware (not disassembly errors)

- `CHECK_BATTERY` compares `XPRAM_44` with IN0 and then branches to the next instruction, so the result is never used (dead code).
- `TIMERX_PRES` is written twice; the second write was probably meant for `TIMERX`. Timer X is unused anyway.
- `$EF` soft reset jumps into the init code from inside a subroutine. The stack pointer isn't reset, and A/Y are left over from the command.
- Incoming parameter counts (`READ_PARAMETER`, `xPramWrite`) are never checked against the 8-byte buffer or the 128-byte XPRAM.
- `readINT` bit 2 is cleared by batteryRead but never set anywhere.
- `DELAY_SMALL` at `$FF00` is never called.
- In `COMMAND_8x_TIMER`, the `bbs 3, COMMAND` test right after `cmp #$80` can never branch.

## Files

| File | Content |
|---|---|
| [`pmuv1.bin`](pmuv1.bin) | The 6 KB PMGR ROM image |
| [`pmuv1.bin.asm`](pmuv1.bin.asm) | Corrected and commented listing (IAR 740 syntax) |
| [`pmuv1_independent_disassembly.txt`](pmuv1_independent_disassembly.txt) | Plain disassembly with addresses and bytes, made by `tools/dis740.py` |
| [`tools/m740.py`](tools/m740.py) | 740 opcode table and decoder |
| [`tools/dis740.py`](tools/dis740.py) | Independent recursive disassembler |
| [`tools/reasm740.py`](tools/reasm740.py) | Re-assembles the listing and compares it with the ROM, including that the unused gaps (`BLKB`) are zero |
| [`docs/`](docs) | CPU (M50753 datasheet extract, 740 Software Manual), ADB (Microchip AN591) and Rockwell R6522 VIA documentation |

To check that the listing still matches the ROM:

```bash
python3 tools/reasm740.py pmuv1.bin.asm pmuv1.bin
```

To regenerate the plain disassembly:

```bash
python3 tools/dis740.py pmuv1.bin pmuv1_independent_disassembly.txt
```

The ROM image and the vendor documents are copyright of their respective owners.
