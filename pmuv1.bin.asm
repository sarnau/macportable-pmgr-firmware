;==============================================================================
; Macintosh Portable Power Manager (PMGR) firmware
; ROM version $02,$B5 - pmuv1.bin, 6144 bytes
; "Copyright Apple Computer Inc 1987, 1988, 1989 Written by Michael Hanlon"
;
; Assembler: IAR 740 (originally exported by IDA, cleaned up and commented).
; Re-assembles byte-identical to pmuv1.bin, check with:
;     python3 tools/reasm740.py pmuv1.bin.asm pmuv1.bin
; Input SHA256: 0F9911AB33A62A2831D683D9648059BD7AD59C455B59DCD214C610CE16EEBD57
;==============================================================================
;
; CPU: Mitsubishi M50753 (MELPS 740 family: 6502 core plus bit instructions)
;   ROM   $E800-$FFFF  6144 bytes, special page $FF00-$FFFF, vectors $FFF4-$FFFF
;   RAM   $0000-$00BF  192 bytes, stack at the top
;   SFR   $00E0-$00FF  ports P0-P4, input port IN, A-D, PWM, serial I/O, timers
;   Clock f(XIN) = 4 MHz, phi = 1 MHz: one cycle = 1 us. All ADB timing is done
;   with cycle-counted code.
;   740 extras used: SEB/CLB/BBS/BBC (bit ops on A or zero page), LDM #imm,zp,
;   TST zp, JSR (zp), JSR \sp (2-byte call into $FFxx), BRA. The T flag stays 0.
;
; The PMGR switches all power planes, charges the battery, keeps the clock and
; the 128 bytes of parameter RAM (XPRAM) alive, runs the ADB, controls LCD
; contrast, modem and sound power, and puts the Portable to sleep / wakes it up.
;
; Host interface (68000 through the 6522 VIA):
;   P2        8-bit data bus
;   P37 in    PMREQ  host request / acknowledge
;   P36 out   PMACK  PMGR acknowledge / data valid
;   P35 out   /PMINT (VIA CB1) interrupt pulse
;   P34 out   1 Hz   (VIA CA1) one-second pulse
; Every transfer is: command byte, count byte, count data bytes. A reply uses
; the same format. After /PMINT the host sends readINT ($78) and then fetches
; the data with readADB ($28) or batteryRead ($68).
;
; Timing: the only time base is the 60.15 Hz tick on INT1. Its interrupt is
; never enabled, because an interrupt would break the cycle-counted ADB code.
; Instead the request bit is polled with
;     bit IRQ_CTRL / bpl ...     (N = bit 7 = IRQ_INT1_REQ)
; followed by "jsr TICK". The only enabled interrupt is INT2 (reset switch),
; which never returns.

;------------------------------------------------------------------------------
; Host commands. Bits 7-4 index COMMAND_TABLE, bit 3 is usually read (1) /
; write (0).
;------------------------------------------------------------------------------
PM_powerCntl:      EQU $10      ; switch power planes on/off
PM_powerRead:      EQU $18      ; read power plane state
PM_pMgrADB:        EQU $20      ; send an ADB command, set ADB_FLAGS
PM_pMgrADBoff:     EQU $21      ; stop ADB auto-poll
PM_readADB:        EQU $28      ; fetch the ADB result
PM_timeWrite:      EQU $30      ; set the clock (4 bytes)
PM_pramWrite:      EQU $31      ; write the classic 20 bytes of PRAM
PM_xPramWrite:     EQU $32      ; write XPRAM bytes (offset, count, data)
PM_timeRead:       EQU $38      ; read the clock
PM_pramRead:       EQU $39      ; read the classic 20 bytes of PRAM
PM_xPramRead:      EQU $3A      ; read XPRAM bytes (offset, count)
PM_setContrast:    EQU $40      ; set the LCD contrast (0-31)
PM_readContrast:   EQU $48      ; read the LCD contrast
PM_modemSet:       EQU $50      ; modem power, A/B select, wake on ring
PM_modemRead:      EQU $58      ; modem status
PM_batteryRead:    EQU $68      ; battery flags, voltage, IN0 (filtered)
PM_batteryNow:     EQU $69      ; same, with a fresh unfiltered sample
PM_SLEEP_ACK:      EQU $70      ; reply to sleepReq: going to sleep
PM_readINT:        EQU $78      ; read the interrupt cause (INT_STATE)
PM_sleepReq:       EQU $7F      ; sleep, needs the signature 'MATT'
PM_timerSet:       EQU $80      ; set and enable the wakeup timer
PM_timerDisable:   EQU $82      ; disable the wakeup timer
PM_timerRead:      EQU $88      ; read the wakeup timer and enable flag
PM_soundSet:       EQU $90      ; sound power / clear the sound latch
PM_soundRead:      EQU $98      ; sound status
PM_SLEEP_NAK:      EQU $AA      ; reply to sleepReq: wrong signature
PM_writePmgrRAM:   EQU $E0      ; write PMGR memory (addr hi, addr lo, data)
PM_readPmgrRAM:    EQU $E8      ; read PMGR memory (addr hi, addr lo, count)
PM_readPmgrVers:   EQU $EA      ; read the ROM version
PM_PmgrSelfTest:   EQU $EC      ; run the self test
PM_PmgrSoftReset:  EQU $EF      ; re-initialise the ports

;------------------------------------------------------------------------------
; FLAGS ($00)
;------------------------------------------------------------------------------
FLAG_PMINT_SENT:   EQU 1        ; /PMINT was pulsed, cleared by readINT. readADB and
                                ; batteryRead keep their cause if a new pulse was sent.
FLAG_AKD_IDLE_SEEN: EQU 2       ; asleep: all keys were up at least once. Only then
                                ; does a key press wake the machine.
FLAG_ALARM_SET:    EQU 4        ; wakeup timer enabled
FLAG_ALARM_HIT:    EQU 5        ; wakeup time reached (checked only while asleep,
                                ; cleared by the next tick)
FLAG_SLEEPING:     EQU 6        ; system is powered down
FLAG_RING_WAKEUP:  EQU 7        ; wake on modem ring enabled

;------------------------------------------------------------------------------
; INT_STATE ($01): reply to readINT. While bits 0-2 are not all 0, /PMINT is
; pulsed every 1/60 s.
;------------------------------------------------------------------------------
INT_ADB:           EQU 0        ; ADB result available (readADB)
INT_BATT:          EQU 1        ; battery/charger status changed (batteryRead)
INT_BATT2:         EQU 2        ; cleared by batteryRead, never set in this ROM
INT_RESET:         EQU 3        ; PMGR had a cold reset, cleared by readINT
M_INT_ADB:         EQU 1
M_INT_BATT:        EQU 2
M_INT_BATT2:       EQU 4
M_INT_RESET:       EQU 8

;------------------------------------------------------------------------------
; ADB_FLAGS ($06): written by the host with pMgrADB, returned by readADB.
; Bit 0 belongs to the host and is preserved.
;------------------------------------------------------------------------------
ADBF_PENDING:      EQU 1        ; a pMgrADB command waits to be sent
ADBF_AUTOPOLL:     EQU 2        ; repeat the command every tick; an empty answer
                                ; (no data, no SRQ) is not reported to the host
ADBF_SRQ:          EQU 3        ; a device requested service after the command
ADBF_NO_DATA:      EQU 4        ; no valid answer (always after Listen/Flush),
                                ; ADB reset sent, or send failed
ADBF_BUS_ERR:      EQU 5        ; bus did not follow our output while sending
ADBF_ERROR:        EQU 7        ; set with BUS_ERR or a receive timeout

;------------------------------------------------------------------------------
; BAT_FLAGS ($1D): first byte of batteryRead
;------------------------------------------------------------------------------
BATF_CHARGER:      EQU 0        ; charger connected (P13 low)
BATF_HICHARGE_ON:  EQU 1        ; high-rate charge on (copy of P15)
BATF_HICHARGE_OVF: EQU 2        ; high-rate charge timer overflowed (~18 min)
BATF_DEAD:         EQU 3        ; voltage < XPRAM_BAT_DEAD: forced sleep
BATF_LOW:          EQU 4        ; voltage < XPRAM_BAT_LOW: low battery warning
BATF_CHARGER_CHANGED: EQU 5     ; charger plugged in or removed
BATF_VERY_LOW:     EQU 6        ; voltage < (LOW+DEAD)/2: do not wake up

; BAT_HICHG_STATE ($21): high-rate charge state machine (charger connected).
; A voltage below 90 in any state restarts at HICHG_START.
HICHG_START:       EQU 0        ; HICHG on, timer = 1
HICHG_COUNT_UP:    EQU 1        ; count the timer up until the voltage reaches 208
HICHG_COUNT_DOWN:  EQU 2        ; count it down again: charge as long again
HICHG_DONE:        EQU 3        ; HICHG off (trickle charge)

;------------------------------------------------------------------------------
; SFR bits
;------------------------------------------------------------------------------
; IRQ_CTRL ($FE)
IRQ_INT2_EN:       EQU 0        ; INT2 (reset/interrupt switch)
IRQ_INT2_REQ:      EQU 1
IRQ_T2_SIO_EN:     EQU 2        ; timer 2 or serial I/O
IRQ_T2_SIO_REQ:    EQU 3
IRQ_T1_AD_EN:      EQU 4        ; timer 1 or A-D (AD_CTRL bit 3 selects the A-D)
IRQ_T1_AD_REQ:     EQU 5        ; polled for "A-D conversion done"
IRQ_INT1_EN:       EQU 6        ; INT1 (60 Hz tick)
IRQ_INT1_REQ:      EQU 7        ; polled with BIT/BPL

; PWM_CTRL ($F5): bit 0 is the only bit. The PWM output (high time TIMER1,
; low time TIMER2) generates the LCD contrast voltage.
PWM_EN:            EQU 0

; IN ($EE): analog / digital input port
IN2_SOUND_LATCH:   EQU 2        ; sound latch (powerRead reports it as is,
                                ; soundRead inverted)
IN3_OFF_HOOK:      EQU 3        ; 0 = modem off hook
; IN0 and IN1 are read with the A-D: IN1 = battery voltage, IN0 unknown.

; Port P0 ($E0): power planes. All active low (0 = on) except bit 6.
P00_IWM_CNTRL:     EQU 0        ; floppy (IWM) power
P01_SCC_CNTRL:     EQU 1        ; SCC power
P02_HD_PWR:        EQU 2        ; hard disk power
P03_MODEM_PWR:     EQU 3        ; modem power
P04_SERIAL_PWR:    EQU 4        ; serial driver power
P05_SOUND_LATCH_CLR: EQU 5      ; pulsed high to clear the sound latch (IN2).
                                ; IDA called it SOUND PWR/, but it is only ever
                                ; pulsed, never left on or off
P06_neg5_EN:       EQU 6        ; -5 V enable (active high)
P07_SYS_PWR:       EQU 7        ; main system power
M_P00_IWM_CNTRL:   EQU $01
M_P01_SCC_CNTRL:   EQU $02
M_P02_HD_PWR:      EQU $04
M_P03_MODEM_PWR:   EQU $08
M_P04_SERIAL_PWR:  EQU $10
M_P05_SOUND_LATCH_CLR: EQU $20
M_P06_neg5_EN:     EQU $40
M_P07_SYS_PWR:     EQU $80

; Port P1 ($E2)
P10_N_C:           EQU 0        ; not connected, set by TICK in test mode
P11_AKD:           EQU 1        ; in: any key down (from the keyboard controller)
P12_STOP_CLK:      EQU 2        ; out: pulsed low while asleep. The sleep loop
                                ; does not wait for the tick itself, so the pulse
                                ; must stop the PMGR clock until the next tick
P13_CHRG_ON:       EQU 3        ; in: low = charger connected
P14_KBD_RST:       EQU 4        ; out: low = reset the M50740 keyboard controller
P15_HICHG:         EQU 5        ; out: high-rate charge
P16_RING_DETECT:   EQU 6        ; in: low = modem ring
P17_MODEM_AB:      EQU 7        ; out: MODEM_A/B select
M_P10_N_C:         EQU $01
M_P16_RING_DETECT: EQU $40
M_P17_MODEM_AB:    EQU $80

; Port P3 ($E8)
P30_RESET:         EQU 0        ; in: reset/interrupt switch (low = pressed)
P31_SYS_RST:       EQU 1        ; out: low = reset the 68000 and peripherals
P32_VIA_TEST:      EQU 2        ; in: high = normal. Low (test mode?) keeps the power
                                ; on: no sleep at power-on, no low battery shutdown
P33_SOUND_ON:      EQU 3        ; out: 1 = sound on (soundSet bit 0). IDA called it
                                ; SOUND_OFF, but it is cleared at reset and before
                                ; sleep, so 1 must mean on
P34_1SEC:          EQU 4        ; out: 1 Hz pulse to VIA CA1
P35_PMINT:         EQU 5        ; out: /PMINT pulse to VIA CB1
P36_PMACK:         EQU 6        ; out: handshake to the VIA
P37_PMREQ:         EQU 7        ; in:  handshake from the VIA
M_P30_RESET:       EQU $01
M_P31_SYS_RST:     EQU $02
M_P32_VIA_TEST:    EQU $04
M_P33_SOUND_ON:    EQU $08
M_P34_1SEC:        EQU $10
M_P35_PMINT:       EQU $20
M_P36_PMACK:       EQU $40
M_P37_PMREQ:       EQU $80

; Port P4 ($EA, 4 bits)
P40_PMGR_ADB:      EQU 0        ; out: 1 = pull the ADB line low
P41_FDB:           EQU 1        ; in:  ADB line level
P42_DISP_BLANK:    EQU 2        ; out: low = blank the display
P43_MODEM_INS:     EQU 3        ; in:  low = modem installed
M_P40_PMGR_ADB:    EQU $01
M_P41_FDB:         EQU $02
M_P42_DISP_BLANK:  EQU $04
M_P43_MODEM_INS:   EQU $08

;==============================================================================
; RAM
;==============================================================================
                RSEG RAM
FLAGS:          BLKB 1          ; $00 FLAG_xxx
INT_STATE:      BLKB 1          ; $01 INT_xxx, reply to readINT
TEMP:           BLKB 1          ; $02 scratch
ADB_SEND_COUNT: BLKB 1          ; $03 number of Listen data bytes
ADB_SHIFT:      BLKB 1          ; $04 ADB transmit shift register
ADB_COMMAND:    BLKB 1          ; $05 ADB command byte  \  readADB replies these
ADB_FLAGS:      BLKB 1          ; $06 ADBF_xxx          |  bytes in this order
ADB_COUNT:      BLKB 1          ; $07 data byte count   |
ADB_BUFFER:     BLKB 8          ; $08 ADB data          /
ADB_RX_STACK:   BLKB 1          ; $10 S during ADB receive: bytes are PHAed into $10-$09
COMMAND:        BLKB 1          ; $11 current host command
COMMAND_SIZE:   BLKB 1          ; $12 its byte count
PARAMETER:      BLKB 8          ; $13 parameter / reply buffer (counts are not checked!)
PTR:            BLKB 2          ; $1B transfer pointer
BAT_FLAGS:      BLKB 1          ; $1D BATF_xxx    \  batteryRead replies
BAT_VOLTAGE:    BLKB 1          ; $1E IN1, filtered | these 3 bytes
BAT_IN0:        BLKB 1          ; $1F IN0         /
BAT_VERY_LOW:   BLKB 1          ; $20 (LOW+DEAD)/2
BAT_HICHG_STATE: BLKB 1         ; $21 HICHG_xxx
HICHG_TIMER_LO: BLKB 1          ; $22 high-rate charge timer (ticks)
HICHG_TIMER_HI: BLKB 1          ; $23
TICK_COUNT:     BLKB 1          ; $24 counts 60 ticks down to the next second
TIME_S:         BLKB 4          ; $25 clock: seconds since 1904, big-endian
TIME_CHECKSUM:  BLKB 1          ; $29 sum of TIME_S, detects a lost clock
ALARM_TIME:     BLKB 4          ; $2A wakeup time, big-endian
CONTRAST:       BLKB 1          ; $2E LCD contrast 0-31
XPRAM:          BLKB 8          ; $2F 128 bytes XPRAM ($00-$7F)
XPRAM_08:       BLKB 8          ;     XPRAM $08: classic PRAM bytes 16-19
XPRAM_10:       BLKB $32        ;     XPRAM $10: classic PRAM bytes 0-15
XPRAM_BAT_LOW:  BLKB 1          ;     XPRAM $42: low battery level (default 78)
XPRAM_BAT_DEAD: BLKB 1          ;     XPRAM $43: dead battery level (default 62)
XPRAM_44:       BLKB $3C        ;     XPRAM $44: default 200, effectively unused
XPRAM_CHKSUM:   BLKB 1          ; $AF sum of the 128 XPRAM bytes
STACK_BOTTOM:   BLKB $F         ; $B0 16 byte stack
STACK_TOP:      BLKB 1          ; $BF
RAM_END:        BLKB $20        ; $C0-$DF not present

; SFRs ($E0-$FF)
PORT_P0:        BLKB 1          ; $E0
PORT_P0_DIR:    BLKB 1          ; $E1 1 = output
PORT_P1:        BLKB 1          ; $E2
PORT_P1_DIR:    BLKB 1          ; $E3
PORT_P2:        BLKB 1          ; $E4 host data bus
PORT_P2_DIR:    BLKB 1          ; $E5
                BLKB 1          ; $E6
SFR_E7:         BLKB 1          ; $E7
PORT_P3:        BLKB 1          ; $E8
PORT_P3_DIR:    BLKB 1          ; $E9
PORT_P4:        BLKB 1          ; $EA
PORT_P4_DIR:    BLKB 1          ; $EB
                BLKB 2          ; $EC
IN:             BLKB 1          ; $EE input port IN
AD:             BLKB 1          ; $EF A-D result
SFR_F0:         BLKB 2          ; $F0
AD_START:       BLKB 1          ; $F2 any write starts a conversion
AD_CTRL:        BLKB 1          ; $F3 bits 0-2 channel, bit 3: A-D drives IRQ_T1_AD_REQ
                BLKB 1          ; $F4
PWM_CTRL:       BLKB 1          ; $F5
SERIAL_IO_MODE: BLKB 1          ; $F6 (unused)
SERIAL_IO:      BLKB 1          ; $F7 (unused)
                BLKB 1          ; $F8
TIMER_12_PRES:  BLKB 1          ; $F9 timer 1/2 prescaler
TIMER1:         BLKB 1          ; $FA PWM high time
TIMER2:         BLKB 1          ; $FB PWM low time
TIMERX_PRES:    BLKB 1          ; $FC
TIMERX:         BLKB 1          ; $FD
IRQ_CTRL:       BLKB 1          ; $FE IRQ_xxx
TIMER_CTRL:     BLKB 1          ; $FF

;==============================================================================
; ROM
;
; Function headers list
;   In:      registers and RAM the function reads
;   Out:     registers and RAM it returns or changes on purpose
;   Changes: other registers it destroys
; Command handlers get COMMAND and COMMAND_SIZE from MAIN_LOOP. Their carry
; result is ignored by the dispatcher.
;==============================================================================
                RSEG ROM
                ORG $E800

;------------------------------------------------------------------------------
; VECTOR_RESET - power-on reset
; The ROM starts with a header (version, checksum, signature, copyright), so
; the reset entry has to jump over it.
; In:  -
; Out: does not return, continues in INIT with Y = M_INT_RESET
;------------------------------------------------------------------------------
VECTOR_RESET:
                bra     RESET
ROM_VERSION:    BYTE    2,181           ; $02,$B5, returned by readPmgrVers
ROM_CHECKSUM:   BYTE    $76,$44         ; expected PARAMETER+1 and A of CHECK_ROM_CHECKSUM
aMATT:          BYTE    'M','A','T','T' ; signature required by sleepReq
aBUGS:          BYTE    'B','u','g','s'
                BYTE    $A8             ; Mac Roman (c)
aCopyrightApple:BYTE    "Copyright Apple Computer Inc  1987, 1988, 1989 Written by Micha"
                BYTE    "el Hanlon "

RESET:
                ldy     #M_INT_RESET    ; tell the host that the PMGR lost its state
                bra     INIT

;------------------------------------------------------------------------------
; WARM_RESET / INIT - initialise the PMGR and start the Mac
; The PMGR runs from the battery and is only reset when power was lost or the
; reset switch was pressed. RAM may therefore still hold valid XPRAM and a
; valid clock; both are kept if their checksums match.
; A cold reset leaves every power plane off and, with P32 high, goes straight
; to sleep: the Portable only powers up when a key is pressed. A warm reset
; (reset switch) keeps the machine powered and restarts the 68000.
; In:  Y = M_INT_RESET (cold, from RESET) or 0 (warm, WARM_RESET)
; Out: does not return, continues in MAIN_LOOP or ENTER_SLEEP
;------------------------------------------------------------------------------
WARM_RESET:
                ldy     #0

INIT:
                ldx     #STACK_TOP
                txs
                clt                     ; T=1 would redirect ALU ops to (X)
                sei
                cld

                jsr     XPRAM_IS_VALID
                bcc     INIT_XPRAM_OK
                ldx     #0              ; garbage after a power loss: start over
                lda     #0

INIT_XPRAM_CLR:
                sta     XPRAM, X
                inx
                bpl     INIT_XPRAM_CLR
                sta     BAT_FLAGS
                sta     BAT_HICHG_STATE
                ldm     #78, XPRAM_BAT_LOW  ; CHECK_BATTERY needs sane levels
                ldm     #62, XPRAM_BAT_DEAD
                ldm     #200, XPRAM_44
                jsr     XPRAM_IS_VALID  ; only for the new sum in A
                sta     XPRAM_CHKSUM

INIT_XPRAM_OK:
                lda     #0
                sta     FLAGS
                sta     ADB_FLAGS       ; no auto-poll until the host asks for it

                jsr     TIME_CALC_CHECKSUM
                cmp     TIME_CHECKSUM
                beq     INIT_TIME_OK
                ldx     #9              ; clock lost: clear TICK_COUNT..ALARM_TIME
                lda     #0

INIT_TIME_CLR:
                sta     TICK_COUNT, X
                dex
                bpl     INIT_TIME_CLR

INIT_TIME_OK:
                lda     PORT_P0         ; warm: all planes on, -5 V on, but keep the
                and     #M_P02_HD_PWR   ; hard disk as it was
                ora     #M_P06_neg5_EN
                sty     INT_STATE

                tst     INT_STATE
                beq     INIT_PORTS
                lda     #M_P00_IWM_CNTRL|M_P01_SCC_CNTRL|M_P02_HD_PWR|M_P03_MODEM_PWR|M_P04_SERIAL_PWR|M_P07_SYS_PWR
                                        ; cold: all planes off

INIT_PORTS:                             ; PmgrSoftReset enters here
                sta     PORT_P0
                ldm     #0b11111111, PORT_P0_DIR
                ldm     #M_P10_N_C|M_P16_RING_DETECT|M_P17_MODEM_AB, PORT_P1
                                        ; keyboard controller held in reset
                ldm     #0b10110101, PORT_P1_DIR
                ldm     #0b11111111, PORT_P2
                ldm     #0b00000000, PORT_P2_DIR
                ldm     #M_P30_RESET|M_P32_VIA_TEST|M_P34_1SEC|M_P35_PMINT|M_P36_PMACK|M_P37_PMREQ, PORT_P3
                                        ; 68000 held in reset, sound off
                ldm     #0b01111010, PORT_P3_DIR
                ldm     #M_P41_FDB|M_P42_DISP_BLANK|M_P43_MODEM_INS, PORT_P4
                ldm     #0b00000101, PORT_P4_DIR

                ldm     #0, TIMER_CTRL
                ldm     #0, IRQ_CTRL    ; everything is polled
                ldm     #4, TIMER_12_PRES
                ldm     #1, TIMERX_PRES
                ldm     #1, TIMERX_PRES ; sic, written twice (timer X is not used)

                lda     CONTRAST        ; RAM may be garbage: allow 1..31, else 4
                bmi     INIT_CONTRAST_DEFAULT
                beq     INIT_CONTRAST_DEFAULT
                cmp     #32
                bcc     INIT_CONTRAST_OK

INIT_CONTRAST_DEFAULT:
                ldm     #4, CONTRAST

INIT_CONTRAST_OK:
                lda     CONTRAST
                sta     PARAMETER
                jsr     SET_CONTRAST
                seb     PWM_EN, PWM_CTRL

                jsr     BATTERY_READ    ; start the voltage filter with a real value
                seb     P14_KBD_RST, PORT_P1

                cpy     #0
                beq     INIT_RUN
                bbc     P32_VIA_TEST, PORT_P3, INIT_RUN
                jmp     ENTER_SLEEP     ; cold reset: stay off until a key is pressed

INIT_RUN:
                ldx     #2              ; presumably lets the power planes settle

INIT_WAIT_TICK:
                bit     IRQ_CTRL
                bpl     INIT_WAIT_TICK
                jsr     TICK
                dex
                bne     INIT_WAIT_TICK

                seb     P31_SYS_RST, PORT_P3 ; start the 68000
                seb     P05_SOUND_LATCH_CLR, PORT_P0
                clb     P05_SOUND_LATCH_CLR, PORT_P0
                clb     IRQ_INT2_REQ, IRQ_CTRL ; forget a switch press from before
                seb     IRQ_INT2_EN, IRQ_CTRL
                cli

;------------------------------------------------------------------------------
; MAIN_LOOP - poll for work, never returns
; Waits for one of
;   - the 60 Hz tick: clock, alarm, battery (TICK), ADB auto-poll, /PMINT
;   - a new pMgrADB command: sent at once, without waiting for the tick
;   - PMREQ low: the host sends a command, which is dispatched by its high
;     nibble through COMMAND_TABLE
; readINT and readADB are checked first because the host sends them after
; every /PMINT.
; While busy with a tick or ADB the PMGR drives $07 onto the data bus (the
; reason is unknown).
;------------------------------------------------------------------------------
MAIN_LOOP:
                ldm     #0, PORT_P2_DIR ; release the data bus

MAIN_POLL:
                bit     IRQ_CTRL
                bmi     MAIN_TICK

                bbs     ADBF_PENDING, ADB_FLAGS, MAIN_DO_ADB
                bbs     P37_PMREQ, PORT_P3, MAIN_POLL

                jsr     READ_COMMAND
                bcs     MAIN_LOOP       ; handshake broke off: drop the command

                lda     COMMAND
                cmp     #PM_readINT
                bne     MAIN_NOT_READINT
                jsr     COMMAND_78_readINT
                bra     MAIN_LOOP

MAIN_NOT_READINT:
                cmp     #PM_readADB
                bne     MAIN_DISPATCH
                jsr     COMMAND_28_readADB
                bra     MAIN_LOOP

MAIN_DISPATCH:
                and     #$F0            ; X = (command >> 4) * 2
                lsr     A
                lsr     A
                lsr     A
                tax
                lda     COMMAND_TABLE, X
                sta     PTR
                lda     COMMAND_TABLE+1, X
                sta     PTR+1
                jsr     (PTR)
                bra     MAIN_LOOP

MAIN_TICK:
                ldm     #7, PORT_P2
                ldm     #$FF, PORT_P2_DIR

                jsr     TICK
                bbs     INT_ADB, INT_STATE, MAIN_CHECK_INT ; don't overwrite unread ADB data
                bbs     ADBF_PENDING, ADB_FLAGS, MAIN_DO_ADB
                bbc     ADBF_AUTOPOLL, ADB_FLAGS, MAIN_CHECK_INT

MAIN_DO_ADB:
                ldm     #7, PORT_P2
                ldm     #$FF, PORT_P2_DIR

                lda     ADB_FLAGS       ; drop the status of the last transaction
                and     #0b00000101
                sta     ADB_FLAGS
                lda     ADB_SEND_COUNT  ; a Talk answer may have replaced the count
                sta     ADB_COUNT
                lda     ADB_COMMAND
                and     #$F
                bne     MAIN_ADB_SEND
                seb     P40_PMGR_ADB, PORT_P4 ; command $x0 is an ADB reset: line low
                ldx     #0              ; for 3 x 1545 us = 4.6 ms (spec: >= 3 ms)
                jsr     \DELAY_LOOP_X
                jsr     \DELAY_LOOP_X
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4
                seb     ADBF_NO_DATA, ADB_FLAGS
                bra     MAIN_ADB_REPORT

MAIN_ADB_SEND:
                jsr     ADB_SEND_CMD
                bcc     MAIN_ADB_RECEIVE
                seb     ADBF_NO_DATA, ADB_FLAGS
                bra     MAIN_ADB_REPORT

MAIN_ADB_RECEIVE:
                jsr     ADB_RECEIVE_CMD ; also after Listen/Flush: times out there
                bcc     MAIN_ADB_REPORT
                bbc     ADBF_AUTOPOLL, ADB_FLAGS, MAIN_ADB_REPORT
                bbc     ADBF_SRQ, ADB_FLAGS, MAIN_CHECK_INT
                                        ; an idle auto-poll must not interrupt the host

MAIN_ADB_REPORT:
                seb     INT_ADB, INT_STATE

MAIN_CHECK_INT:                         ; reached at most once per tick, so /PMINT
                lda     INT_STATE       ; repeats every 1/60 s until the host reacts
                and     #M_INT_ADB|M_INT_BATT|M_INT_BATT2
                beq     MAIN_NEXT
                clb     P35_PMINT, PORT_P3
                seb     FLAG_PMINT_SENT, FLAGS
                seb     P35_PMINT, PORT_P3

MAIN_NEXT:
                jmp     MAIN_LOOP

;------------------------------------------------------------------------------
; READ_COMMAND - receive the command header from the host
; In:  - (PMREQ is already low)
; Out: COMMAND, COMMAND_SIZE; C = 1: handshake timeout
; Changes: A
;
; READ_PARAMETER - receive COMMAND_SIZE bytes into PARAMETER
; READ_BYTES - receive COMMAND_SIZE bytes to (PTR)
; In:  COMMAND_SIZE (0 means 256), PTR (READ_BYTES only)
; Out: data at (PTR); COMMAND_SIZE = 0 if complete; C = 1: timeout
; Changes: A, Y
; Note: the count comes from the host and is not checked against the 8 byte
; PARAMETER buffer; more than 8 bytes overwrite PTR and the battery state.
;------------------------------------------------------------------------------
READ_COMMAND:
                jsr     READ_BYTE
                bcs     READ_DONE
                sta     COMMAND
                jsr     READ_BYTE
                bcs     READ_DONE
                sta     COMMAND_SIZE
                rts

READ_PARAMETER:
                ldm     #PARAMETER, PTR
                ldm     #0, PTR+1

READ_BYTES:
                ldy     #0

READ_BYTES_LOOP:
                jsr     READ_BYTE
                bcs     READ_DONE
                sta     (PTR), Y
                iny
                dec     COMMAND_SIZE
                bne     READ_BYTES_LOOP
                clc

READ_DONE:
                rts

;------------------------------------------------------------------------------
; READ_BYTE - receive one byte with the PMREQ/PMACK handshake
; The host pulls PMREQ low when the byte is on the bus; PMACK low tells it the
; byte was taken, and PMREQ going high again ends the cycle. The timeouts are
; unrolled BBC/BBS chains (5 us each) so a missing host can't hang the PMGR.
; In:  -
; Out: A = byte; C = 1: PMREQ did not go low (or high again) within ~45 us
; Changes: -
;------------------------------------------------------------------------------
READ_BYTE:
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bbc     P37_PMREQ, PORT_P3, RB_REQ
                bra     RB_TIMEOUT

RB_REQ:
                lda     PORT_P2
                clb     P36_PMACK, PORT_P3
                bbs     P37_PMREQ, PORT_P3, RB_OK
                bbs     P37_PMREQ, PORT_P3, RB_OK
                bbs     P37_PMREQ, PORT_P3, RB_OK
                bbs     P37_PMREQ, PORT_P3, RB_OK
                bbs     P37_PMREQ, PORT_P3, RB_OK
                bbs     P37_PMREQ, PORT_P3, RB_OK
                bbs     P37_PMREQ, PORT_P3, RB_OK
                bbs     P37_PMREQ, PORT_P3, RB_OK
                bbs     P37_PMREQ, PORT_P3, RB_OK

RB_TIMEOUT:
                seb     P36_PMACK, PORT_P3
                sec
                rts

RB_OK:
                seb     P36_PMACK, PORT_P3
                clc
                rts

;------------------------------------------------------------------------------
; SEND_COMMAND_PARAMETER - send a reply from PARAMETER
; SEND_COMMAND - send a reply from (PTR)
; A reply has the same format as a command: COMMAND, COMMAND_SIZE, data.
; In:  COMMAND, COMMAND_SIZE, PTR (SEND_COMMAND only)
; Out: C = 1: the host did not take a byte
; Changes: A, X, Y, COMMAND_SIZE
;
; SEND_BUFFER - send COMMAND_SIZE data bytes only
; In:  PTR, Y = offset, COMMAND_SIZE (0 means 256)
;------------------------------------------------------------------------------
SEND_COMMAND_PARAMETER:
                ldm     #PARAMETER, PTR
                ldm     #0, PTR+1

SEND_COMMAND:
                lda     COMMAND
                jsr     SEND_BYTE
                bcs     SEND_DONE
                lda     COMMAND_SIZE
                jsr     SEND_BYTE
                bcs     SEND_DONE
                tst     COMMAND_SIZE
                beq     SEND_DONE
                ldy     #0

SEND_BUFFER:
                lda     (PTR), Y
                jsr     SEND_BYTE
                bcs     SEND_DONE
                iny
                dec     COMMAND_SIZE
                bne     SEND_BUFFER
                clc

SEND_DONE:
                rts

;------------------------------------------------------------------------------
; SEND_BYTE - send one byte with the PMREQ/PMACK handshake
; The host must not be requesting anything itself (PMREQ high). PMACK low
; signals "byte on the bus"; the host takes it by pulling PMREQ low.
; In:  A = byte
; Out: C = 1: PMREQ was low at the start or did not go low within ~4 ms
; Changes: X
;------------------------------------------------------------------------------
SEND_BYTE:
                bbc     P37_PMREQ, PORT_P3, SB_TIMEOUT
                ldm     #$FF, PORT_P2_DIR
                sta     PORT_P2
                clb     P36_PMACK, PORT_P3
                bbc     P37_PMREQ, PORT_P3, SB_OK
                ldx     #0              ; 256 x 16 us

SB_WAIT_REQ:
                bbc     P37_PMREQ, PORT_P3, SB_OK
                dex
                bbc     P37_PMREQ, PORT_P3, SB_OK
                bne     SB_WAIT_REQ

SB_TIMEOUT:
                seb     P36_PMACK, PORT_P3
                ldm     #0, PORT_P2_DIR
                sec
                rts

SB_OK:
                seb     P36_PMACK, PORT_P3
                ldm     #0, PORT_P2_DIR
                clc
                rts

;------------------------------------------------------------------------------
; CHECK_BATTERY - update the battery and charger state, called every tick
; - Charger plugged in or removed: set BATF_CHARGER_CHANGED and INT_BATT, and
;   restart the voltage filter because the voltage jumps.
; - Charger connected: run the high-rate charge state machine.
; - On battery: compare the voltage with the levels in XPRAM. BATF_LOW sets
;   INT_BATT on every tick, so the host keeps getting /PMINT until the voltage
;   recovers. A dead battery shuts the machine down (unless it is already
;   asleep or P32 is low) before the voltage gets too low to run.
; Note: removing the charger does not switch the high-rate charge (P15) off;
; it stays on until the charger is connected again.
; In:  BAT_FLAGS, BAT_HICHG_STATE, XPRAM levels
; Out: BAT_FLAGS, BAT_VOLTAGE, BAT_IN0, INT_STATE, P15; may jump to ENTER_SLEEP
; Changes: A
;------------------------------------------------------------------------------
CHECK_BATTERY:
                jsr     BATTERY_SAMPLE

                lda     XPRAM_44        ; dead code: min(XPRAM_44, 220) is compared
                cmp     #220            ; with BAT_IN0, but the result is not used
                bcc     BAT_44_CLIPPED
                lda     #220

BAT_44_CLIPPED:
                cmp     BAT_IN0
                bcs     BAT_CHECK_CHARGER

BAT_CHECK_CHARGER:
                lda     BAT_FLAGS       ; BATF_CHARGER is 1 when P13 is 0, so moved to
                asl     A               ; bit 3 and XORed with P1 it gives 1 as long
                asl     A               ; as nothing changed
                asl     A
                eor     PORT_P1
                bbs     P13_CHRG_ON, A, BAT_CHARGER_SAME
                seb     INT_BATT, INT_STATE
                seb     BATF_CHARGER_CHANGED, BAT_FLAGS
                jsr     BATTERY_READ

BAT_CHARGER_SAME:
                clb     BATF_CHARGER, BAT_FLAGS
                clb     BATF_DEAD, BAT_FLAGS
                clb     BATF_VERY_LOW, BAT_FLAGS
                bbc     P13_CHRG_ON, PORT_P1, BAT_CHARGER

                lda     XPRAM_BAT_LOW   ; the levels are host-writable XPRAM: only
                cmp     #90             ; accept 59..89 with LOW >= DEAD
                bcs     BAT_DEFAULT_LEVELS
                cmp     #59
                bcc     BAT_DEFAULT_LEVELS
                lda     XPRAM_BAT_DEAD
                cmp     #90
                bcs     BAT_DEFAULT_LEVELS
                cmp     #59
                bcc     BAT_DEFAULT_LEVELS
                lda     XPRAM_BAT_LOW
                cmp     XPRAM_BAT_DEAD
                bcc     BAT_DEFAULT_LEVELS

BAT_ON_BATTERY:
                lda     XPRAM_BAT_LOW   ; BAT_VERY_LOW = LOW/2 + DEAD/2
                lsr     A
                sta     BAT_VERY_LOW
                lda     XPRAM_BAT_DEAD
                lsr     A
                clc
                adc     BAT_VERY_LOW
                sta     BAT_VERY_LOW

                lda     BAT_VOLTAGE
                cmp     XPRAM_BAT_LOW
                bcc     BAT_BELOW_LOW
                bbc     BATF_LOW, BAT_FLAGS, BAT_HICHG_RESTART
                clb     BATF_LOW, BAT_FLAGS ; recovered: tell the host once
                seb     INT_BATT, INT_STATE
                bra     BAT_HICHG_RESTART

BAT_BELOW_LOW:
                seb     BATF_LOW, BAT_FLAGS
                seb     INT_BATT, INT_STATE
                cmp     BAT_VERY_LOW
                bcs     BAT_HICHG_RESTART
                seb     BATF_VERY_LOW, BAT_FLAGS
                cmp     XPRAM_BAT_DEAD
                bcs     BAT_HICHG_RESTART
                seb     BATF_DEAD, BAT_FLAGS
                bbs     FLAG_SLEEPING, FLAGS, BAT_HICHG_RESTART
                bbc     P32_VIA_TEST, PORT_P3, BAT_HICHG_RESTART
                jmp     ENTER_SLEEP

BAT_HICHG_RESTART:                      ; on battery, or charge voltage < 90: run
                ldm     #HICHG_START, BAT_HICHG_STATE ; a full high-rate charge next time
                rts

BAT_DEFAULT_LEVELS:
                ldm     #78, XPRAM_BAT_LOW
                ldm     #62, XPRAM_BAT_DEAD
                ldm     #200, XPRAM_44
                jsr     XPRAM_IS_VALID  ; keep XPRAM valid after the change
                sta     XPRAM_CHKSUM
                bra     BAT_ON_BATTERY

; Charger connected. The high-rate charge stays on for twice the time the
; battery needs to reach 208. While asleep PARAMETER+1 holds the PORT_P1 value
; that WAKE restores, so P15 is changed there as well.
BAT_CHARGER:
                seb     BATF_CHARGER, BAT_FLAGS
                clb     BATF_LOW, BAT_FLAGS

                lda     BAT_HICHG_STATE
                bne     HICHG_STATE_1
                seb     P15_HICHG, PORT_P1 ; HICHG_START
                seb     P15_HICHG, PARAMETER+1
                seb     BATF_HICHARGE_ON, BAT_FLAGS
                ldm     #HICHG_COUNT_UP, BAT_HICHG_STATE
                ldm     #1, HICHG_TIMER_LO
                ldm     #1, HICHG_TIMER_HI
                clb     BATF_HICHARGE_OVF, BAT_FLAGS
                rts

HICHG_STATE_1:
                cmp     #HICHG_COUNT_DOWN
                bcs     HICHG_STATE_2
                lda     BAT_VOLTAGE     ; HICHG_COUNT_UP
                cmp     #208
                bcs     HICHG_GO_COUNT_DOWN
                bbs     BATF_HICHARGE_OVF, BAT_FLAGS, HICHG_CHECK_MIN
                inc     HICHG_TIMER_LO
                bne     HICHG_CHECK_MIN
                inc     HICHG_TIMER_HI
                bne     HICHG_CHECK_MIN
                seb     BATF_HICHARGE_OVF, BAT_FLAGS ; stop counting at ~18 min
                rts

HICHG_GO_COUNT_DOWN:
                ldm     #HICHG_COUNT_DOWN, BAT_HICHG_STATE
                rts

HICHG_STATE_2:
                bne     HICHG_CHECK_MIN ; HICHG_DONE: nothing to do
                dec     HICHG_TIMER_LO  ; HICHG_COUNT_DOWN
                bne     HICHG_CHECK_MIN
                dec     HICHG_TIMER_HI
                bne     HICHG_CHECK_MIN
                ldm     #HICHG_DONE, BAT_HICHG_STATE
                clb     P15_HICHG, PORT_P1
                clb     P15_HICHG, PARAMETER+1
                clb     BATF_HICHARGE_ON, BAT_FLAGS

HICHG_CHECK_MIN:
                lda     BAT_VOLTAGE
                cmp     #90
                bcc     BAT_HICHG_RESTART
                rts

;------------------------------------------------------------------------------
; BATTERY_SAMPLE - sample IN1 and IN0, filtering the battery voltage
; The (old + new) / 2 low-pass smooths the load-dependent voltage so the
; thresholds in CHECK_BATTERY don't flicker.
; BATTERY_READ - same without the filter, for a fresh value (batteryNow, a
; charger change, power-up)
; AD_CTRL bit 3 routes "conversion done" to IRQ_T1_AD_REQ, which is polled.
; In:  BAT_VOLTAGE (BATTERY_SAMPLE only)
; Out: BAT_VOLTAGE = IN1, BAT_IN0 = IN0 (unknown input, maybe temperature)
; Changes: A
;------------------------------------------------------------------------------
BATTERY_SAMPLE:
                clb     3, AD_CTRL
                ldm     #1, AD_CTRL     ; channel IN1
                seb     3, AD_CTRL
                clb     IRQ_T1_AD_REQ, IRQ_CTRL
                ldm     #0, AD_START

BAT_SAMPLE_WAIT1:
                lda     IRQ_CTRL
                nop
                bbc     IRQ_T1_AD_REQ, A, BAT_SAMPLE_WAIT1
                lda     AD
                clc
                adc     BAT_VOLTAGE
                ror     A               ; ROR keeps the carry of the 9-bit sum
                sta     BAT_VOLTAGE
                clb     3, AD_CTRL
                ldm     #0, AD_CTRL     ; channel IN0
                seb     3, AD_CTRL
                clb     IRQ_T1_AD_REQ, IRQ_CTRL
                ldm     #0, AD_START

BAT_SAMPLE_WAIT2:
                lda     IRQ_CTRL
                nop
                bbc     IRQ_T1_AD_REQ, A, BAT_SAMPLE_WAIT2
                lda     AD
                sta     BAT_IN0
                clb     3, AD_CTRL
                rts

BATTERY_READ:
                clb     3, AD_CTRL
                ldm     #1, AD_CTRL     ; channel IN1
                seb     3, AD_CTRL
                clb     IRQ_T1_AD_REQ, IRQ_CTRL
                ldm     #0, AD_START

BAT_READ_WAIT1:
                lda     IRQ_CTRL
                nop
                bbc     IRQ_T1_AD_REQ, A, BAT_READ_WAIT1
                lda     AD
                sta     BAT_VOLTAGE
                clb     3, AD_CTRL
                ldm     #0, AD_CTRL     ; channel IN0
                seb     3, AD_CTRL
                clb     IRQ_T1_AD_REQ, IRQ_CTRL
                ldm     #0, AD_START

BAT_READ_WAIT2:
                lda     IRQ_CTRL
                nop
                bbc     IRQ_T1_AD_REQ, A, BAT_READ_WAIT2
                lda     AD
                sta     BAT_IN0
                clb     3, AD_CTRL
                rts

;------------------------------------------------------------------------------
; TICK - 60 Hz housekeeping
; Called whenever IRQ_INT1_REQ is set (and once per wake-up while asleep).
; - Awake with P32 low: force every plane except the modem on (a test mode,
;   presumably so the board runs without the OS managing power).
; - Every 60th tick: 1 Hz pulse to the VIA (the Mac OS counts seconds with
;   it), increment the clock, and while asleep compare it with the alarm.
;   The alarm is only needed to wake the machine; FLAG_ALARM_HIT lasts one
;   tick, long enough for the sleep loop to see it.
; - Every tick: CHECK_BATTERY.
; Callers keep loop counters in X and Y, so TICK must preserve them.
; In:  -
; Out: TIME_S, TIME_CHECKSUM, TICK_COUNT, FLAG_ALARM_HIT, battery state
; Changes: A
;------------------------------------------------------------------------------
TICK:
                clb     IRQ_INT1_REQ, IRQ_CTRL
                clb     FLAG_ALARM_HIT, FLAGS
                bbs     FLAG_SLEEPING, FLAGS, TICK_COUNT_DOWN
                bbs     P32_VIA_TEST, PORT_P3, TICK_COUNT_DOWN
                ldm     #M_P03_MODEM_PWR|M_P06_neg5_EN, PORT_P0
                seb     P10_N_C, PORT_P1

TICK_COUNT_DOWN:
                dec     TICK_COUNT
                beq     TICK_1HZ
                rts

TICK_1HZ:
                clb     P34_1SEC, PORT_P3
                seb     P34_1SEC, PORT_P3
                ldm     #60, TICK_COUNT

                inc     TIME_S+3        ; 32-bit big-endian increment
                bne     TICK_TIME_DONE
                inc     TIME_S+2
                bne     TICK_TIME_DONE
                inc     TIME_S+1
                bne     TICK_TIME_DONE
                inc     TIME_S

TICK_TIME_DONE:
                jsr     TIME_CALC_CHECKSUM
                sta     TIME_CHECKSUM

                bbc     FLAG_ALARM_SET, FLAGS, TICK_CHECK_BAT
                bbc     FLAG_SLEEPING, FLAGS, TICK_CHECK_BAT
                bbs     FLAG_ALARM_HIT, FLAGS, TICK_CHECK_BAT ; never set here
                lda     ALARM_TIME+3
                cmp     TIME_S+3
                bne     TICK_CHECK_BAT
                lda     ALARM_TIME+2
                cmp     TIME_S+2
                bne     TICK_CHECK_BAT
                lda     ALARM_TIME+1
                cmp     TIME_S+1
                bne     TICK_CHECK_BAT
                lda     ALARM_TIME
                cmp     TIME_S
                bne     TICK_CHECK_BAT
                seb     FLAG_ALARM_HIT, FLAGS

TICK_CHECK_BAT:
                jsr     CHECK_BATTERY
                rts

;------------------------------------------------------------------------------
; ADB_SEND_CMD - send the ADB command and, for Listen, its data
; The ADB has no hardware support here, so the waveform is produced by
; cycle-counted code (1 cycle = 1 us); the delays below only work at 4 MHz.
; P40 = 1 pulls the line low, P41 reads it back. Every time the line is
; released it must read high, otherwise another device is driving it.
;   attention 800 us low, sync 70 us high, 8 command bits, stop bit
;   bit cell 100 us: '0' = 65 us low / 35 us high, '1' = 35 us low / 65 us high
;   after the stop bit a device may hold the line low for ~300 us (SRQ)
;   Listen: Tlt ~160 us, start bit '1', ADB_COUNT data bytes, stop bit
; In:  ADB_COMMAND, ADB_COUNT = number of Listen bytes (0 = none),
;      ADB_BUFFER (data in reverse order)
; Out: C = 1: bus error (ADBF_BUS_ERR, ADBF_ERROR); ADBF_SRQ; ADB_COUNT = $FF
;      after Listen data
; Changes: A, X, Y, ADB_SHIFT
;------------------------------------------------------------------------------
ADB_SEND_CMD:
                lda     ADB_FLAGS
                and     #5
                sta     ADB_FLAGS
                lda     ADB_COMMAND
                sta     ADB_SHIFT

                seb     P40_PMGR_ADB, PORT_P4 ; attention
                ldx     #131
                jsr     \DELAY_LOOP_X
                nop
                clb     P40_PMGR_ADB, PORT_P4

                ldx     #6              ; sync
                jsr     \DELAY_LOOP_X
                bbc     P41_FDB, PORT_P4, TX_BUS_ERROR
                nop
                ldy     #8              ; MSB first
                bra     TX_BIT

TX_NEXT_BIT:
                ldx     #1              ; pad the cell to 100 us
                jsr     \DELAY_LOOP_X
                nop

TX_BIT:
                seb     P40_PMGR_ADB, PORT_P4
                ldx     #2
                jsr     \DELAY_LOOP_X
                rol     ADB_SHIFT
                bcc     TX_BIT_0
                clb     P40_PMGR_ADB, PORT_P4 ; '1': release after 35 us
                bbc     P41_FDB, PORT_P4, TX_BUS_ERROR
                bra     TX_BIT_END

TX_BIT_0:
                jsr     \DELAY_RTS      ; same time as the '1' path

TX_BIT_END:
                ldx     #1
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4 ; '0': release after 65 us
                bbc     P41_FDB, PORT_P4, TX_BUS_ERROR
                dey
                bne     TX_NEXT_BIT
                ldx     #1
                jsr     \DELAY_LOOP_X
                nop
                nop
                seb     P40_PMGR_ADB, PORT_P4 ; stop bit: 65 us low
                ldx     #9
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4
                bbc     P41_FDB, PORT_P4, TX_CHECK_SRQ

TX_NO_SRQ:
                bra     TX_CMD_DONE

TX_CHECK_SRQ:                           ; a device holds the line low
                ldx     #9              ; high within ~100 us: just a slow edge

TX_SRQ_WAIT1:
                bbs     P41_FDB, PORT_P4, TX_NO_SRQ
                dex
                bne     TX_SRQ_WAIT1
                ldx     #19             ; high within another ~210 us: SRQ

TX_SRQ_WAIT2:
                bbs     P41_FDB, PORT_P4, TX_SRQ
                dex
                bne     TX_SRQ_WAIT2
                bra     TX_BUS_ERROR    ; still low: the bus is stuck

TX_SRQ:
                seb     ADBF_SRQ, ADB_FLAGS
                bra     TX_CMD_DONE

TX_BUS_ERROR:
                seb     ADBF_BUS_ERR, ADB_FLAGS
                seb     ADBF_ERROR, ADB_FLAGS
                clb     P40_PMGR_ADB, PORT_P4
                sec
                rts

TX_CMD_DONE:
                tst     ADB_COUNT
                bne     TX_LISTEN_DATA
                clc
                rts

TX_LISTEN_DATA:                         ; buffer is reversed: send from the top
                ldy     #8
                ldx     ADB_COUNT
                dec     ADB_COUNT
                lda     ADB_BUFFER-1, X
                sta     ADB_SHIFT
                ldx     #25             ; Tlt ~160 us
                jsr     \DELAY_LOOP_X
                seb     P40_PMGR_ADB, PORT_P4 ; start bit '1'
                nop
                ldx     #3
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4
                nop
                nop
                ldx     #6
                jsr     \DELAY_LOOP_X
                bbc     P41_FDB, PORT_P4, TX_BUS_ERROR
                bra     TX_DATA_BIT

TX_DATA_NEXT_BIT:
                ldx     #1
                jsr     \DELAY_LOOP_X
                nop

TX_DATA_BIT:                            ; same timing as TX_BIT
                seb     P40_PMGR_ADB, PORT_P4
                ldx     #2
                jsr     \DELAY_LOOP_X
                rol     ADB_SHIFT
                bcc     TX_DATA_BIT_0
                clb     P40_PMGR_ADB, PORT_P4
                bbc     P41_FDB, PORT_P4, TX_BUS_ERROR
                bra     TX_DATA_BIT_END

TX_DATA_BIT_0:
                jsr     \DELAY_RTS

TX_DATA_BIT_END:
                ldx     #1
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4
                bbc     P41_FDB, PORT_P4, TX_BUS_ERROR
                dey
                bne     TX_DATA_NEXT_BIT
                ldy     #8              ; next byte
                ldx     ADB_COUNT
                lda     ADB_BUFFER-1, X ; X = 0 after the last byte: harmless dummy
                sta     ADB_SHIFT
                dec     ADB_COUNT
                bpl     TX_DATA_BIT
                nop
                seb     P40_PMGR_ADB, PORT_P4 ; stop bit
                ldx     #9
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4
                clc
                rts

;------------------------------------------------------------------------------
; ADB_RECEIVE_CMD - receive the answer to a Talk command
; There is no time to count bit times in a loop, so the line is sampled by
; long unrolled BBS/BBC chains, one test every 5 us:
;   RX_BIT: the line went low. Every slot it stays low moves the entry into
;     the RX_Hnn chain one step further (nn = low time / 5 us).
;   RX_Hnn: wait for the next falling edge. The longer the low time, the
;     fewer slots remain before RX_GOT_1, so the bit is '1' when the high time
;     is longer than the low time. Comparing the two halves of the cell makes
;     the decoder tolerant of devices with a slow or fast clock.
;   No falling edge at all: the stop bit has ended the packet.
; Bits are shifted into A behind a 1 sentinel. Pushing the bytes is the
; fastest way to store them, so S is moved to ADB_RX_STACK and the bytes land
; in $10, $0F, ... Afterwards they are copied to ADB_BUFFER in order.
; Each path that does extra work re-enters the chains a few slots later
; (RX_BIT_RESUME1/2, RX_H02) to keep the time base.
; In:  -
; Out: C = 0: ADB_BUFFER, ADB_COUNT = 2..8 bytes
;      C = 1: no answer, bad timing, or not 2..8 whole bytes
;             (ADBF_NO_DATA, ADBF_ERROR)
; Changes: A, X, Y, TEMP
;------------------------------------------------------------------------------
ADB_RECEIVE_CMD:
                ldm     #0, ADB_COUNT
                tsx
                stx     TEMP
                ldx     #ADB_RX_STACK
                txs
                lda     #1              ; sentinel
                ldy     #9              ; one more than the 8 allowed bytes
                ldx     #16             ; wait ~256 us (Tlt) for the start bit

RX_WAIT_START:
                bbc     P41_FDB, PORT_P4, RX_START_LOW
                dex
                bbc     P41_FDB, PORT_P4, RX_START_LOW
                bne     RX_WAIT_START
                bra     RX_FAIL

RX_FAIL:
                seb     ADBF_ERROR, ADB_FLAGS
                seb     ADBF_NO_DATA, ADB_FLAGS
                ldx     TEMP
                txs
                sec
                rts

RX_START_LOW:                           ; start bit '1': ~35 us low ...
                ldx     #3
                bbs     P41_FDB, PORT_P4, RX_FAIL ; glitch

RX_WAIT_START_HIGH:
                bbs     P41_FDB, PORT_P4, RX_START_HIGH
                dex
                bbs     P41_FDB, PORT_P4, RX_START_HIGH
                bne     RX_WAIT_START_HIGH
                bra     RX_FAIL

RX_START_HIGH:                          ; ... then ~65 us high
                nop
                nop
                nop
                nop
                bit     TEMP            ; delay
                bbc     P41_FDB, PORT_P4, RX_FAIL ; high too short
                bbc     P41_FDB, PORT_P4, RX_FAIL
                bbc     P41_FDB, PORT_P4, RX_FAIL
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bbc     P41_FDB, PORT_P4, RX_BIT
                bra     RX_FAIL         ; high too long

RX_BIT:                                 ; measure the low time
                bbs     P41_FDB, PORT_P4, RX_H00
                bbs     P41_FDB, PORT_P4, RX_H01

RX_BIT_RESUME1:
                bbs     P41_FDB, PORT_P4, RX_H02
                bbs     P41_FDB, PORT_P4, RX_H03

RX_BIT_RESUME2:
                bbs     P41_FDB, PORT_P4, RX_H04
                bbs     P41_FDB, PORT_P4, RX_H05
                bbs     P41_FDB, PORT_P4, RX_H06
                bbs     P41_FDB, PORT_P4, RX_H07
                bbs     P41_FDB, PORT_P4, RX_H08
                bbs     P41_FDB, PORT_P4, RX_H09
                bbs     P41_FDB, PORT_P4, RX_H10
                bbs     P41_FDB, PORT_P4, RX_H11
                bbs     P41_FDB, PORT_P4, RX_H12
                bbs     P41_FDB, PORT_P4, RX_H13
                bbs     P41_FDB, PORT_P4, RX_H14
                bbs     P41_FDB, PORT_P4, RX_H15
                bbs     P41_FDB, PORT_P4, RX_H16

RX_ABORT:                               ; low too long, or a bad end of packet
                jmp     RX_FAIL

RX_H16:                                 ; wait for the next falling edge
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H15:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H14:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H13:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H12:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H11:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H10:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H09:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H08:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H07:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H06:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H05:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H04:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H03:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H02:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H01:
                bbc     P41_FDB, PORT_P4, RX_GOT_0

RX_H00:
                bbc     P41_FDB, PORT_P4, RX_GOT_0
                bbc     P41_FDB, PORT_P4, RX_GOT_1 ; from here: high time > low time
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                bbc     P41_FDB, PORT_P4, RX_GOT_1
                cmp     #1              ; line stays high: that was the stop bit
                bne     RX_ABORT        ; partial byte
                cpy     #8
                bcs     RX_ABORT        ; fewer than 2 bytes
                bra     RX_DONE

RX_GOT_0:
                asl     A
                bcc     RX_NEXT_BIT
                pha                     ; sentinel shifted out: byte complete
                lda     #1
                bbs     P41_FDB, PORT_P4, RX_BYTE_HIGH
                dey
                beq     RX_OVERFLOW
                jmp     RX_BIT_RESUME2

RX_BYTE_HIGH:                           ; the line went high while storing
                dey
                beq     RX_OVERFLOW
                jmp     RX_H02

RX_OVERFLOW:                            ; more than 8 bytes
                jmp     RX_FAIL

RX_GOT_1:
                sec
                rol     A
                bcc     RX_NEXT_BIT
                pha
                lda     #1
                bbs     P41_FDB, PORT_P4, RX_BYTE_HIGH
                dey
                beq     RX_OVERFLOW
                jmp     RX_BIT_RESUME2

RX_NEXT_BIT:
                jmp     RX_BIT_RESUME1

RX_DONE:
                ldx     TEMP            ; back to the real stack
                txs
                tya                     ; ADB_COUNT = 9 - Y
                eor     #$FF
                clc
                adc     #10
                sta     ADB_COUNT
                tay
                beq     RX_RET
                ldx     #8              ; first byte is at ADB_BUFFER+8 = $10

RX_COPY_OUT:                            ; push them onto the real stack ...
                lda     ADB_BUFFER, X
                pha
                dex
                dey
                bne     RX_COPY_OUT
                ldx     ADB_COUNT

RX_COPY_BACK:                           ; ... and pop them back in order
                pla
                sta     ADB_BUFFER-1, X
                dex
                bne     RX_COPY_BACK

RX_RET:
                clc
                rts

;==============================================================================
; Host commands
;==============================================================================

; Handler for each command high nibble. Unused groups do nothing and send no
; reply.
COMMAND_TABLE:  WORD    COMMAND_xx_NOP
                WORD    COMMAND_1x_POWER
                WORD    COMMAND_2x_ADB
                WORD    COMMAND_3x_PRAM
                WORD    COMMAND_4x_CONTRAST
                WORD    COMMAND_5x_MODEM
                WORD    COMMAND_6x_BATTERY
                WORD    COMMAND_7x_SLEEP
                WORD    COMMAND_8x_TIMER
                WORD    COMMAND_9x_SOUND
                WORD    COMMAND_xx_NOP
                WORD    COMMAND_xx_NOP
                WORD    COMMAND_xx_NOP
                WORD    COMMAND_xx_NOP
                WORD    COMMAND_Ex_INTERNAL
                WORD    COMMAND_xx_NOP

COMMAND_xx_NOP:
                clc
                rts

;------------------------------------------------------------------------------
; COMMAND_1x_POWER - power plane control
; $10 powerCntl: one or more bytes. Bit 7 = 1 switches the planes in bits
;     0-6 on, bit 7 = 0 switches them off. P0 is active low except for the
;     -5 V enable (bit 6), so the two cases need different masks. SYS_PWR is
;     never switched off here: that is done by sleep only. No reply.
; $18 powerRead: reply 1 byte, 1 = plane on. Bit 5 is replaced by the sound
;     latch (IN2), because P05 is only the latch-clear strobe.
; In:  COMMAND, COMMAND_SIZE
; Out: PORT_P0, reply
; Changes: A, X, Y, TEMP
;------------------------------------------------------------------------------
COMMAND_1x_POWER:
                bbs     3, COMMAND, COMMAND_18_powerRead

COMMAND_10_powerCntl:
                tst     COMMAND_SIZE    ; READ_PARAMETER would read 256 bytes
                bne     POWER_CNTL_DATA
                rts

POWER_CNTL_DATA:
                lda     COMMAND_SIZE    ; READ_PARAMETER counts it down to 0
                pha
                jsr     READ_PARAMETER
                pla
                sta     COMMAND_SIZE
                ldx     #0

POWER_CNTL_LOOP:
                lda     PARAMETER, X
                bpl     POWER_CNTL_OFF
                eor     #$FF            ; on: clear the selected active-low bits ...
                and     PORT_P0
                sta     TEMP
                lda     PARAMETER, X
                and     #M_P06_neg5_EN
                ora     TEMP            ; ... and set -5 V if selected
                sta     PORT_P0
                bra     POWER_CNTL_NEXT

POWER_CNTL_NEXT:
                inx
                dec     COMMAND_SIZE
                bne     POWER_CNTL_LOOP
                clc
                rts

POWER_CNTL_OFF:                         ; off: set the selected active-low bits ...
                and     #~M_P07_SYS_PWR & $FF
                ora     PORT_P0
                sta     TEMP
                lda     PARAMETER, X
                and     #M_P06_neg5_EN
                eor     #~M_P07_SYS_PWR & $FF
                and     TEMP            ; ... clear -5 V if selected, keep SYS_PWR on
                sta     PORT_P0
                bra     POWER_CNTL_NEXT

COMMAND_18_powerRead:
                ldm     #1, COMMAND_SIZE
                lda     PORT_P0
                and     #~M_P07_SYS_PWR & $FF
                eor     #~(M_P06_neg5_EN|M_P07_SYS_PWR) & $FF ; active low -> 1 = on
                seb     5, A
                bbs     IN2_SOUND_LATCH, IN, POWER_READ_SEND
                clb     5, A

POWER_READ_SEND:
                sta     PARAMETER
                jsr     SEND_COMMAND_PARAMETER
                rts

;------------------------------------------------------------------------------
; COMMAND_28_readADB - return the last ADB result
; Reply: ADB_COMMAND, ADB_FLAGS, ADB_COUNT, data (these RAM bytes are in reply
; order, so they are sent straight from RAM).
; INT_ADB is only cleared if no /PMINT was sent since readINT; otherwise the
; host would miss an event that arrived in between.
; In:  ADB state
; Out: reply, INT_ADB
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_28_readADB:
                ldm     #0, PTR+1
                ldm     #ADB_COMMAND, PTR
                lda     ADB_COUNT
                clc
                adc     #3
                sta     COMMAND_SIZE
                jsr     SEND_COMMAND
                bcs     READ_ADB_DONE
                bbs     FLAG_PMINT_SENT, FLAGS, READ_ADB_DONE
                clb     INT_ADB, INT_STATE

READ_ADB_DONE:
                rts

;------------------------------------------------------------------------------
; COMMAND_2x_ADB
; $20 pMgrADB: ADB command, ADB_FLAGS (bit 2 = auto-poll), count, Listen data.
;     The command is only stored; MAIN_LOOP sends it, because the ADB timing
;     can't be interrupted by the host handshake. The data is stored in
;     reverse order for ADB_SEND_CMD. Because PARAMETER holds 8 bytes, only
;     up to 5 data bytes fit.
; $21 pMgrADBoff: stop auto-poll and drop a pending result.
; Other $2x are ignored ($28 is handled in MAIN_LOOP).
; In:  COMMAND, COMMAND_SIZE
; Out: ADB_COMMAND, ADB_FLAGS, ADB_BUFFER, ADB_COUNT, ADB_SEND_COUNT, INT_ADB
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_2x_ADB:
                lda     COMMAND
                cmp     #PM_pMgrADB
                beq     COMMAND_20_pMgrADB
                cmp     #PM_pMgrADBoff
                bne     ADB_UNKNOWN

COMMAND_21_pMgrADBoff:
                ldm     #0, ADB_FLAGS
                clb     INT_ADB, INT_STATE
                clc
                rts

COMMAND_20_pMgrADB:
                jsr     READ_PARAMETER
                clb     INT_ADB, INT_STATE
                lda     PARAMETER
                sta     ADB_COMMAND
                lda     PARAMETER+1
                sta     ADB_FLAGS
                seb     ADBF_PENDING, ADB_FLAGS
                ldy     #0
                ldx     PARAMETER+2
                beq     ADB_COPY_DONE

ADB_COPY_LOOP:
                lda     PARAMETER+3, Y
                sta     ADB_BUFFER-1, X
                iny
                dex
                bne     ADB_COPY_LOOP

ADB_COPY_DONE:
                sty     ADB_SEND_COUNT  ; kept for auto-poll repeats
                sty     ADB_COUNT
                clc
                rts

ADB_UNKNOWN:
                sec
                rts

;------------------------------------------------------------------------------
; COMMAND_3x_PRAM - clock and parameter RAM
; $30 timeWrite: 4 bytes, seconds since 1904 (big-endian). No reply.
; $31 pramWrite: 20 bytes of classic PRAM. The Portable keeps them in XPRAM
;     at $10-$1F and $08-$0B, where the larger Macs put them. No reply.
; $32 xPramWrite (and $33-$37): offset, count, data. No reply.
; $38 timeRead: reply 4 bytes.
; $39 pramRead: reply the 20 classic PRAM bytes.
; $3A xPramRead (and $3B-$3F): offset, count; reply count bytes.
; The XPRAM checksum is updated after every write so INIT can tell valid
; XPRAM from garbage. Offset and count are not checked.
; In:  COMMAND, COMMAND_SIZE
; Out: TIME_S, XPRAM, reply
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_3x_PRAM:
                bbs     3, COMMAND, COMMAND_3x_READ
                lda     COMMAND
                cmp     #PM_timeWrite
                bne     PRAM_WRITE_31_32

COMMAND_30_timeWrite:
                ldm     #TIME_S, PTR
                ldm     #0, PTR+1
                ldm     #4, COMMAND_SIZE
                jsr     READ_BYTES
                jsr     TIME_CALC_CHECKSUM
                sta     TIME_CHECKSUM
                rts

PRAM_WRITE_31_32:
                cmp     #PM_pramWrite
                bne     COMMAND_32_xPramWrite

COMMAND_31_pramWrite:
                ldm     #XPRAM_10, PTR
                ldm     #0, PTR+1
                ldm     #$10, COMMAND_SIZE
                jsr     READ_BYTES
                ldm     #XPRAM_08, PTR
                ldm     #4, COMMAND_SIZE
                jsr     READ_BYTES
                jsr     XPRAM_IS_VALID
                sta     XPRAM_CHKSUM
                rts

COMMAND_32_xPramWrite:
                ldm     #2, COMMAND_SIZE
                jsr     READ_PARAMETER
                lda     PARAMETER
                clc
                adc     #XPRAM
                sta     PTR
                ldm     #0, PTR+1
                lda     PARAMETER+1
                sta     COMMAND_SIZE
                jsr     READ_BYTES
                jsr     XPRAM_IS_VALID
                sta     XPRAM_CHKSUM
                rts

COMMAND_3x_READ:
                lda     COMMAND
                cmp     #PM_timeRead
                bne     PRAM_READ_39_3A

COMMAND_38_timeRead:
                ldm     #TIME_S, PTR
                ldm     #0, PTR+1
                ldm     #4, COMMAND_SIZE
                jsr     SEND_COMMAND
                rts

PRAM_READ_39_3A:
                cmp     #PM_pramRead
                bne     COMMAND_3A_xPramRead

COMMAND_39_pramRead:                    ; two blocks, so the header is sent by hand
                ldm     #0, PTR+1
                ldm     #XPRAM_10, PTR
                ldm     #$10, COMMAND_SIZE
                ldy     #0
                lda     COMMAND
                jsr     SEND_BYTE
                bcs     PRAM_READ_DONE
                lda     #$14            ; count = 20
                jsr     SEND_BYTE
                bcs     PRAM_READ_DONE
                jsr     SEND_BUFFER
                ldm     #XPRAM_08, PTR
                ldm     #4, COMMAND_SIZE
                ldy     #0
                jsr     SEND_BUFFER

PRAM_READ_DONE:
                rts

COMMAND_3A_xPramRead:
                ldm     #2, COMMAND_SIZE
                jsr     READ_PARAMETER
                lda     PARAMETER
                clc
                adc     #XPRAM
                sta     PTR
                ldm     #0, PTR+1
                lda     PARAMETER+1
                sta     COMMAND_SIZE
                jsr     SEND_COMMAND
                rts

;------------------------------------------------------------------------------
; XPRAM_IS_VALID - check the XPRAM checksum
; An all-zero XPRAM has a matching sum of 0 but is just cleared RAM, so it
; counts as invalid.
; In:  XPRAM, XPRAM_CHKSUM
; Out: A = 8-bit sum of the 128 bytes (to store a new checksum);
;      C = 0: valid, C = 1: invalid
; Changes: TEMP
;------------------------------------------------------------------------------
XPRAM_IS_VALID:
                txa
                pha
                ldx     #0
                lda     #0
                clc

XPRAM_SUM_LOOP:
                adc     XPRAM, X        ; the carry is added in as well
                inx
                bpl     XPRAM_SUM_LOOP
                sta     TEMP
                cmp     XPRAM_CHKSUM
                bne     XPRAM_INVALID
                sta     TEMP
                bne     XPRAM_VALID
                ldx     #0

XPRAM_ZERO_LOOP:
                ora     XPRAM, X
                bne     XPRAM_VALID
                inx
                bpl     XPRAM_ZERO_LOOP

XPRAM_INVALID:
                pla
                tax
                lda     TEMP
                sec
                rts

XPRAM_VALID:
                pla
                tax
                lda     TEMP
                clc
                rts

;------------------------------------------------------------------------------
; TIME_CALC_CHECKSUM - checksum of the clock
; Lets INIT detect a clock that was lost with the battery.
; In:  TIME_S
; Out: A = 8-bit sum of the 4 bytes
; Changes: C
;------------------------------------------------------------------------------
TIME_CALC_CHECKSUM:
                lda     #0
                clc
                adc     TIME_S
                adc     TIME_S+1
                adc     TIME_S+2
                adc     TIME_S+3
                rts

;------------------------------------------------------------------------------
; COMMAND_4x_CONTRAST - LCD contrast
; $40 setContrast: 1 byte, 0-31. No reply.
; $48 readContrast (and $49-$4F): reply 1 byte.
; In:  COMMAND, COMMAND_SIZE
; Out: CONTRAST, TIMER1, TIMER2, reply
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_4x_CONTRAST:
                bbc     3, COMMAND, COMMAND_40_setContrast

COMMAND_48_readContrast:
                lda     CONTRAST
                sta     PARAMETER
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts

COMMAND_40_setContrast:
                ldm     #1, COMMAND_SIZE
                jsr     READ_PARAMETER  ; falls through into SET_CONTRAST

;------------------------------------------------------------------------------
; SET_CONTRAST - set the contrast PWM
; The PWM output is high for TIMER1 and low for TIMER2 counts; the total of 66
; keeps the frequency constant, so only the duty cycle (2..64)/66 changes.
; In:  PARAMETER = contrast (bits 0-4 used)
; Out: CONTRAST, TIMER1, TIMER2; C = 0
; Changes: A, X
;------------------------------------------------------------------------------
SET_CONTRAST:
                lda     PARAMETER
                and     #$1F
                tax
                sta     CONTRAST
                lda     #66
                sec
                sbc     CONTRAST_TABLE, X
                sta     TIMER2
                lda     CONTRAST_TABLE, X
                sta     TIMER1
                clc
                rts

CONTRAST_TABLE: BYTE    2,  4,  6,  8, 10, 12, 14, 16
                BYTE    18, 20, 22, 24, 26, 28, 30, 32
                BYTE    34, 36, 38, 40, 42, 44, 46, 48
                BYTE    50, 52, 54, 56, 58, 60, 62, 64

;------------------------------------------------------------------------------
; COMMAND_5x_MODEM - internal modem
; $50 modemSet: bit 0 power on, bit 1 MODEM_A/B (P17), bit 2 wake on ring.
;     No reply.
; $58 modemRead (and $59-$5F): reply 1 byte: bit 0 power on, bit 1 MODEM_A/B,
;     bit 2 wake on ring, bit 3 modem installed, bit 4 ringing, bit 5 off hook.
;     The inputs are active low; the reply uses 1 = true.
; In:  COMMAND, COMMAND_SIZE
; Out: PORT_P0, PORT_P1, FLAG_RING_WAKEUP, reply
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_5x_MODEM:
                bbs     3, COMMAND, COMMAND_58_modemRead

COMMAND_50_modemSet:
                ldm     #1, COMMAND_SIZE
                jsr     READ_PARAMETER
                clb     FLAG_RING_WAKEUP, FLAGS
                bbc     2, PARAMETER, MODEM_SET_AB
                seb     FLAG_RING_WAKEUP, FLAGS

MODEM_SET_AB:
                bbc     1, PARAMETER, MODEM_AB_LOW
                seb     P17_MODEM_AB, PORT_P1
                bra     MODEM_SET_PWR

MODEM_AB_LOW:
                clb     P17_MODEM_AB, PORT_P1

MODEM_SET_PWR:
                bbc     0, PARAMETER, MODEM_PWR_OFF
                clb     P03_MODEM_PWR, PORT_P0
                clc
                rts

MODEM_PWR_OFF:
                seb     P03_MODEM_PWR, PORT_P0
                clc
                rts

COMMAND_58_modemRead:
                ldm     #0, PARAMETER
                bbs     P03_MODEM_PWR, PORT_P0, MODEM_RD_AB
                seb     0, PARAMETER

MODEM_RD_AB:
                bbc     P17_MODEM_AB, PORT_P1, MODEM_RD_RINGEN
                seb     1, PARAMETER

MODEM_RD_RINGEN:
                bbc     FLAG_RING_WAKEUP, FLAGS, MODEM_RD_INSTALLED
                seb     2, PARAMETER

MODEM_RD_INSTALLED:
                bbs     P43_MODEM_INS, PORT_P4, MODEM_RD_RING
                seb     3, PARAMETER

MODEM_RD_RING:
                bbs     P16_RING_DETECT, PORT_P1, MODEM_RD_HOOK
                seb     4, PARAMETER

MODEM_RD_HOOK:
                bbs     IN3_OFF_HOOK, IN, MODEM_RD_SEND
                seb     5, PARAMETER

MODEM_RD_SEND:
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts

;------------------------------------------------------------------------------
; COMMAND_6x_BATTERY - battery status
; $68 batteryRead: reply BAT_FLAGS, BAT_VOLTAGE, BAT_IN0 (sent straight from
;     RAM, which is in reply order).
; $69 batteryNow: same, but with a new unfiltered sample.
; Like readADB, the interrupt cause is only cleared if no newer /PMINT was
; sent; BATF_CHARGER_CHANGED is cleared with it because the host has now seen
; the change.
; In:  COMMAND
; Out: reply, INT_STATE, BAT_FLAGS
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_6x_BATTERY:
                lda     COMMAND
                cmp     #PM_batteryRead
                beq     COMMAND_68_batteryRead
                cmp     #PM_batteryNow
                bne     BATTERY_DONE

COMMAND_69_batteryNow:
                jsr     BATTERY_READ

COMMAND_68_batteryRead:
                ldm     #BAT_FLAGS, PTR
                ldm     #0, PTR+1
                ldm     #3, COMMAND_SIZE
                jsr     SEND_COMMAND
                bcs     BATTERY_DONE
                bbs     FLAG_PMINT_SENT, FLAGS, BATTERY_DONE
                clb     INT_BATT2, INT_STATE
                clb     INT_BATT, INT_STATE
                clb     BATF_CHARGER_CHANGED, BAT_FLAGS

BATTERY_DONE:
                rts

;------------------------------------------------------------------------------
; COMMAND_78_readINT - report the interrupt causes
; The host sends this after every /PMINT. Clearing FLAG_PMINT_SENT here lets
; readADB/batteryRead detect a /PMINT that comes after this point.
; INT_RESET is reported once.
; In:  INT_STATE
; Out: reply INT_STATE; INT_RESET and FLAG_PMINT_SENT cleared
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_78_readINT:
                lda     INT_STATE
                sta     PARAMETER
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                clb     INT_RESET, INT_STATE
                clb     FLAG_PMINT_SENT, FLAGS
                rts

;------------------------------------------------------------------------------
; COMMAND_7x_SLEEP - put the Portable to sleep
; $7F sleepReq: 4 bytes, must be 'MATT'. The signature keeps a stray command
; from switching the machine off. Reply: PM_SLEEP_ACK or PM_SLEEP_NAK as the
; command byte, count 0. On ACK the PMGR goes to sleep.
; Other $7x are ignored.
; In:  COMMAND, COMMAND_SIZE
; Out: reply; on success does not return (ENTER_SLEEP)
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_7x_SLEEP:
                lda     COMMAND
                cmp     #PM_sleepReq
                bne     SLEEP_REQ_FAIL

COMMAND_7F_sleepReq:
                ldm     #4, COMMAND_SIZE
                jsr     READ_PARAMETER
                ldm     #PM_SLEEP_ACK, COMMAND
                ldx     #4

SLEEP_REQ_CHECK:
                dex
                bmi     SLEEP_REQ_REPLY
                lda     aMATT, X
                cmp     PARAMETER, X
                beq     SLEEP_REQ_CHECK
                ldm     #PM_SLEEP_NAK, COMMAND

SLEEP_REQ_REPLY:
                ldm     #0, COMMAND_SIZE
                jsr     SEND_COMMAND
                bcs     SLEEP_REQ_FAIL  ; the host didn't see the ACK: stay awake
                lda     COMMAND
                cmp     #PM_SLEEP_ACK
                beq     ENTER_SLEEP

SLEEP_REQ_FAIL:
                sec
                rts

;------------------------------------------------------------------------------
; ENTER_SLEEP - power down and wait for a wake-up event
; Used for sleepReq, a dead battery and after a cold reset.
; Saves P0 (with SYS_PWR off) and P1 in PARAMETER, holds the 68000 in reset
; and switches every plane off. Each pass of the sleep loop pulses STOP_CLK.
; The loop calls TICK without waiting for IRQ_INT1_REQ, so the pulse must
; stop the PMGR's own clock until the next 60 Hz tick: the PMGR sleeps too.
; Wake-up events:
;   - a key press, but only after all keys were up once, so the key still
;     held from the sleep command doesn't wake the machine at once
;   - the alarm time
;   - a ring, if enabled
; Nothing wakes the machine while BATF_VERY_LOW is set.
; On wake-up the ports are restored, the PMGR waits until the key is
; released (so it doesn't reach the restarted keyboard controller), switches
; the system on and releases the keyboard controller and the 68000 1/30 s
; later. Waking by alarm or ring disables the alarm.
; The stack is reset because ENTER_SLEEP is also reached from deep inside
; CHECK_BATTERY; interrupts stay off until the end.
; In:  -
; Out: does not return, continues in MAIN_LOOP
;------------------------------------------------------------------------------
ENTER_SLEEP:
                clb     P42_DISP_BLANK, PORT_P4
                sei
                bit     IRQ_CTRL
                bpl     ENTER_SLEEP
                jsr     TICK
                ldx     #STACK_TOP
                txs

SLEEP_WAIT_TICK1:                       ; 1/30 s with the display blank before
                bit     IRQ_CTRL        ; the power goes
                bpl     SLEEP_WAIT_TICK1
                jsr     TICK

SLEEP_WAIT_TICK2:
                bit     IRQ_CTRL
                bpl     SLEEP_WAIT_TICK2
                jsr     TICK

                seb     P05_SOUND_LATCH_CLR, PORT_P0
                clb     P05_SOUND_LATCH_CLR, PORT_P0
                lda     PORT_P0
                seb     P07_SYS_PWR, A  ; restore the planes later, but not SYS_PWR
                sta     PARAMETER
                lda     PORT_P1
                sta     PARAMETER+1
                clb     P33_SOUND_ON, PORT_P3
                clb     PWM_EN, PWM_CTRL
                clb     P31_SYS_RST, PORT_P3

                clb     FLAG_AKD_IDLE_SEEN, FLAGS
                seb     FLAG_SLEEPING, FLAGS
                ldm     #M_P00_IWM_CNTRL|M_P01_SCC_CNTRL|M_P02_HD_PWR|M_P03_MODEM_PWR|M_P04_SERIAL_PWR|M_P07_SYS_PWR, PORT_P0
                                        ; all planes off
                bra     SLEEP_STOP_CLK

SLEEP_LOOP:
                jsr     TICK
                bbs     P11_AKD, PORT_P1, SLEEP_STOP_CLK
                seb     FLAG_AKD_IDLE_SEEN, FLAGS

SLEEP_STOP_CLK:
                clb     P12_STOP_CLK, PORT_P1 ; halt until the next tick
                seb     P12_STOP_CLK, PORT_P1
                bbs     BATF_VERY_LOW, BAT_FLAGS, SLEEP_LOOP
                bbc     FLAG_AKD_IDLE_SEEN, FLAGS, SLEEP_CHECK_ALARM
                bbs     P11_AKD, PORT_P1, WAKE

SLEEP_CHECK_ALARM:
                bbs     FLAG_ALARM_HIT, FLAGS, WAKE_ALARM_RING
                bbc     FLAG_RING_WAKEUP, FLAGS, SLEEP_LOOP
                bbs     P16_RING_DETECT, PORT_P1, SLEEP_LOOP

WAKE_ALARM_RING:
                sei
                clb     IRQ_INT1_REQ, IRQ_CTRL
                clb     FLAG_ALARM_HIT, FLAGS
                clb     FLAG_ALARM_SET, FLAGS

WAKE:
                sei
                clb     FLAG_SLEEPING, FLAGS

                lda     ADB_FLAGS       ; resume auto-poll, nothing else
                and     #4
                sta     ADB_FLAGS

                lda     PARAMETER
                sta     PORT_P0
                lda     PARAMETER+1
                sta     PORT_P1

WAKE_KEY_RELEASE:                       ; keep the clock running while waiting
                bit     IRQ_CTRL
                bpl     WAKE_CHECK_KEY
                jsr     TICK

WAKE_CHECK_KEY:
                bbs     P11_AKD, PORT_P1, WAKE_KEY_RELEASE

                clb     P07_SYS_PWR, PORT_P0
                clb     P14_KBD_RST, PORT_P1
                seb     PWM_EN, PWM_CTRL
                seb     P42_DISP_BLANK, PORT_P4

                ldx     #2              ; presumably lets the power settle (1/30 s)

WAKE_WAIT_TICKS:
                bit     IRQ_CTRL
                bpl     WAKE_WAIT_TICKS
                jsr     TICK
                dex
                bne     WAKE_WAIT_TICKS

                seb     P14_KBD_RST, PORT_P1
                seb     P31_SYS_RST, PORT_P3
                clb     IRQ_INT2_REQ, IRQ_CTRL
                seb     IRQ_INT2_EN, IRQ_CTRL
                cli

                jmp     MAIN_LOOP

;------------------------------------------------------------------------------
; COMMAND_8x_TIMER - wake-up alarm
; $80 timerSet: 4 bytes (seconds since 1904), enables the alarm. No reply.
; $82 timerDisable. No reply.
; $88 timerRead (and every other $8x): reply 4 bytes + 1 byte (bit 0 = on).
; In:  COMMAND
; Out: ALARM_TIME, FLAG_ALARM_SET, reply
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_8x_TIMER:
                lda     COMMAND
                cmp     #PM_timerSet
                bne     TIMER_NOT_SET

COMMAND_80_timerSet:
                bbs     3, COMMAND, COMMAND_88_timerRead ; never taken
                ldm     #4, COMMAND_SIZE
                ldm     #ALARM_TIME, PTR
                ldm     #0, PTR+1
                jsr     READ_BYTES
                seb     FLAG_ALARM_SET, FLAGS
                rts

TIMER_NOT_SET:
                cmp     #PM_timerDisable
                bne     COMMAND_88_timerRead
                clb     FLAG_ALARM_SET, FLAGS
                rts

COMMAND_88_timerRead:
                ldm     #5, COMMAND_SIZE
                lda     ALARM_TIME
                sta     PARAMETER
                lda     ALARM_TIME+1
                sta     PARAMETER+1
                lda     ALARM_TIME+2
                sta     PARAMETER+2
                lda     ALARM_TIME+3
                sta     PARAMETER+3
                ldm     #0, PARAMETER+4
                bbc     FLAG_ALARM_SET, FLAGS, TIMER_READ_SEND
                seb     0, PARAMETER+4

TIMER_READ_SEND:
                jsr     SEND_COMMAND_PARAMETER
                rts

;------------------------------------------------------------------------------
; COMMAND_9x_SOUND - sound power and the sound latch
; $90 soundSet: bit 0 = sound on (P33), bit 1 = 1 clears the sound latch.
;     No reply.
; $98 soundRead (and $99-$9F): reply 1 byte: bit 0 = sound on,
;     bit 1 = sound latch (IN2 low).
; In:  COMMAND, COMMAND_SIZE
; Out: PORT_P3, reply
; Changes: A, X, Y
;------------------------------------------------------------------------------
COMMAND_9x_SOUND:
                bbs     3, COMMAND, COMMAND_98_soundRead

COMMAND_90_soundSet:
                ldm     #1, COMMAND_SIZE
                jsr     READ_PARAMETER
                bbc     0, PARAMETER, SOUND_SET_OFF
                seb     P33_SOUND_ON, PORT_P3
                bra     SOUND_SET_LATCH

SOUND_SET_OFF:
                clb     P33_SOUND_ON, PORT_P3

SOUND_SET_LATCH:
                bbc     1, PARAMETER, SOUND_DONE
                seb     P05_SOUND_LATCH_CLR, PORT_P0
                clb     P05_SOUND_LATCH_CLR, PORT_P0

SOUND_DONE:
                rts

COMMAND_98_soundRead:
                ldm     #0, PARAMETER
                bbc     P33_SOUND_ON, PORT_P3, SOUND_RD_LATCH
                seb     0, PARAMETER

SOUND_RD_LATCH:
                bbs     IN2_SOUND_LATCH, IN, SOUND_RD_SEND
                seb     1, PARAMETER

SOUND_RD_SEND:
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts

;------------------------------------------------------------------------------
; COMMAND_Ex_INTERNAL - PMGR maintenance
; $EF PmgrSoftReset: echo the command, then re-initialise the ports through
;     INIT_PORTS. The stack is not reset and A and Y hold leftover values
;     (A = 0 for a command without data: all planes on, -5 V off).
; $EC PmgrSelfTest: reply 1 byte, 1 = failed: bit 0 ROM checksum, bit 1 RAM
;     address lines, bit 2 RAM read/write.
; $EA readPmgrVers: reply ROM_VERSION (2 bytes).
; $E0 writePmgrRAM: address hi, lo, data. No reply.
; $E8 readPmgrRAM (and every other $Ex): address hi, lo, count; reply count
;     bytes. Both work on any 16-bit address, including the ROM and the SFRs.
;     With only the 2 address bytes nothing is done and no reply is sent.
; In:  COMMAND, COMMAND_SIZE
; Out: reply
; Changes: A, X, Y, TEMP
;------------------------------------------------------------------------------
COMMAND_Ex_INTERNAL:
                lda     COMMAND
                cmp     #PM_PmgrSoftReset
                bne     EX_NOT_EF

COMMAND_EF_PmgrSoftReset:
                jsr     SEND_COMMAND
                bcs     COMMAND_E0_fail
                jmp     INIT_PORTS

EX_NOT_EF:
                cmp     #PM_PmgrSelfTest
                bne     EX_NOT_EC

COMMAND_EC_PmgrSelfTest:                ; each test returns its result in C,
                ldm     #0, PARAMETER   ; which is rotated in at bit 7 and ends up
                jsr     CHECK_ROM_CHECKSUM ; in bits 0-2 after 8 rotations
                ror     PARAMETER
                jsr     CHECK_RAM_BITS
                ror     PARAMETER
                jsr     CHECK_RAM_RW
                ror     PARAMETER
                ror     PARAMETER
                ror     PARAMETER
                ror     PARAMETER
                ror     PARAMETER
                ror     PARAMETER
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts

EX_NOT_EC:
                cmp     #PM_readPmgrVers
                bne     COMMAND_E0_E8_PmgrRAM

COMMAND_EA_readPmgrVers:
                lda     ROM_VERSION
                sta     PARAMETER
                lda     ROM_VERSION+1
                sta     PARAMETER+1
                ldm     #2, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts

COMMAND_E0_E8_PmgrRAM:
                lda     COMMAND_SIZE
                sta     TEMP
                jsr     READ_PARAMETER
                lda     PARAMETER       ; the address is sent high byte first
                sta     PTR+1
                lda     PARAMETER+1
                sta     PTR
                ldx     TEMP
                beq     COMMAND_E0_fail
                dex
                beq     COMMAND_E0_fail
                dex                     ; X = number of data bytes
                beq     COMMAND_E0_success
                lda     COMMAND
                cmp     #PM_writePmgrRAM
                bne     COMMAND_E8_readPmgrRAM

COMMAND_E0_writePmgrRAM:
                ldy     #0

COMMAND_E0_LOOP:
                lda     PARAMETER+2, Y
                sta     (PTR), Y
                iny
                dex
                bne     COMMAND_E0_LOOP

COMMAND_E0_success:
                clc
                rts

COMMAND_E0_fail:
                sec
                rts

COMMAND_E8_readPmgrRAM:
                ldx     PARAMETER+2
                beq     RAM_READ_NONE
                stx     COMMAND_SIZE

RAM_READ_SEND:
                jsr     SEND_COMMAND
                rts

RAM_READ_NONE:
                ldm     #0, COMMAND_SIZE
                bra     RAM_READ_SEND

;==============================================================================
; Self test (PmgrSelfTest)
;==============================================================================

;------------------------------------------------------------------------------
; CHECK_ROM_CHECKSUM - verify the ROM
; Each byte is added to A (a carry increments PARAMETER+1), then the pair
; A/PARAMETER+1 is rotated left by one bit (A bit 7 -> PARAMETER+1 bit 0,
; PARAMETER+1 bit 7 -> A bit 0). The rotation makes the sum depend on the
; byte order. The checksum bytes themselves ($E804/5) are skipped. The test
; takes longer than a tick, so TICK is called between pages to keep the clock
; right.
; In:  -
; Out: C = 0: ROM_CHECKSUM matches, C = 1: it doesn't
; Changes: A, X, Y, PTR, PARAMETER+1, PARAMETER+2
;------------------------------------------------------------------------------
CHECK_ROM_CHECKSUM:
                lda     #>VECTOR_RESET
                sta     PTR+1
                ldy     #6              ; start at $E806
                lda     #0
                sta     PARAMETER+1
                sta     PTR

ROM_SUM_LOOP:
                clc
                adc     (PTR), Y
                bcc     ROM_SUM_NO_CARRY
                inc     PARAMETER+1

ROM_SUM_NO_CARRY:
                cmp     #$80            ; C = bit 7 of A
                rol     PARAMETER+1
                rol     A
                iny
                bne     ROM_SUM_LOOP

                bit     IRQ_CTRL
                bpl     ROM_SUM_NEXT_PAGE
                sta     PARAMETER+2
                jsr     TICK
                lda     PARAMETER+2
                ldy     #0

ROM_SUM_NEXT_PAGE:
                inc     PTR+1
                bne     ROM_SUM_LOOP
                ldx     PARAMETER+1
                tay
                ora     PARAMETER+1
                bne     ROM_SUM_COMPARE
                dex                     ; a result of 0 becomes $FF,$FF
                dey

ROM_SUM_COMPARE:
                cpx     ROM_CHECKSUM
                bne     ROM_SUM_FAIL
                cpy     ROM_CHECKSUM+1
                bne     ROM_SUM_FAIL
                clc
                rts

ROM_SUM_FAIL:
                sec
                rts

;------------------------------------------------------------------------------
; CHECK_RAM_BITS - test the RAM address lines
; Each of the addresses $00, $01, $02, $04 ... $80 gets a different pattern.
; A broken or shorted address line would map two of them onto the same cell,
; so one pattern overwrites another. The test is repeated with the inverted
; patterns. The old contents are saved and restored because these addresses
; hold live variables; interrupts are off meanwhile.
; In:  -
; Out: C = 0: ok, C = 1: failed; the I flag is unchanged
; Changes: A, X, Y, PARAMETER+1 .. PARAMETER+9
;------------------------------------------------------------------------------
CHECK_RAM_BITS:
                php
                sei
                sec                     ; result if a compare fails
                ldy     #8

RAM_BITS_SAVE:
                ldx     CHECK_RAM_ADR_TAB, Y
                lda     0, X
                sta     PARAMETER+1, Y
                dey
                bpl     RAM_BITS_SAVE
                ldy     #8

RAM_BITS_WRITE:
                lda     CHECK_RAM_DATA_TAB, Y
                ldx     CHECK_RAM_ADR_TAB, Y
                sta     0, X
                dey
                bpl     RAM_BITS_WRITE
                ldy     #8

RAM_BITS_VERIFY:
                lda     CHECK_RAM_DATA_TAB, Y
                ldx     CHECK_RAM_ADR_TAB, Y
                eor     0, X
                bne     RAM_BITS_RESTORE_INIT
                dey
                bpl     RAM_BITS_VERIFY
                ldy     #8

RAM_BITS_WRITE_INV:
                lda     CHECK_RAM_DATA_TAB, Y
                eor     #$FF
                ldx     CHECK_RAM_ADR_TAB, Y
                sta     0, X
                dey
                bpl     RAM_BITS_WRITE_INV
                ldy     #8

RAM_BITS_VERIFY_INV:
                lda     CHECK_RAM_DATA_TAB, Y
                eor     #$FF
                ldx     CHECK_RAM_ADR_TAB, Y
                eor     0, X
                bne     RAM_BITS_RESTORE_INIT
                dey
                bpl     RAM_BITS_VERIFY_INV
                clc

RAM_BITS_RESTORE_INIT:
                ldy     #8

RAM_BITS_RESTORE:
                ldx     CHECK_RAM_ADR_TAB, Y
                lda     PARAMETER+1, Y
                sta     0, X
                dey
                bpl     RAM_BITS_RESTORE
                rol     A               ; park C in A while PLP restores the flags
                plp
                ror     A
                rts

CHECK_RAM_ADR_TAB:  BYTE $00,$01,$02,$04,$08,$10,$20,$40,$80
CHECK_RAM_DATA_TAB: BYTE $F0,$E1,$D2,$C3,$B4,$A5,$96,$87,$78

;------------------------------------------------------------------------------
; CHECK_RAM_RW - test every RAM bit
; Walks a single 1 (and, inverted, a single 0) through each byte from $BF down
; to $00, then writes $00/$FF. Each byte is restored right away, so the test
; can run over live data and the stack. TICK is called between bytes to keep
; the clock right.
; In:  -
; Out: C = 0: ok, C = 1: failed
; Changes: A, X, Y, PARAMETER+2
;------------------------------------------------------------------------------
CHECK_RAM_RW:
                ldx     #RAM_END

RAM_RW_NEXT:
                dex
                cpx     #$FF
                beq     RAM_RW_OK
                ldy     0, X            ; save the byte
                lda     #0
                sec

RAM_RW_BIT:
                rol     A
                sta     0, X
                cmp     0, X
                bne     RAM_RW_FAIL
                eor     #$FF
                sta     0, X
                cmp     0, X
                bne     RAM_RW_FAIL
                eor     #$FF
                clc
                bne     RAM_RW_BIT
                sty     0, X
                bit     IRQ_CTRL
                bpl     RAM_RW_NEXT
                stx     PARAMETER+2
                jsr     TICK
                ldx     PARAMETER+2
                bra     RAM_RW_NEXT

RAM_RW_OK:
                clc
                rts

RAM_RW_FAIL:
                sty     0, X
                sec
                rts

;==============================================================================
; Interrupt vectors
;==============================================================================

;------------------------------------------------------------------------------
; VECTOR_INT2_RESET - reset switch (the only enabled interrupt)
; Holds the 68000 in reset until the switch is released, but at least 2
; ticks, so it restarts cleanly once, then does a warm reset. It never
; returns; INIT resets the stack.
; In:  -
; Out: does not return, continues in WARM_RESET
;------------------------------------------------------------------------------
VECTOR_INT2_RESET:
                nop
                clb     P31_SYS_RST, PORT_P3

INT2_WAIT_TICK:
                bit     IRQ_CTRL
                bpl     INT2_WAIT_TICK
                jsr     TICK

INT2_WAIT_RELEASE:
                bit     IRQ_CTRL
                bpl     INT2_WAIT_RELEASE
                jsr     TICK

                bbc     P30_RESET, PORT_P3, INT2_WAIT_RELEASE

                jmp     WARM_RESET

; These interrupts are never enabled; INT1 (60 Hz) is polled instead.
VECTOR_TIMER2:
                rti

VECTOR_TIMER1:
                rti

VECTOR_TIMERX:
                rti

VECTOR_INT1:
                rti

                BLKB    3008            ; unused, zero-filled

;------------------------------------------------------------------------------
; Delays in the special page $FF00, called with the 2-byte JSR \xx. The ADB
; code calls them often, so the short call saves ROM.
; DELAY_LOOP_X: 6*X + 9 cycles including the JSR (X = 0: 256 loops, 1545 us)
;   In: X   Out: X = 0
; DELAY_RTS: 11 cycles (JSR + RTS)
; DELAY_SMALL: not used
;------------------------------------------------------------------------------
DELAY_SMALL:
                ldx     #3

DELAY_LOOP_X:
                dex
                bne     DELAY_LOOP_X

DELAY_RTS:
                rts

                BLKB    238             ; unused, zero-filled

                WORD    VECTOR_INT2_RESET ; $FFF4 INT2 / BRK
                WORD    VECTOR_TIMER2   ; $FFF6 timer 2 / serial I/O
                WORD    VECTOR_TIMER1   ; $FFF8 timer 1 / A-D
                WORD    VECTOR_TIMERX   ; $FFFA timer X
                WORD    VECTOR_INT1     ; $FFFC INT1
                WORD    VECTOR_RESET    ; $FFFE reset

                END
