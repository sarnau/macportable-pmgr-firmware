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
; Timing: the only clock is INT1 (60.15 Hz from the main logic board). Its
; interrupt is never enabled; the request bit is polled everywhere with
;     bit IRQ_CTRL / bpl ...     (N = bit 7 = IRQ_INT1_REQ)
; followed by "jsr TICK". The only enabled interrupt is INT2 (reset switch).

;------------------------------------------------------------------------------
; Host commands. Bits 7-4 index COMMAND_TABLE, bit 3 is usually read (1) /
; write (0).
;------------------------------------------------------------------------------
PM_powerCntl:      EQU $10      ; switch power planes on/off
PM_powerRead:      EQU $18      ; read power plane state
PM_pMgrADB:        EQU $20      ; send an ADB command (and set auto-poll)
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
FLAG_ALARM_HIT:    EQU 5        ; wakeup time reached (checked only while asleep)
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
ADBF_NO_DATA:      EQU 4        ; no valid answer, ADB reset sent, or send failed
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
P05_SOUND_PWR:     EQU 5        ; pulsed 1-0 to clear the sound latch
P06_neg5_EN:       EQU 6        ; -5 V enable (active high)
P07_SYS_PWR:       EQU 7        ; main system power
M_P00_IWM_CNTRL:   EQU $01
M_P01_SCC_CNTRL:   EQU $02
M_P02_HD_PWR:      EQU $04
M_P03_MODEM_PWR:   EQU $08
M_P04_SERIAL_PWR:  EQU $10
M_P05_SOUND_PWR:   EQU $20
M_P06_neg5_EN:     EQU $40
M_P07_SYS_PWR:     EQU $80

; Port P1 ($E2)
P10_N_C:           EQU 0        ; not connected, set by TICK in test mode
P11_AKD:           EQU 1        ; in: any key down (from the keyboard controller)
P12_STOP_CLK:      EQU 2        ; out: STOP_CLK to the GLU, pulsed while asleep
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
P33_SOUND_OFF:     EQU 3        ; out: sound control, set by soundSet bit 0
P34_1SEC:          EQU 4        ; out: 1 Hz pulse to VIA CA1
P35_PMINT:         EQU 5        ; out: /PMINT pulse to VIA CB1
P36_PMACK:         EQU 6        ; out: handshake to the VIA
P37_PMREQ:         EQU 7        ; in:  handshake from the VIA
M_P30_RESET:       EQU $01
M_P31_SYS_RST:     EQU $02
M_P32_VIA_TEST:    EQU $04
M_P33_SOUND_OFF:   EQU $08
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
TIMER_12_PRES:  BLKB 1          ; $F9 timer 1/2 prescaler (PWM clock)
TIMER1:         BLKB 1          ; $FA PWM high time
TIMER2:         BLKB 1          ; $FB PWM low time
TIMERX_PRES:    BLKB 1          ; $FC
TIMERX:         BLKB 1          ; $FD
IRQ_CTRL:       BLKB 1          ; $FE IRQ_xxx
TIMER_CTRL:     BLKB 1          ; $FF

;==============================================================================
; ROM
;==============================================================================
                RSEG ROM
                ORG $E800

;------------------------------------------------------------------------------
; Power-on reset ($FFFE): jump over the ROM header.
;------------------------------------------------------------------------------
VECTOR_RESET:
                bra     RESET
ROM_VERSION:    BYTE    2,181           ; $02,$B5, returned by readPmgrVers
ROM_CHECKSUM:   BYTE    $76,$44         ; $7644 (big-endian), see CHECK_ROM_CHECKSUM
aMATT:          BYTE    'M','A','T','T' ; signature required by sleepReq
aBUGS:          BYTE    'B','u','g','s'
                BYTE    $A8             ; Mac Roman (c)
aCopyrightApple:BYTE    "Copyright Apple Computer Inc  1987, 1988, 1989 Written by Micha"
                BYTE    "el Hanlon "

RESET:
                ldy     #M_INT_RESET    ; cold reset: report INT_RESET to the host
                bra     INIT

;------------------------------------------------------------------------------
; Initialisation
;   Y = M_INT_RESET: cold reset (power-on). All planes off; with P32 high the
;                    machine then goes straight to sleep and waits for a key.
;   Y = 0:           warm reset (reset/interrupt switch, VECTOR_INT2_RESET).
;                    Power stays on, the hard disk keeps its state.
; XPRAM and the clock survive a reset as long as their checksums are valid.
;------------------------------------------------------------------------------
WARM_RESET:
                ldy     #0

INIT:
                ldx     #STACK_TOP
                txs
                clt
                sei
                cld

                jsr     XPRAM_IS_VALID
                bcc     INIT_XPRAM_OK
                ldx     #0              ; invalid: clear all 128 bytes
                lda     #0

INIT_XPRAM_CLR:
                sta     XPRAM, X
                inx
                bpl     INIT_XPRAM_CLR
                sta     BAT_FLAGS
                sta     BAT_HICHG_STATE
                ldm     #78, XPRAM_BAT_LOW  ; default battery levels
                ldm     #62, XPRAM_BAT_DEAD
                ldm     #200, XPRAM_44
                jsr     XPRAM_IS_VALID  ; A = sum
                sta     XPRAM_CHKSUM

INIT_XPRAM_OK:
                lda     #0
                sta     FLAGS
                sta     ADB_FLAGS

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
                lda     PORT_P0         ; warm: all planes on, -5 V on, HD unchanged
                and     #M_P02_HD_PWR
                ora     #M_P06_neg5_EN
                sty     INT_STATE

                tst     INT_STATE
                beq     INIT_PORTS
                lda     #M_P00_IWM_CNTRL|M_P01_SCC_CNTRL|M_P02_HD_PWR|M_P03_MODEM_PWR|M_P04_SERIAL_PWR|M_P07_SYS_PWR
                                        ; cold: all planes off

INIT_PORTS:                             ; also entered by PmgrSoftReset
                sta     PORT_P0
                ldm     #0b11111111, PORT_P0_DIR
                ldm     #M_P10_N_C|M_P16_RING_DETECT|M_P17_MODEM_AB, PORT_P1
                ldm     #0b10110101, PORT_P1_DIR
                ldm     #0b11111111, PORT_P2
                ldm     #0b00000000, PORT_P2_DIR
                ldm     #M_P30_RESET|M_P32_VIA_TEST|M_P34_1SEC|M_P35_PMINT|M_P36_PMACK|M_P37_PMREQ, PORT_P3
                ldm     #0b01111010, PORT_P3_DIR
                ldm     #M_P41_FDB|M_P42_DISP_BLANK|M_P43_MODEM_INS, PORT_P4
                ldm     #0b00000101, PORT_P4_DIR

                ldm     #0, TIMER_CTRL
                ldm     #0, IRQ_CTRL    ; all interrupts off
                ldm     #4, TIMER_12_PRES
                ldm     #1, TIMERX_PRES
                ldm     #1, TIMERX_PRES ; sic, written twice (timer X is not used)

                lda     CONTRAST        ; contrast must be 1..31, else 4
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

                jsr     BATTERY_READ
                seb     P14_KBD_RST, PORT_P1 ; release the keyboard controller

                cpy     #0
                beq     INIT_RUN        ; warm reset
                bbc     P32_VIA_TEST, PORT_P3, INIT_RUN
                jmp     ENTER_SLEEP     ; cold reset: stay off until a key is pressed

INIT_RUN:
                ldx     #2              ; wait 2 ticks (1/30 s)

INIT_WAIT_TICK:
                bit     IRQ_CTRL
                bpl     INIT_WAIT_TICK
                jsr     TICK
                dex
                bne     INIT_WAIT_TICK

                seb     P31_SYS_RST, PORT_P3 ; release the 68000 reset
                seb     P05_SOUND_PWR, PORT_P0 ; clear the sound latch
                clb     P05_SOUND_PWR, PORT_P0
                clb     IRQ_INT2_REQ, IRQ_CTRL
                seb     IRQ_INT2_EN, IRQ_CTRL ; enable the reset/interrupt switch
                cli

;------------------------------------------------------------------------------
; Main loop. Polls for
;   - the 60 Hz tick: clock, alarm and battery (TICK), ADB auto-poll, /PMINT
;   - a new pMgrADB command: sent at once
;   - PMREQ low: the host sends a command
; While the PMGR is busy with a tick or ADB it drives $07 onto the data bus.
;------------------------------------------------------------------------------
MAIN_LOOP:
                ldm     #0, PORT_P2_DIR ; data bus: input

MAIN_POLL:
                bit     IRQ_CTRL
                bmi     MAIN_TICK

                bbs     ADBF_PENDING, ADB_FLAGS, MAIN_DO_ADB
                bbs     P37_PMREQ, PORT_P3, MAIN_POLL

                jsr     READ_COMMAND
                bcs     MAIN_LOOP

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
                bbs     INT_ADB, INT_STATE, MAIN_CHECK_INT ; last result not read yet
                bbs     ADBF_PENDING, ADB_FLAGS, MAIN_DO_ADB
                bbc     ADBF_AUTOPOLL, ADB_FLAGS, MAIN_CHECK_INT

MAIN_DO_ADB:                            ; new command or auto-poll
                ldm     #7, PORT_P2
                ldm     #$FF, PORT_P2_DIR

                lda     ADB_FLAGS       ; keep the host bits 0 and 2
                and     #0b00000101
                sta     ADB_FLAGS
                lda     ADB_SEND_COUNT
                sta     ADB_COUNT
                lda     ADB_COMMAND
                and     #$F
                bne     MAIN_ADB_SEND
                seb     P40_PMGR_ADB, PORT_P4 ; command $x0: ADB reset, line low
                ldx     #0              ; for 3 x 1545 us = 4.6 ms (spec >= 3 ms)
                jsr     \DELAY_LOOP_X
                jsr     \DELAY_LOOP_X
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4
                seb     ADBF_NO_DATA, ADB_FLAGS
                bra     MAIN_ADB_DONE

MAIN_ADB_SEND:
                jsr     ADB_SEND_CMD
                bcc     MAIN_ADB_RECEIVE
                seb     ADBF_NO_DATA, ADB_FLAGS
                bra     MAIN_ADB_DONE

MAIN_ADB_RECEIVE:
                jsr     ADB_RECEIVE_CMD
                bcc     MAIN_ADB_DONE   ; got data
                bbc     ADBF_AUTOPOLL, ADB_FLAGS, MAIN_ADB_DONE
                bbc     ADBF_SRQ, ADB_FLAGS, MAIN_CHECK_INT ; auto-poll, no answer, no SRQ: quiet

MAIN_ADB_DONE:
                seb     INT_ADB, INT_STATE

MAIN_CHECK_INT:
                lda     INT_STATE
                and     #M_INT_ADB|M_INT_BATT|M_INT_BATT2
                beq     MAIN_NEXT
                clb     P35_PMINT, PORT_P3 ; pulse /PMINT
                seb     FLAG_PMINT_SENT, FLAGS
                seb     P35_PMINT, PORT_P3

MAIN_NEXT:
                jmp     MAIN_LOOP

;------------------------------------------------------------------------------
; Host interface
;   READ_COMMAND    COMMAND, COMMAND_SIZE
;   READ_PARAMETER  COMMAND_SIZE bytes to PARAMETER (the count is not checked!)
;   READ_BYTES      COMMAND_SIZE bytes to (PTR)
; Carry set = handshake timeout.
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

; Receive one byte: wait up to ~45 us for PMREQ low, read the bus, PMACK low,
; wait up to ~45 us for PMREQ high, PMACK high.
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

; Send COMMAND, COMMAND_SIZE and COMMAND_SIZE data bytes
;   SEND_COMMAND_PARAMETER  data from PARAMETER
;   SEND_COMMAND            data from (PTR)
;   SEND_BUFFER             data only, from (PTR),Y
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

; Send one byte: PMREQ must be high, drive the bus, PMACK low (data valid),
; wait up to ~4 ms for PMREQ low, PMACK high, release the bus.
SEND_BYTE:
                bbc     P37_PMREQ, PORT_P3, SB_TIMEOUT
                ldm     #$FF, PORT_P2_DIR
                sta     PORT_P2
                clb     P36_PMACK, PORT_P3
                bbc     P37_PMREQ, PORT_P3, SB_OK
                ldx     #0

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
; Battery check, called every tick (also while asleep)
;   - charger plugged in or removed: BATF_CHARGER_CHANGED + INT_BATT
;   - charger connected: high-rate charge state machine
;   - on battery: compare the voltage with the XPRAM levels. LOW and DEAD must
;     be 59..89 with LOW >= DEAD, else the defaults are restored. INT_BATT is
;     set on every tick while the voltage is below LOW.
;     Dead battery while awake (and P32 high): ENTER_SLEEP.
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
                lda     BAT_FLAGS       ; BATF_CHARGER (moved to bit 3) XOR P13
                asl     A
                asl     A
                asl     A
                eor     PORT_P1
                bbs     P13_CHRG_ON, A, BAT_CHARGER_SAME ; 1 = unchanged
                seb     INT_BATT, INT_STATE
                seb     BATF_CHARGER_CHANGED, BAT_FLAGS
                jsr     BATTERY_READ

BAT_CHARGER_SAME:
                clb     BATF_CHARGER, BAT_FLAGS
                clb     BATF_DEAD, BAT_FLAGS
                clb     BATF_VERY_LOW, BAT_FLAGS
                bbc     P13_CHRG_ON, PORT_P1, BAT_CHARGER

                lda     XPRAM_BAT_LOW   ; validate the levels
                cmp     #90
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
                clb     BATF_LOW, BAT_FLAGS
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
                jmp     ENTER_SLEEP     ; dead battery: shut down

BAT_HICHG_RESTART:
                ldm     #HICHG_START, BAT_HICHG_STATE
                rts

BAT_DEFAULT_LEVELS:
                ldm     #78, XPRAM_BAT_LOW
                ldm     #62, XPRAM_BAT_DEAD
                ldm     #200, XPRAM_44
                jsr     XPRAM_IS_VALID
                sta     XPRAM_CHKSUM
                bra     BAT_ON_BATTERY

BAT_CHARGER:
                seb     BATF_CHARGER, BAT_FLAGS
                clb     BATF_LOW, BAT_FLAGS

; Charger connected: high-rate charge state machine. While asleep PARAMETER+1
; holds the saved PORT_P1, so P15 is changed there as well.
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
                seb     BATF_HICHARGE_OVF, BAT_FLAGS
                rts

HICHG_GO_COUNT_DOWN:
                ldm     #HICHG_COUNT_DOWN, BAT_HICHG_STATE
                rts

HICHG_STATE_2:
                bne     HICHG_CHECK_MIN ; HICHG_DONE
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
; A-D conversions. IN1 = battery voltage, IN0 = unknown (temperature?).
;   BATTERY_SAMPLE: BAT_VOLTAGE = (BAT_VOLTAGE + IN1) / 2 (low-pass filter)
;   BATTERY_READ:   BAT_VOLTAGE = IN1
; AD_CTRL bit 3 routes "conversion done" to IRQ_T1_AD_REQ, which is polled.
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
                ror     A
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
; 60 Hz tick, called whenever IRQ_INT1_REQ is set
;   - awake with P32 low: force all planes on (except the modem)
;   - every 60th tick: 1 Hz pulse to the VIA, increment the clock, and while
;     asleep compare it with the alarm
;   - always: CHECK_BATTERY
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
                bbs     FLAG_ALARM_HIT, FLAGS, TICK_CHECK_BAT
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
; ADB transmit. Bit-banged with cycle-counted code (1 cycle = 1 us).
; P40 = 1 pulls the line low, P41 reads the line.
;   attention 800 us low, sync 70 us high, 8 command bits, stop bit
;   bit cell 100 us: '0' = 65 us low / 35 us high, '1' = 35 us low / 65 us high
;   after the stop bit a device may hold the line low (SRQ, ~300 us)
;   Listen: Tlt ~160 us, start bit '1', ADB_COUNT data bytes, stop bit
; Every time the line is released it must read high, else TX_BUS_ERROR.
; Carry set = bus error.
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
                ldy     #8              ; 8 command bits, MSB first
                bra     TX_BIT

TX_NEXT_BIT:
                ldx     #1
                jsr     \DELAY_LOOP_X
                nop

TX_BIT:
                seb     P40_PMGR_ADB, PORT_P4 ; line low
                ldx     #2
                jsr     \DELAY_LOOP_X
                rol     ADB_SHIFT
                bcc     TX_BIT_0
                clb     P40_PMGR_ADB, PORT_P4 ; '1': release after 35 us
                bbc     P41_FDB, PORT_P4, TX_BUS_ERROR
                bra     TX_BIT_END

TX_BIT_0:
                jsr     \DELAY_RTS

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
                bbc     P41_FDB, PORT_P4, TX_CHECK_SRQ ; still low: SRQ?

TX_NO_SRQ:
                bra     TX_CMD_DONE

TX_CHECK_SRQ:
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
                bra     TX_BUS_ERROR    ; line stuck low

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

; Listen data. ADB_BUFFER holds the bytes in reverse order, so they are sent
; from ADB_BUFFER[ADB_COUNT-1] down to ADB_BUFFER[0].
TX_LISTEN_DATA:
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

TX_DATA_BIT:
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
                lda     ADB_BUFFER-1, X
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
; ADB receive (Talk answer)
; Each BBS/BBC instruction samples the line once every 5 us; long unrolled
; chains measure the times:
;   RX_BIT: the line went low. Every BBS slot the line stays low moves the
;     entry into the RX_Hnn chain one step further (nn = low time / 5 us).
;   RX_Hnn: wait for the next falling edge. The earlier the entry, the more
;     slots lead to RX_GOT_0 before the RX_GOT_1 part begins, so the bit is
;     '1' if the high time is longer than the low time, else '0'.
;   No falling edge at all: the stop bit has ended the packet.
; Bits are shifted into A behind a 1 sentinel; each full byte is PHAed. S was
; moved to ADB_RX_STACK, so the bytes land in $10, $0F, ... (max 8 bytes).
; Afterwards they are copied to ADB_BUFFER in order and ADB_COUNT is set.
; Carry set = no answer or bad timing (ADBF_NO_DATA|ADBF_ERROR).
;------------------------------------------------------------------------------
ADB_RECEIVE_CMD:
                ldm     #0, ADB_COUNT
                tsx
                stx     TEMP
                ldx     #ADB_RX_STACK
                txs
                lda     #1              ; sentinel
                ldy     #9              ; at most 8 bytes
                ldx     #16             ; wait ~256 us for the start bit

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

RX_START_LOW:                           ; start bit '1': short low ...
                ldx     #3
                bbs     P41_FDB, PORT_P4, RX_FAIL

RX_WAIT_START_HIGH:
                bbs     P41_FDB, PORT_P4, RX_START_HIGH
                dex
                bbs     P41_FDB, PORT_P4, RX_START_HIGH
                bne     RX_WAIT_START_HIGH
                bra     RX_FAIL

RX_START_HIGH:                          ; ... then high, followed by the first bit
                nop
                nop
                nop
                nop
                bit     TEMP            ; delay
                bbc     P41_FDB, PORT_P4, RX_FAIL
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
                bra     RX_FAIL

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

RX_LOW_TOO_LONG:
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
                bbc     P41_FDB, PORT_P4, RX_GOT_1 ; high time > low time
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
                cmp     #1              ; line stays high: end of packet
                bne     RX_LOW_TOO_LONG ; partial byte
                cpy     #8
                bcs     RX_LOW_TOO_LONG ; fewer than 2 bytes
                bra     RX_DONE

RX_GOT_0:
                asl     A
                bcc     RX_NEXT_BIT
                pha                     ; sentinel shifted out: byte complete
                lda     #1
                bbs     P41_FDB, PORT_P4, RX_BYTE_HIGH
                dey
                beq     RX_OVERFLOW
                jmp     RX_BIT_RESUME2  ; skip the slots used up here

RX_BYTE_HIGH:                           ; line already high again
                dey
                beq     RX_OVERFLOW
                jmp     RX_H02

RX_OVERFLOW:
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
                ldx     TEMP            ; restore the stack
                txs
                tya                     ; ADB_COUNT = 9 - Y
                eor     #$FF
                clc
                adc     #10
                sta     ADB_COUNT
                tay
                beq     RX_RET
                ldx     #8

RX_COPY_OUT:                            ; push the bytes from $10 down
                lda     ADB_BUFFER, X
                pha
                dex
                dey
                bne     RX_COPY_OUT
                ldx     ADB_COUNT

RX_COPY_BACK:                           ; pop them into ADB_BUFFER[count-1..0]
                pla
                sta     ADB_BUFFER-1, X
                dex
                bne     RX_COPY_BACK

RX_RET:
                clc
                rts

;==============================================================================
; Host commands, one handler per high nibble. $28 and $78 are handled in
; MAIN_LOOP.
;==============================================================================
COMMAND_TABLE:  WORD COMMAND_xx_NOP
                WORD COMMAND_1x_POWER
                WORD COMMAND_2x_ADB
                WORD COMMAND_3x_PRAM
                WORD COMMAND_4x_CONTRAST
                WORD COMMAND_5x_MODEM
                WORD COMMAND_6x_BATTERY
                WORD COMMAND_7x_SLEEP
                WORD COMMAND_8x_TIMER
                WORD COMMAND_9x_SOUND
                WORD COMMAND_xx_NOP
                WORD COMMAND_xx_NOP
                WORD COMMAND_xx_NOP
                WORD COMMAND_xx_NOP
                WORD COMMAND_Ex_INTERNAL
                WORD COMMAND_xx_NOP

COMMAND_xx_NOP:
                clc
                rts

;------------------------------------------------------------------------------
; $10 powerCntl: for each parameter byte, bit 7 = 1 switches the planes in
;     bits 0-6 on, bit 7 = 0 switches them off. SYS_PWR always stays on.
; $18 powerRead: 1 byte, 1 = plane on; bit 5 = sound latch (IN2).
;------------------------------------------------------------------------------
COMMAND_1x_POWER:
                bbs     3, COMMAND, COMMAND_18_powerRead

COMMAND_10_powerCntl:
                tst     COMMAND_SIZE
                bne     POWER_CNTL_DATA
                rts

POWER_CNTL_DATA:
                lda     COMMAND_SIZE
                pha
                jsr     READ_PARAMETER
                pla
                sta     COMMAND_SIZE
                ldx     #0

POWER_CNTL_LOOP:
                lda     PARAMETER, X
                bpl     POWER_CNTL_OFF
                eor     #$FF            ; on: clear the selected active-low bits,
                and     PORT_P0
                sta     TEMP
                lda     PARAMETER, X
                and     #M_P06_neg5_EN
                ora     TEMP            ; set -5 V if selected
                sta     PORT_P0
                bra     POWER_CNTL_NEXT

POWER_CNTL_NEXT:
                inx
                dec     COMMAND_SIZE
                bne     POWER_CNTL_LOOP
                clc
                rts

POWER_CNTL_OFF:                         ; off: set the active-low bits, clear -5 V
                and     #~M_P07_SYS_PWR & $FF
                ora     PORT_P0
                sta     TEMP
                lda     PARAMETER, X
                and     #M_P06_neg5_EN
                eor     #~M_P07_SYS_PWR & $FF
                and     TEMP
                sta     PORT_P0
                bra     POWER_CNTL_NEXT

COMMAND_18_powerRead:
                ldm     #1, COMMAND_SIZE
                lda     PORT_P0
                and     #~M_P07_SYS_PWR & $FF
                eor     #~(M_P06_neg5_EN|M_P07_SYS_PWR) & $FF ; invert the active-low bits 0-5
                seb     P05_SOUND_PWR, A
                bbs     IN2_SOUND_LATCH, IN, POWER_READ_SEND
                clb     P05_SOUND_PWR, A

POWER_READ_SEND:
                sta     PARAMETER
                jsr     SEND_COMMAND_PARAMETER
                rts

;------------------------------------------------------------------------------
; $28 readADB: reply ADB_COMMAND, ADB_FLAGS, ADB_COUNT, data. Clears INT_ADB
; unless a new /PMINT was sent in the meantime.
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
; $20 pMgrADB: ADB command, ADB_FLAGS (bit 2 = auto-poll), count, data.
;     MAIN_LOOP sends it. The data is stored in reverse order.
; $21 pMgrADBoff: stop auto-poll.
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
                sty     ADB_SEND_COUNT
                sty     ADB_COUNT
                clc
                rts

ADB_UNKNOWN:
                sec
                rts

;------------------------------------------------------------------------------
; $30 timeWrite / $38 timeRead: 4 bytes, seconds since 1904, big-endian
; $31 pramWrite / $39 pramRead: 20 bytes classic PRAM = XPRAM $10-$1F, $08-$0B
; $32 xPramWrite: offset, count, data / $3A xPramRead: offset, count
;     (offset + count are not checked against the 128 bytes)
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

COMMAND_39_pramRead:
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
; XPRAM_IS_VALID: A = sum of the 128 XPRAM bytes (carry ignored). Carry clear
; if it matches XPRAM_CHKSUM and the XPRAM is not all zero. X is preserved.
;------------------------------------------------------------------------------
XPRAM_IS_VALID:
                txa
                pha
                ldx     #0
                lda     #0
                clc

XPRAM_SUM_LOOP:
                adc     XPRAM, X
                inx
                bpl     XPRAM_SUM_LOOP
                sta     TEMP
                cmp     XPRAM_CHKSUM
                bne     XPRAM_INVALID
                sta     TEMP
                bne     XPRAM_VALID
                ldx     #0              ; sum is 0: is everything 0?

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

; A = 8-bit sum of the 4 clock bytes
TIME_CALC_CHECKSUM:
                lda     #0
                clc
                adc     TIME_S
                adc     TIME_S+1
                adc     TIME_S+2
                adc     TIME_S+3
                rts

;------------------------------------------------------------------------------
; $40 setContrast: 1 byte (0-31)   $48 readContrast: 1 byte
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
                jsr     READ_PARAMETER

; PWM duty cycle = CONTRAST_TABLE[n] / 66 (TIMER1 high, TIMER2 low)
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
; $50 modemSet:  bit 0 power on, bit 1 MODEM_A/B (P17), bit 2 wake on ring
; $58 modemRead: bit 0 power on, bit 1 MODEM_A/B, bit 2 wake on ring,
;                bit 3 installed, bit 4 ringing, bit 5 off hook
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
; $68 batteryRead, $69 batteryNow (takes a new unfiltered sample first):
; reply BAT_FLAGS, BAT_VOLTAGE, BAT_IN0. Clears INT_BATT and
; BATF_CHARGER_CHANGED unless a new /PMINT was sent in the meantime.
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

; $78 readINT: reply INT_STATE, then clear INT_RESET
COMMAND_78_readINT:
                lda     INT_STATE
                sta     PARAMETER
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                clb     INT_RESET, INT_STATE
                clb     FLAG_PMINT_SENT, FLAGS
                rts

;------------------------------------------------------------------------------
; $7F sleepReq: 4 bytes 'MATT'. Reply PM_SLEEP_ACK and sleep, or PM_SLEEP_NAK.
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
                ldm     #0, COMMAND_SIZE ; reply: command byte only
                jsr     SEND_COMMAND
                bcs     SLEEP_REQ_FAIL
                lda     COMMAND
                cmp     #PM_SLEEP_ACK
                beq     ENTER_SLEEP

SLEEP_REQ_FAIL:
                sec
                rts

;------------------------------------------------------------------------------
; Sleep. Also used after a cold reset and for a dead battery.
; Saves P0/P1 in PARAMETER, holds the 68000 in reset and switches everything
; off. Then loops on the tick, pulsing STOP_CLK, until
;   - a key is pressed (only after all keys were released once),
;   - the alarm time is reached, or
;   - the modem rings (if enabled).
; It never wakes up while BATF_VERY_LOW is set. On wake-up the ports are
; restored, the PMGR waits for the key to be released, resets the keyboard
; controller and releases the 68000 after 1/30 s. Interrupts stay off while
; asleep; the stack is reset.
;------------------------------------------------------------------------------
ENTER_SLEEP:
                clb     P42_DISP_BLANK, PORT_P4
                sei
                bit     IRQ_CTRL
                bpl     ENTER_SLEEP
                jsr     TICK
                ldx     #STACK_TOP
                txs

SLEEP_WAIT_TICK1:                       ; wait 2 more ticks
                bit     IRQ_CTRL
                bpl     SLEEP_WAIT_TICK1
                jsr     TICK

SLEEP_WAIT_TICK2:
                bit     IRQ_CTRL
                bpl     SLEEP_WAIT_TICK2
                jsr     TICK

                seb     P05_SOUND_PWR, PORT_P0 ; clear the sound latch
                clb     P05_SOUND_PWR, PORT_P0
                lda     PORT_P0         ; save P0 (with SYS_PWR off) and P1
                seb     P07_SYS_PWR, A
                sta     PARAMETER
                lda     PORT_P1
                sta     PARAMETER+1
                clb     P33_SOUND_OFF, PORT_P3
                clb     PWM_EN, PWM_CTRL ; contrast off
                clb     P31_SYS_RST, PORT_P3 ; hold the 68000 in reset

                clb     FLAG_AKD_IDLE_SEEN, FLAGS
                seb     FLAG_SLEEPING, FLAGS
                ldm     #M_P00_IWM_CNTRL|M_P01_SCC_CNTRL|M_P02_HD_PWR|M_P03_MODEM_PWR|M_P04_SERIAL_PWR|M_P07_SYS_PWR, PORT_P0
                                        ; all planes off
                bra     SLEEP_STOP_CLK

SLEEP_LOOP:
                jsr     TICK
                bbs     P11_AKD, PORT_P1, SLEEP_STOP_CLK
                seb     FLAG_AKD_IDLE_SEEN, FLAGS ; all keys up

SLEEP_STOP_CLK:
                clb     P12_STOP_CLK, PORT_P1
                seb     P12_STOP_CLK, PORT_P1
                bbs     BATF_VERY_LOW, BAT_FLAGS, SLEEP_LOOP
                bbc     FLAG_AKD_IDLE_SEEN, FLAGS, SLEEP_CHECK_ALARM
                bbs     P11_AKD, PORT_P1, WAKE ; key pressed

SLEEP_CHECK_ALARM:
                bbs     FLAG_ALARM_HIT, FLAGS, WAKE_ALARM_RING
                bbc     FLAG_RING_WAKEUP, FLAGS, SLEEP_LOOP
                bbs     P16_RING_DETECT, PORT_P1, SLEEP_LOOP

WAKE_ALARM_RING:
                sei
                clb     IRQ_INT1_REQ, IRQ_CTRL
                clb     FLAG_ALARM_HIT, FLAGS
                clb     FLAG_ALARM_SET, FLAGS ; the alarm is one-shot

WAKE:
                sei
                clb     FLAG_SLEEPING, FLAGS

                lda     ADB_FLAGS       ; keep only auto-poll
                and     #4
                sta     ADB_FLAGS

                lda     PARAMETER       ; restore P0 (SYS_PWR still off) and P1
                sta     PORT_P0
                lda     PARAMETER+1
                sta     PORT_P1

WAKE_KEY_RELEASE:
                bit     IRQ_CTRL
                bpl     WAKE_CHECK_KEY
                jsr     TICK

WAKE_CHECK_KEY:
                bbs     P11_AKD, PORT_P1, WAKE_KEY_RELEASE ; wait for the key release

                clb     P07_SYS_PWR, PORT_P0 ; system power on
                clb     P14_KBD_RST, PORT_P1
                seb     PWM_EN, PWM_CTRL
                seb     P42_DISP_BLANK, PORT_P4

                ldx     #2              ; wait 1/30 s

WAKE_WAIT_TICKS:
                bit     IRQ_CTRL
                bpl     WAKE_WAIT_TICKS
                jsr     TICK
                dex
                bne     WAKE_WAIT_TICKS

                seb     P14_KBD_RST, PORT_P1
                seb     P31_SYS_RST, PORT_P3 ; start the 68000
                clb     IRQ_INT2_REQ, IRQ_CTRL
                seb     IRQ_INT2_EN, IRQ_CTRL
                cli

                jmp     MAIN_LOOP

;------------------------------------------------------------------------------
; $80 timerSet: 4 bytes, enables the alarm   $82 timerDisable
; $88 timerRead (also any other $8x): 4 bytes + 1 byte enable flag
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
; $90 soundSet:  bit 0 -> P33, bit 1 = 1 clears the sound latch
; $98 soundRead: bit 0 = P33, bit 1 = sound latch (IN2 low)
;------------------------------------------------------------------------------
COMMAND_9x_SOUND:
                bbs     3, COMMAND, COMMAND_98_soundRead

COMMAND_90_soundSet:
                ldm     #1, COMMAND_SIZE
                jsr     READ_PARAMETER
                bbc     0, PARAMETER, SOUND_P33_LOW
                seb     P33_SOUND_OFF, PORT_P3
                bra     SOUND_LATCH

SOUND_P33_LOW:
                clb     P33_SOUND_OFF, PORT_P3

SOUND_LATCH:
                bbc     1, PARAMETER, SOUND_DONE
                seb     P05_SOUND_PWR, PORT_P0
                clb     P05_SOUND_PWR, PORT_P0

SOUND_DONE:
                rts

COMMAND_98_soundRead:
                ldm     #0, PARAMETER
                bbc     P33_SOUND_OFF, PORT_P3, SOUND_RD_LATCH
                seb     0, PARAMETER

SOUND_RD_LATCH:
                bbs     IN2_SOUND_LATCH, IN, SOUND_RD_SEND
                seb     1, PARAMETER

SOUND_RD_SEND:
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts

;------------------------------------------------------------------------------
; $EF PmgrSoftReset: echo the command, then re-initialise the ports.
;     Note: the stack is not reset and A/Y hold leftover values.
; $EC PmgrSelfTest: 1 byte, 1 = failed: bit 0 ROM checksum, bit 1 RAM address
;     lines, bit 2 RAM read/write
; $EA readPmgrVers: 2 bytes
; $E0 writePmgrRAM: address hi, lo, data      $E8 readPmgrRAM: address hi, lo,
;     count. Any 16-bit address, including the ROM.
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

COMMAND_EC_PmgrSelfTest:
                ldm     #0, PARAMETER
                jsr     CHECK_ROM_CHECKSUM ; carry = result, rotated into
                ror     PARAMETER       ; bit 7 and then down to bits 0-2
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
                lda     PARAMETER       ; PTR = big-endian address
                sta     PTR+1
                lda     PARAMETER+1
                sta     PTR
                ldx     TEMP            ; X = count - 2
                beq     COMMAND_E0_fail
                dex
                beq     COMMAND_E0_fail
                dex
                beq     COMMAND_E0_success ; no data: nothing to do (no reply for $E8!)
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
; Self test routines. Carry set = failed.
;==============================================================================

; 16-bit checksum over $E806-$FFFF: add each byte, then rotate the 16-bit sum
; (PARAMETER+1:A) left by one. Compared with ROM_CHECKSUM. Runs the tick
; between pages.
CHECK_ROM_CHECKSUM:
                lda     #>VECTOR_RESET
                sta     PTR+1
                ldy     #6
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
                dex                     ; a sum of 0 becomes $FFFF
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

; RAM address line test: write a different pattern to $00, $01, $02, $04 ...
; $80, verify, then the same with the inverted patterns. The old contents are
; kept in PARAMETER+1.. and restored. PHP/PLP keeps the I flag; ROL/ROR keeps
; the carry across the PLP.
CHECK_RAM_BITS:
                php
                sei
                sec
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
                rol     A
                plp
                ror     A
                rts

CHECK_RAM_ADR_TAB:  BYTE $00,$01,$02,$04,$08,$10,$20,$40,$80
CHECK_RAM_DATA_TAB: BYTE $F0,$E1,$D2,$C3,$B4,$A5,$96,$87,$78

; RAM read/write test: walk a 1 and a 0 through every byte $BF..$00
; (including the stack). Each byte is restored. Runs the tick in between.
CHECK_RAM_RW:
                ldx     #RAM_END

RAM_RW_NEXT:
                dex
                cpx     #$FF
                beq     RAM_RW_OK
                ldy     0, X
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

; INT2: reset/interrupt switch. Holds the 68000 in reset for at least 2 ticks
; and until the switch is released, then does a warm reset.
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

                bbc     P30_RESET, PORT_P3, INT2_WAIT_RELEASE ; switch still pressed

                jmp     WARM_RESET

; Never enabled: timer 2/serial I/O, timer 1/A-D, timer X, INT1 (60 Hz, polled)
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
; Special page $FF00, called with the 2-byte JSR \xx
;   JSR \DELAY_LOOP_X: 6*X + 9 cycles (X = 0: 256 loops, 1545 us)
;   JSR \DELAY_RTS:    11 cycles
;   DELAY_SMALL is not used.
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
