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

**Sleep:** the sleep loop calls the tick routine without waiting for the 60 Hz flag. The STOP_CLK pulse (P12) on every pass must therefore stop the PMGR's own clock until the next tick, so the PMGR sleeps as well.

**Power-up behaviour:** after a cold reset the PMGR goes straight into the sleep loop, as long as P32 is high, which is the normal case. The Mac only powers on when a key is pressed. A low battery voltage forces the same sleep path.

**ADB receive:** the receive routine moves the stack pointer to `$10` and uses PHA to store each received byte into the 8-byte buffer at `$08-$0F`.

## Checked against the host side

The Portable's main ROM (`93ca3846.rom`, not included) contains the other end of the protocol: the `_PMgrOp` trap (`$A085`), the `/PMINT` handler and the ADB, battery, sound and sleep code. It confirms:

- **Wiring:** VIA at `$F70000`; PMREQ is VIA PB0 (host output), PMACK is VIA PB1 (host input), the data bus is VIA port A.
- **Busy signal:** before sending a command the host waits until port A reads `$FF`. The `$07` the PMGR drives onto the bus while busy therefore means "busy".
- **Commands:** about 30 call sites use exactly the formats documented in the listing (powerCntl bit 7 = on/off, PRAM/XPRAM/time formats, pMgrADB = command, flags, count, data; read commands have bit 3 set).
- **readINT:** the handler dispatches bit 0 to ADB, bit 1 to battery and bit 2 to a second battery handler. This PMGR never sets bit 2.
- **ADB flags:** bit 0 is the OS's "bus initialisation in progress" flag, bit 2 auto-poll (the OS sends flags = 4 when it starts polling a device), bit 3 SRQ (the OS then polls the other devices), bit 4 no data (the OS discards the data).
- **Battery:** the OS uses only flag bit 0 (charger connected: no idle power-down), bit 5 (charger changed) and the voltage byte. It averages 8 samples and applies its own levels from XPRAM `$72/$73` (default 78/62, the same values the PMGR keeps at `$42/$43`). The third byte (IN0) is never used.
- **Sound:** every 10 s the OS reads soundRead. If sound is on but nothing was played (latch bit clear), it switches sound off; otherwise it clears the latch. So P33 = sound on and the IN2 latch records sound activity.
- **Sleep:** the OS sends sleepReq with `'MATT'`, checks for the `$70` reply and then loops until the PMGR cuts the power. Before that it waits while the modem rings with wake on ring enabled (modemRead bits 2 and 4).

## Hardware notes from macintoshportable.info

- The Power Manager is Apple part **342S0753-A**, an M50753.
- **VIA_TEST (P32)** is the factory test line on pin 7 of the J22 edge connector. Grounding it at boot starts the ROM's Test Manager. The PMGR then keeps the machine powered: no sleep at power-on, no low-battery shutdown, and all power planes forced on except the modem.
- **Battery A/D (IN1):** the hybrid maps the battery voltage onto 0–5 V; about 7.5 V gives 5.0 V (255) and 5.6 V gives about 1.0 V (51). With these example values the default levels are roughly LOW 78 = 5.85 V, VERY_LOW 70 = 5.78 V and DEAD 62 = 5.7 V, and the high-rate charge runs between 90 = 6.0 V and 208 = 7.1 V.
- The ROM's Sad Mac codes `$0014` (communication) and `$0010` (self test) with minor codes `$CD33`–`$CD38` are the host-side handshake timeouts; `$CD38` means the PMGR never signalled "ready" (data bus `$FF`).
- Still unknown: what is connected to the second analog input, IN0.

## Bugs and oddities in the firmware

- `CHECK_BATTERY` compares `XPRAM_44` with IN0 and then branches to the next instruction, so the result is never used (dead code).
- `TIMERX_PRES` is written twice; the second write was probably meant for `TIMERX`. Timer X is unused anyway.
- `$EF` soft reset jumps into the init code from inside a subroutine. The stack pointer isn't reset, and A/Y are left over from the command.
- Incoming parameter counts (`READ_PARAMETER`, `xPramWrite`) are never checked against the 8-byte buffer or the 128-byte XPRAM.
- `readINT` bit 2 is cleared by batteryRead but never set anywhere.
- `DELAY_SMALL` at `$FF00` is never called.
- Removing the charger does not switch the high-rate charge output (P15) off; it stays on until the charger is connected again.
- While the battery is below the low level, the battery interrupt is set again on every tick, so the host gets /PMINT 60 times a second.
- Listen and Flush commands also run through the ADB receive code, which times out and reports `ADBF_NO_DATA|ADBF_ERROR`.
- pMgrADB accepts at most 5 Listen data bytes; more overflow the 8-byte parameter buffer into `PTR` while it is in use.
- Waking up by modem ring also disables the wake-up alarm.
- readPmgrRAM with only the two address bytes sends no reply at all.
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
