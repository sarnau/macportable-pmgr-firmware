
; ---------------------------------------------------------------------------

; enum PowerManagerCommands
; Host (68000 via VIA) -> PMGR commands. Command byte bits 7-4 index command_table; bit 3 usually
; selects read (1) / write (0). Unknown commands in an implemented group are mostly ignored.
PowerManagerCommands_10_powerCntl_set_port_0: EQU $10 ; power plane/clock control
PowerManagerCommands_18_powerRead_get_port_0: EQU $18 ; power plane/clock status
PowerManagerCommands_20_pMgrADB: EQU $20 ; XREF: COMMAND_2x_ADB+2/s ; send ADB command
PowerManagerCommands_21_pMgrADBoff: EQU $21 ; XREF: COMMAND_2x_ADB+6/s ; turn ADB auto-poll off
PowerManagerCommands_28_readADB: EQU $28 ; XREF: MAIN_LOOP:loc_E92D/s ; Apple Desktop Bus
PowerManagerCommands_30_timeWrite: EQU $30 ; XREF: COMMAND_3x_PRAM+5/s ; write the time to the clock chip
PowerManagerCommands_31_pramWrite: EQU $31
                                        ; XREF: COMMAND_3x_PRAM:loc_EEF1/s ; write the original 20 bytes of PRAM (Portable only)
PowerManagerCommands_32_xPramWrite: EQU $32 ; write extended PRAM byte(s)
PowerManagerCommands_38_timeRead: EQU $38 ; XREF: COMMAND_3x_PRAM+59/s ; read the time from the clock
PowerManagerCommands_39_pramRead: EQU $39
                                        ; XREF: COMMAND_3x_PRAM:loc_EF40/s ; read the original 20 bytes of PRAM (XPRAM $10-$1F,$08-$0B)
PowerManagerCommands_3A_xPramRead: EQU $3A ; read extended PRAM byte(s)
PowerManagerCommands_40_contrast: EQU $40 ; set screen contrast
PowerManagerCommands_48_contrast_read: EQU $48
PowerManagerCommands_50_modemSet: EQU $50 ; internal modem control
PowerManagerCommands_58_modemRead: EQU $58 ; internal modem status
PowerManagerCommands_68_batteryRead: EQU $68
                                        ; XREF: COMMAND_6x_BATTERY+2/s ; read battery/charger level and status
PowerManagerCommands_69_batteryNow: EQU $69
                                        ; XREF: COMMAND_6x_BATTERY+6/s ; read battery/charger instantaneous level and status
PowerManagerCommands_70_response_success: EQU $70 ; reply to sleepReq: going to sleep
                                        ; XREF: COMMAND_7x_SLEEP+C/s
                                        ; COMMAND_7x_SLEEP+28/s
PowerManagerCommands_78_readINT: EQU $78 ; XREF: MAIN_LOOP+14/s ; get PMGR interrupt data
PowerManagerCommands_7F_sleepReq: EQU $7F ; XREF: COMMAND_7x_SLEEP+2/s ; put the system to sleep
PowerManagerCommands_80_timerSet: EQU $80 ; XREF: COMMAND_8x_WAKEUP+2/s ; set the wakeup timer
PowerManagerCommands_82_timerDisable: EQU $82
                                        ; XREF: COMMAND_8x_WAKEUP:loc_F162/s
PowerManagerCommands_88_timerRead: EQU $88 ; read the wakeup timer setting
PowerManagerCommands_90_soundSet: EQU $90 ; sound power control
PowerManagerCommands_98_soundRead: EQU $98 ; read sound power state
PowerManagerCommands_AA_response_fail: EQU $AA ; reply to sleepReq: bad signature (not 'MATT')
                                        ; XREF: COMMAND_7x_SLEEP+1B/s
PowerManagerCommands_E0_writePmgrRAM: EQU $E0
                                        ; XREF: COMMAND_Ex_INTERNAL+65/s ; write to internal PMGR RAM
PowerManagerCommands_E8_readPmgrRAM: EQU $E8 ; read from internal PMGR RAM
PowerManagerCommands_EA_readPmgrVers: EQU $EA
                                        ; XREF: COMMAND_Ex_INTERNAL:loc_F1EB/s ; read the PMGR version number
PowerManagerCommands_EC_PmgrSelfTest: EQU $EC
                                        ; XREF: COMMAND_Ex_INTERNAL:loc_F1C4/s ; run the PMGR selftest
PowerManagerCommands_EF_PmgrSoftReset: EQU $EF
                                        ; XREF: COMMAND_Ex_INTERNAL+2/s ; soft reset of the PMGR

; ---------------------------------------------------------------------------

; enum FLAGS_Bits  -- general flags in RAM $00 (FLAGS)
;   bit 0  unused
;   bit 1  PMINT_SENT      set when the /PMINT pulse was sent to the VIA, cleared by readINT ($78).
;                          readADB/batteryRead only clear their interrupt cause when no newer PMINT
;                          was signalled in the meantime.
;   bit 2  AKD_IDLE_SEEN   during sleep: the AKD (any key down, active high) line was seen low, i.e.
;                          all keys were up at least once. A key press only wakes the machine after
;                          that, so a key held while going to sleep does not wake it immediately.
;   bit 3  unused
;   bit 4  ALARM_SET       wakeup timer enabled (timerSet $80 / timerDisable $82)
;   bit 5  ALARM_TRIGGERED wakeup time reached (only evaluated while sleeping)
;   bit 6  SLEEPING        set while the PMGR keeps the system powered down
;   bit 7  RING_WAKEUP     wake on modem ring enabled (modemSet $50 bit 2)
FLAGS_Bits_0:    EQU 0
FLAGS_Bits_PMINT_SENT:    EQU 1                  ; XREF: MAIN_LOOP+90/s
                                        ; COMMAND_28_readADB+12/s ...
FLAGS_Bits_AKD_IDLE_SEEN:  EQU 2                  ; XREF: COMMAND_7x_SLEEP+5C/s
                                        ; COMMAND_7x_SLEEP+6B/s ... ; AKD seen inactive since sleep started
FLAGS_Bits_3:    EQU 3
FLAGS_Bits_ALARM_SET: EQU 4             ; XREF: IRQ_60Hz+2E/s
                                        ; COMMAND_7x_SLEEP+88/s ... ; 1:Alarm is enabled
FLAGS_Bits_ALARM_TRIGGERED: EQU 5       ; XREF: IRQ_60Hz+2/s
                                        ; IRQ_60Hz+34/s ... ; 1:Alarm time was triggered
FLAGS_Bits_SLEEPING:    EQU 6                  ; XREF: CHECK_BAT_STATUS+6E/s
                                        ; IRQ_60Hz+4/s ...
FLAGS_Bits_RING_WAKEUP:    EQU 7                  ; XREF: COMMAND_5x_MODEM+9/s
                                        ; COMMAND_5x_MODEM+E/s ...

; ---------------------------------------------------------------------------

; enum IRQ_CTRL_FLAGS, width 1 byte  -- interrupt control register $FE (M50753 datasheet Fig. 3)
; [FIX] IDA had bits 2-5 swapped: on the M50753 bits 2/3 are Timer 2 / serial I/O and bits 4/5 are
;       Timer 1 / A-D. The firmware polls bit 5 for "A-D conversion finished" (AD_CTRL bit 3 = 1 selects
;       the A-D as source), which only makes sense with the corrected assignment.
; No interrupt is ever enabled except INT2 (reset/interrupt switch). INT1 (60.15 Hz from the VIA/GLU)
; is only polled: "bit IRQ_CTRL / bmi" tests bit 7 = INT1 request.
IRQ_CTRL_FLAGS_INT2_EN: EQU 0           ; XREF: VECTOR_INT2_RESET_CONTINUE+B1/s
                                        ; COMMAND_7x_SLEEP+BF/s ; INT2 pin interrupt enable bit
IRQ_CTRL_FLAGS_INT2_IRQ_REQ: EQU 1      ; XREF: VECTOR_INT2_RESET_CONTINUE+AF/s
                                        ; COMMAND_7x_SLEEP+BD/s ; INT2 pin interrupt request bit
IRQ_CTRL_FLAGS_TIM2_SERIAL_EN: EQU 2    ; [FIX] Timer 2 or serial I/O interrupt enable bit
IRQ_CTRL_FLAGS_TIM2_SERIAL_REQ: EQU 3   ; [FIX] Timer 2 or serial I/O interrupt request bit
IRQ_CTRL_FLAGS_TIM1_AD_EN: EQU 4        ; [FIX] Timer 1 or A-D interrupt enable bit (source: AD_CTRL bit 3)
IRQ_CTRL_FLAGS_TIM1_AD_REQ: EQU 5          ; XREF: BATTERY_READ_SUM+7/s
                                        ; BATTERY_READ_SUM+F/s ... ; [FIX] Timer 1 or A-D conversion complete request bit
IRQ_CTRL_FLAGS_INT1_EN: EQU 6           ; INT1 pin interrupt enable bit
IRQ_CTRL_FLAGS_INT1_REQ: EQU 7          ; XREF: IRQ_60Hz/s
                                        ; COMMAND_7x_SLEEP+84/s ; INT1 pin interrupt request bit

; ---------------------------------------------------------------------------

; enum PWM_CTRL_FLAGS, width 1 byte  -- PWM control register $F5
; [FIX] The old bit descriptions (PWM1-3, P6x, INTx reverse bits) belong to a different 740 family
;       part. The M50753 has a single PWM output and only bit 0 is defined:
;       1 = PWM output on (high time from TIMER1, low time from TIMER2, clock = f(XIN)/16),
;       0 = output transistor off. The PWM drives the LCD contrast voltage.
PWM_CTRL_FLAGS_PWM_EN: EQU 0             ; XREF: VECTOR_INT2_RESET_CONTINUE+8C/s
                                        ; COMMAND_7x_SLEEP+58/s ... ; 1: PWM (LCD contrast) output enabled

; ---------------------------------------------------------------------------

; enum REG_IN
REG_IN_0_PMGR_IN0: EQU 0
REG_IN_A_D_FILTER: EQU 1
REG_IN_SOUND_LATCH: EQU 2               ; XREF: COMMAND_1x_POWER+4A/s
                                        ; COMMAND_9x_SOUND:loc_F1AA/s
REG_IN_OFF_HOOK: EQU 3                  ; XREF: COMMAND_5x_MODEM:loc_F045/s
REG_IN_4:        EQU 4
REG_IN_5:        EQU 5
REG_IN_6:        EQU 6
REG_IN_7:        EQU 7

; ---------------------------------------------------------------------------

; enum REG_PORT_0
P00_IWM_CNTRL:   EQU 0
P01_SCC_CNTRL:   EQU 1
P02_HD_PWR:      EQU 2                  ; HD PWR/
P03_MODEM_PWR:   EQU 3                  ; XREF: COMMAND_5x_MODEM+1C/s
                                        ; COMMAND_5x_MODEM:loc_F025/s ... ; MODEM PWR/
P04_SERIAL_PWR:  EQU 4                  ; SERIAL PWR/
P05_SOUND_PWR:   EQU 5                  ; XREF: VECTOR_INT2_RESET_CONTINUE+AB/s
                                        ; VECTOR_INT2_RESET_CONTINUE+AD/s ... ; SOUND PWR/
P06_neg5_EN:     EQU 6                  ; -5 ENABLE
P07_SYS_PWR:     EQU 7                  ; XREF: COMMAND_7x_SLEEP+4F/s
                                        ; COMMAND_7x_SLEEP+A5/s ; SYS_PWR/

; ---------------------------------------------------------------------------

; enum REG_P0_MASK, bitfield, width 1 byte
M_P00_IWM_CNTRL: EQU 1                  ; XREF: VECTOR_INT2_RESET_CONTINUE+4A/s
                                        ; COMMAND_7x_SLEEP+60/s
M_P01_SCC_CNTRL: EQU 2                  ; XREF: VECTOR_INT2_RESET_CONTINUE+4A/s
                                        ; COMMAND_7x_SLEEP+60/s
M_P02_HD_PWR:    EQU 4                  ; XREF: VECTOR_INT2_RESET_CONTINUE+40/s
                                        ; VECTOR_INT2_RESET_CONTINUE+4A/s ...
M_P03_MODEM_PWR: EQU 8                  ; XREF: VECTOR_INT2_RESET_CONTINUE+4A/s
                                        ; IRQ_60Hz+A/s ...
M_P04_SERIAL_PWR: EQU $10               ; XREF: VECTOR_INT2_RESET_CONTINUE+4A/s
                                        ; COMMAND_7x_SLEEP+60/s
M_P05_SOUND_PWR: EQU $20
M_P06_neg5_EN:   EQU $40                ; XREF: VECTOR_INT2_RESET_CONTINUE+42/s
                                        ; IRQ_60Hz+A/s ...
M_P07_SYS_PWR:   EQU $80                ; XREF: VECTOR_INT2_RESET_CONTINUE+4A/s
                                        ; COMMAND_1x_POWER:loc_EE61/s ...

; ---------------------------------------------------------------------------

; enum REG_PORT_1
P10_N_C:         EQU 0                  ; XREF: IRQ_60Hz+D/s
P11_AKD:         EQU 1                  ; XREF: COMMAND_7x_SLEEP+68/s
                                        ; COMMAND_7x_SLEEP+77/s ... ; Any Key Down
P12_STOP_CLK:    EQU 2                  ; XREF: COMMAND_7x_SLEEP:loc_F0F2/s
                                        ; COMMAND_7x_SLEEP+6F/s
P13_CHRG_ON:     EQU 3                  ; XREF: CHECK_BAT_STATUS+16/s
                                        ; CHECK_BAT_STATUS+25/s
P14_KBD_RST:     EQU 4                  ; XREF: VECTOR_INT2_RESET_CONTINUE+91/s
                                        ; COMMAND_7x_SLEEP+A7/s ... ; resets keyboard M50740
P15_HICHG:       EQU 5                  ; XREF: CHECK_BAT_STATUS+93/s
                                        ; CHECK_BAT_STATUS+CE/s
P16_RING_DETECT: EQU 6                  ; XREF: COMMAND_5x_MODEM:loc_F040/s
                                        ; COMMAND_7x_SLEEP+80/s
P17_MODEM_AB:    EQU 7                  ; XREF: COMMAND_5x_MODEM+13/s
                                        ; COMMAND_5x_MODEM:loc_F01C/s ...

; ---------------------------------------------------------------------------

; enum REG_P1_MASK, bitfield, width 1 byte
M_P10_N_C:       EQU 1                  ; XREF: VECTOR_INT2_RESET_CONTINUE+51/s ; not connected in the schematics
M_P11_AKD:       EQU 2                  ; Any key pressed signal
M_P12_STOP_CLK:  EQU 4                  ; MUSIC GLU (U12G) STOP_CLK - stop the clock signal?
M_P13_CHRG_ON:   EQU 8                  ; HYBRID (U1M) CHRG_ON line for the power supply
M_P14_KBD_RST:   EQU $10                ; M50740 (U12K) Keyboard Controller Reset Line
M_P15_HICHG:     EQU $20
M_P16_RING_DETECT: EQU $40              ; XREF: VECTOR_INT2_RESET_CONTINUE+51/s ; From J21: EPMGR and J9: MODEM connector
M_P17_MODEM_AB:  EQU $80                ; XREF: VECTOR_INT2_RESET_CONTINUE+51/s ; MISC GLUE (U12G) - MODEM_A/B

; ---------------------------------------------------------------------------

; enum REG_PORT_3
P30_RESET:       EQU 0                  ; XREF: VECTOR_INT2_RESET+11/s
P31_SYS_RST:     EQU 1                  ; XREF: VECTOR_INT2_RESET_CONTINUE+A9/s
                                        ; COMMAND_7x_SLEEP+5A/s ... ; Reset line output to 680x0 and many other chips
P32_VIA_TEST:    EQU 2                  ; XREF: VECTOR_INT2_RESET_CONTINUE+97/s
                                        ; CHECK_BAT_STATUS+71/s ... ; PB2 (Pin 13) on VIA 65C22 V14H
P33_SOUND_OFF:   EQU 3                  ; XREF: COMMAND_7x_SLEEP+56/s
                                        ; COMMAND_9x_SOUND+C/s ... ; Audio subsystem power control
P34_1SEC:        EQU 4                  ; XREF: IRQ_60Hz:IRQ_1Hz/s
                                        ; IRQ_60Hz+16/s ; CA1 (Pin 44) on VIA 65C22 V14H
P35_PMINT:       EQU 5                  ; XREF: MAIN_LOOP+8E/s
                                        ; MAIN_LOOP+92/s ; CB1 (Pin 19) on VIA 65C22 V14H
P36_PMACK:       EQU 6                  ; XREF: READ_BYTE+1F/s
                                        ; READ_BYTE:loc_EA08/s ... ; PB1 (Pin 12) on VIA 65C22 V14H: PMAck handshake flag to the VIA
P37_PMREQ:       EQU 7                  ; XREF: MAIN_LOOP+A/s
                                        ; READ_BYTE/s ... ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA

; ---------------------------------------------------------------------------

; enum REG_P3_MASK, bitfield, width 1 byte
M_P30_RESET:     EQU 1                  ; XREF: VECTOR_INT2_RESET_CONTINUE+5D/s
                                        ; VECTOR_INT2_RESET+1/s
M_P31_SYS_RST:   EQU 2                  ; XREF: VECTOR_INT2_RESET_CONTINUE+63/s
M_P32_VIA_TEST:  EQU 4                  ; XREF: VECTOR_INT2_RESET_CONTINUE+5D/s
                                        ; VECTOR_INT2_RESET_CONTINUE+63/s
M_P33_SOUND_OFF: EQU 8                  ; XREF: VECTOR_INT2_RESET_CONTINUE+63/s
M_P34_1_SEC:     EQU $10                ; XREF: VECTOR_INT2_RESET_CONTINUE+5D/s
M_P35_PMINT:     EQU $20                ; XREF: VECTOR_INT2_RESET_CONTINUE+5D/s
M_P36_PMACK:     EQU $40                ; XREF: VECTOR_INT2_RESET_CONTINUE+5D/s
M_P37_PMREQ:     EQU $80                ; XREF: VECTOR_INT2_RESET_CONTINUE+5D/s

; ---------------------------------------------------------------------------

; enum REG_PORT_4_ADB
P40_PMGR_ADB:    EQU 0                  ; XREF: MAIN_LOOP+62/s
                                        ; MAIN_LOOP+6C/s ... ; PMGR_ADB (ADB out)
P41_FDB:         EQU 1                  ; XREF: ADB_SEND_CMD+17/s
                                        ; ADB_SEND_CMD+30/s ... ; ADB In
P42_DISP_BLANK:  EQU 2                  ; XREF: COMMAND_7x_SLEEP:ENTER_SLEEP/s
                                        ; COMMAND_7x_SLEEP+AB/s ; DISPLAY (J19) Display Blank Line
P43_MODEM_INS:   EQU 3                  ; XREF: COMMAND_5x_MODEM:loc_F03B/s ; MODEM (J9) and EPMGR (J21) - Modem Installed?
P44_N_C:         EQU 4                  ; not connected in the schematics
P45_N_C:         EQU 5                  ; not connected in the schematics
P46_N_C:         EQU 6                  ; not connected in the schematics
P47_N_C:         EQU 7                  ; not connected in the schematics

; ---------------------------------------------------------------------------

; enum REG_P4_MASK, bitfield, width 1 byte
M_P40_PMGR_ADB_OUT: EQU 1
M_P41_MASK_ADB_IN: EQU 2
M_P42_DISP_BLANK: EQU 4
M_P43_MODEM_INS: EQU 8
M_P44_N_C:       EQU $10
M_P45_N_C:       EQU $20
M_P46_N_C:       EQU $40
M_P47_N_C:       EQU $80

; ---------------------------------------------------------------------------

; enum ADB_STATUS_BITS  -- ADB_FLAGS ($06), returned as 2nd byte of readADB ($28)
; The host writes this byte with pMgrADB ($20, parameter byte 1); the PMGR adds its status bits.
; (names are derived from the code)
;   bit 0  host flag, preserved, not interpreted by the PMGR
;   bit 1  PENDING   a pMgrADB command is waiting to be sent (set by $20, cleared when started)
;   bit 2  AUTOPOLL  repeat the last command every 1/60 s; an empty response (no device data and
;                    no SRQ) does not interrupt the host. Cleared by pMgrADBoff ($21).
;   bit 3  SRQ       a device held the line low after the command stop bit (service request)
;   bit 4  NO_DATA   no (valid) response / ADB reset sent / transmission aborted
;   bit 5  BUS_ERR   the bus did not follow our output (stuck low / collision) while sending
;   bit 7  ERROR     set together with bit 5 or with a receive timeout
ADB_STATUS_BITS_0: EQU 0
ADB_STATUS_BITS_PENDING: EQU 1                ; XREF: MAIN_LOOP+7/s
                                        ; MAIN_LOOP+46/s ...
ADB_STATUS_BITS_AUTOPOLL: EQU 2                ; XREF: MAIN_LOOP+49/s
                                        ; MAIN_LOOP+80/s
ADB_STATUS_BITS_SRQ: EQU 3                ; XREF: MAIN_LOOP+83/s
                                        ; ADB_SEND_CMD:loc_EC54/s
ADB_STATUS_BITS_NO_DATA: EQU 4                ; XREF: MAIN_LOOP+6E/s
                                        ; MAIN_LOOP+77/s ...
ADB_STATUS_BITS_BUS_ERR: EQU 5                ; XREF: ADB_SEND_CMD:adb_send_noAck/s
ADB_STATUS_BITS_6: EQU 6
ADB_STATUS_BITS_ERROR: EQU 7                ; XREF: ADB_SEND_CMD+6E/s
                                        ; ADB_RECEIVE_CMD:loc_ECDD/s

; ---------------------------------------------------------------------------

; enum BAT_CHG_BITS  -- BAT_CHG_FLAGS ($1D), 1st byte of batteryRead ($68/$69)
;   bit 0  CHARGER          charger connected (P13 /CHRG_ON is low)
;   bit 1  HICHARGE_ON      high-rate charge active (mirrors output P15 HICHG)
;   bit 2  HICHARGE_OVF     16-bit high-charge timer overflowed (~18 min at 60 Hz)
;   bit 3  DEAD             battery voltage < PRAM_BAT_DEAD_LEVEL -> PMGR forces sleep
;   bit 4  LOW              battery voltage < PRAM_BAT_LOW_LEVEL (low battery warning)
;   bit 5  CHARGER_CHANGED  charger was connected/disconnected since the last batteryRead
;   bit 6  VERY_LOW         voltage < (LOW_LEVEL+DEAD_LEVEL)/2; while set the PMGR will not wake up
BAT_CHG_BITS_CHARGER: EQU 0          ; XREF: CHECK_BAT_STATUS:loc_EA7D/s
                                        ; CHECK_BAT_STATUS:CHARGER_CONNECTED/s
BAT_CHG_BITS_HICHARGE_ON:  EQU 1                  ; XREF: CHECK_BAT_STATUS+97/s
                                        ; CHECK_BAT_STATUS+D2/s
BAT_CHG_BITS_HICHARGE_OVF:  EQU 2                  ; XREF: CHECK_BAT_STATUS+A2/s
                                        ; CHECK_BAT_STATUS+AF/s ...
BAT_CHG_BITS_DEAD:  EQU 3                  ; XREF: CHECK_BAT_STATUS+21/s
                                        ; CHECK_BAT_STATUS+6C/s
BAT_CHG_BITS_LOW:  EQU 4                  ; XREF: CHECK_BAT_STATUS+55/s
                                        ; CHECK_BAT_STATUS+58/s ...
BAT_CHG_BITS_CHARGER_CHANGED:  EQU 5                  ; XREF: CHECK_BAT_STATUS+1A/s
                                        ; COMMAND_6x_BATTERY+22/s
BAT_CHG_BITS_VERY_LOW:  EQU 6                  ; XREF: CHECK_BAT_STATUS+23/s
                                        ; CHECK_BAT_STATUS+66/s ...
BAT_CHG_BITS_7:  EQU 7

; ---------------------------------------------------------------------------

; enum BAT_STATE_TYPE  -- BAT_HICHG_STATE ($21): high-rate charge state machine (charger connected)
;   0  start: switch HICHG on, timer = 1
;   1  count the timer up while 90 <= voltage < 208; voltage >= 208 -> state 2
;   2  count the same time down again (charge as long again as it took to reach 208)
;   3  HICHG off (trickle charge). Voltage < 90 in any state restarts at state 0.
BAT_STATE_TYPE_0: EQU 0                 ; XREF: CHECK_BAT_STATUS:loc_EAD5/s
BAT_STATE_TYPE_1: EQU 1                 ; XREF: CHECK_BAT_STATUS+99/s
BAT_STATE_TYPE_2: EQU 2                 ; XREF: CHECK_BAT_STATUS:loc_EB03/s
                                        ; CHECK_BAT_STATUS:loc_EB1B/s
BAT_STATE_TYPE_3: EQU 3                 ; XREF: CHECK_BAT_STATUS+CB/s

; ---------------------------------------------------------------------------

; enum CMD_78_BITS  -- CMD_78_STATE ($01), the byte returned by readINT ($78)
;   bit 0  ADB_IRQ   ADB response available (fetch with readADB $28)
;   bit 1  BATT_IRQ  battery/charger status changed (fetch with batteryRead $68)
;   bit 2  BATT_2    only ever cleared (by batteryRead) - never set in this ROM
;   bit 3  RESET     PMGR went through a cold (power-on) reset; cleared by readINT
; While bits 0-2 are non-zero the PMGR pulses /PMINT (VIA CB1) every 1/60 s.
CMD_78_BITS_ADB_IRQ: EQU 0              ; XREF: MAIN_LOOP+43/s
                                        ; MAIN_LOOP:loc_E996/s ...
CMD_78_BITS_BATT_IRQ: EQU 1             ; XREF: CHECK_BAT_STATUS+18/s
                                        ; CHECK_BAT_STATUS+5A/s ...
CMD_78_BITS_BATT_2: EQU 2             ; XREF: COMMAND_6x_BATTERY+1E/s
CMD_78_BITS_RESET: EQU 3                ; XREF: COMMAND_78_readINT+A/s

; ---------------------------------------------------------------------------

; enum CMD_78_BITMASK, bitfield, width 1 byte
CMD_78_BITMASK_ADB_IRQ: EQU 1           ; XREF: MAIN_LOOP+8A/s
CMD_78_BITMASK_BATT_IRQ: EQU 2          ; XREF: MAIN_LOOP+8A/s
CMD_78_BITMASK_BATT_2: EQU 4          ; XREF: MAIN_LOOP+8A/s
CMD_78_BITMASK_RESET: EQU 8             ; XREF: VECTOR_RESET:RESET/s

; ===========================================================================
;  Macintosh Portable (M5120) Power Manager ("PMGR") firmware, ROM version $02,$B5
;  "Copyright Apple Computer Inc 1987, 1988, 1989 Written by Michael Hanlon"
; ===========================================================================
;
;  CPU: Mitsubishi M50753 (MELPS 740 family, 6502-derived 8-bit single-chip MCU, mask ROM)
;    * 6144 bytes ROM  $E800-$FFFF  (this image, 6 KB; vectors $FFF4-$FFFF, special page $FF00-$FFFF)
;    * 192 bytes RAM   $0000-$00BF  ($00C0-$00DF does not exist)
;    * SFRs            $00E0-$00FF  (ports P0-P4, IN/A-D, PWM, serial I/O, timers, interrupt control)
;    * 8-ch 8-bit A-D, 1 PWM output, 3 timers, INT1/INT2 external interrupts
;    Every SFR address, the A-D/PWM registers and the 6K/192 byte sizes match the M50753
;    datasheet (1989 Mitsubishi Single-Chip 8-Bit Microcomputers data book, p. 2-199ff),
;    not the M50740 (no A-D/PWM) that is used as the keyboard controller.
;    Clock: f(XIN) = 4 MHz, phi = 1 MHz -> 1 cycle = 1 us. The ADB timing loops confirm this:
;    800 us attention, 70 us sync, 35/65 us bit cells.
;    740 extras used here: SEB/CLB/BBS/BBC (bit ops on A or zero page), LDM #imm,zp, TST zp,
;    JSR (zp), JSR \sp (2-byte call to $FFxx), BRA, CLT (T flag must be 0).
;
;  The PMGR is not just an ADB controller: it also switches all power planes, charges the battery,
;  keeps the real-time clock and the 128 bytes of (extended) parameter RAM alive, controls the LCD
;  contrast, modem and sound power and puts the machine to sleep / wakes it up.
;  It talks to the 68000 through the 6522 VIA over an 8-bit parallel bus (P2) with a
;  PMREQ/PMACK handshake (P37/P36) and an interrupt line /PMINT (P35 -> VIA CB1).
;
;  Host protocol (see READ_COMMAND/SEND_COMMAND):
;    host -> PMGR : command, count, count x data
;    PMGR -> host : (for read commands) reply byte(s): command/flag byte, count, count x data
;    The 68000 polls readINT ($78) after /PMINT and then fetches readADB ($28) or batteryRead ($68).
;
;  Corrections made to the IDA output (all marked [FIX]; see pmuv1_analysis.md for details):
;    1. 5 operands were printed as "(expr), Y" / "(expr), X" although the opcodes are absolute
;       indexed ($B9/$99/$BD). In IAR syntax "(zp),Y" is indirect-indexed - the listing did
;       not re-assemble to the ROM.
;    2. "#!X" was used for bitwise NOT; in IAR "!" is a logical NOT ("~" is bitwise), and
;       "#!A|B" additionally had the wrong precedence ($BF instead of the ROM's $3F).
;    3. IRQ_CTRL bits 2-5 had Timer 1/Timer 2 swapped; A-D shares its request bit with Timer 1.
;    4. PWM_CTRL bit descriptions were those of another 740 part.
;    5. "clb M_P30_RESET, PORT_P3" (mask used as a bit number) really clears bit 1 = P31 SYS_RST.
;    6. Port P4 initial value was expressed with P3 masks.
;    7. ROM_CHECKSUM is a big-endian value $7644 (two bytes $76,$44), not WORD $4476.
;    8. Wrong/shifted comments ($38/$39/$3A commands, INT1/INT2, auto-propagated comments).
;    9. The header below says "Range: E000h - F800h": the ROM really occupies $E800-$FFFF.
;    10. Symbols renamed to their actual meaning (ENTER_SLEEP, FLAGS_Bits_SLEEPING, battery bits ...).
;  The corrected file re-assembles byte-identical to pmuv1.bin (checked with tools/reasm740.py).
;
; +-------------------------------------------------------------------------+
; |      This file was generated by The Interactive Disassembler (IDA)      |
; |           Copyright (c) 2021 Hex-Rays, <support@hex-rays.com>           |
; |                      License info: 48-3051-7314-20                      |
; |                       Markus Fritze, personal use                       |
; +-------------------------------------------------------------------------+
;
; Input SHA256 : 0F9911AB33A62A2831D683D9648059BD7AD59C455B59DCD214C610CE16EEBD57
; Input MD5    : 984FDC07FFDEEDDD444AC3E8560835A3
; Input CRC32  : 01DAE148

; File Name   : /Users/sarnau/Downloads/macprtb/pmuv1.bin
; Format      : Binary file
; Base Address: 0000h Range: E000h - F800h Loaded length: 1800h
; [FIX] the ROM image is located at $E800-$FFFF (see ORG below and the vectors)

; Processor       : m740 [38000]
; Target assembler: IAR 740 Assembler

; ===========================================================================

; Segment type: Regular
                RSEG RAM
; RAM map ($00-$BF)
;   $00-$12  flags, ADB state, ADB buffer, command/count of the current host command
;   $13-$1A  PARAMETER: 8 byte host parameter/reply buffer (no bounds check on incoming counts!)
;   $1D-$23  battery state, $24-$29 RTC (60 Hz divider, seconds since 1904 big-endian, checksum)
;   $2A-$2E  wakeup alarm (big-endian seconds), contrast value
;   $2F-$AE  128 bytes XPRAM (Mac parameter RAM), $AF its checksum
;   $B0-$BF  stack (16 bytes; S is initialised to $BF)
FLAGS:          BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+2A↓w
                                        ; MAIN_LOOP+90↓w ...
CMD_78_STATE:   BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+44↓w
                                        ; VECTOR_INT2_RESET_CONTINUE+46↓r ...
TEMP:           BLKB 1                  ; DATA XREF: ADB_RECEIVE_CMD+4↓w
                                        ; ADB_RECEIVE_CMD+1E↓r ...
ADB_SEND_SIZE:  BLKB 1                  ; DATA XREF: MAIN_LOOP+58↓r
                                        ; COMMAND_2x_ADB:loc_EECE↓w
ADB_SEND_BYTE:  BLKB 1                  ; DATA XREF: ADB_SEND_CMD+8↓w
                                        ; ADB_SEND_CMD+2A↓w ...
ADB_COMMAND:    BLKB 1                  ; DATA XREF: MAIN_LOOP+5C↓r
                                        ; ADB_SEND_CMD+6↓r ...
ADB_FLAGS:      BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+2C↓w
                                        ; MAIN_LOOP+7↓r ...
BUFFER_CNT:     BLKB 1                  ; DATA XREF: MAIN_LOOP+5A↓w
                                        ; ADB_SEND_CMD:loc_EC60↓r ...
BUFFER:         BLKB 8                  ; DATA XREF: ADB_RECEIVE_CMD:loc_EE00↓o
STACK_TOP_ADB_RECEIVE:BLKB 1            ; ADB_RECEIVE_CMD temporarily moves S here and PHAs received bytes into BUFFER
                                        ;           ; DATA XREF: ADB_RECEIVE_CMD+6↓o
COMMAND:        BLKB 1                  ; DATA XREF: MAIN_LOOP+12↓r
                                        ; MAIN_LOOP+2C↓o ...
COMMAND_SIZE:   BLKB 1                  ; DATA XREF: MAIN_LOOP+31↓o
                                        ; READ_COMMAND+C↓w ...
PARAMETER:      BLKB 8                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+87↓w
                                        ; READ_COMMAND:READ_PARAMETER↓o ...
PTR:            BLKB 2                  ; DATA XREF: MAIN_LOOP+2F↓w
                                        ; MAIN_LOOP+36↓r ...
BAT_CHG_FLAGS:  BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+16↓w
                                        ; CHECK_BAT_STATUS:loc_EA6D↓r ...
BAT_VOLTAGE:BLKB 1              ; DATA XREF: CHECK_BAT_STATUS+4F↓r
                                        ; CHECK_BAT_STATUS+A9↓r ...
BAT_IN0:BLKB 1               ; DATA XREF: CHECK_BAT_STATUS:loc_EA69↓r
                                        ; BATTERY_READ_SUM+2C↓w ...
BAT_VERY_LOW_LEVEL:    BLKB 1                  ; DATA XREF: CHECK_BAT_STATUS+45↓w
                                        ; CHECK_BAT_STATUS+4B↓r ...
BAT_HICHG_STATE:      BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+18↓w
                                        ; CHECK_BAT_STATUS:loc_EAD5↓w ...
BAT_COUNT_A:    BLKB 1                  ; DATA XREF: CHECK_BAT_STATUS+9C↓w
                                        ; CHECK_BAT_STATUS+B2↓w ...
BAT_COUNT_B:    BLKB 1                  ; DATA XREF: CHECK_BAT_STATUS+9F↓w
                                        ; CHECK_BAT_STATUS+B6↓w ...
IRQ_60Hz_COUNTER:BLKB 1                 ; DATA XREF: VECTOR_INT2_RESET_CONTINUE:_TIME_CLR_LOOP↓o
                                        ; IRQ_60Hz:loc_EBA6↓w ...
TIME_S:         BLKB 4                  ; DATA XREF: IRQ_60Hz+27↓w
                                        ; IRQ_60Hz+4B↓r ...
TIME_CHECKSUM:  BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+31↓r
                                        ; IRQ_60Hz+2C↓w ...
ALARM_TIME:     BLKB 4                  ; DATA XREF: IRQ_60Hz+49↓r
                                        ; COMMAND_8x_WAKEUP+C↓o ...
CONTRAST_TIMER_VALUE:BLKB 1             ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+78↓r
                                        ; VECTOR_INT2_RESET_CONTINUE:loc_E8DE↓w ...
PRAM_BUFFER:    BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE:_PRAM_CLR_LOOP↓o
                                        ; COMMAND_3x_PRAM+43↓o ...
                BLKB 1
                BLKB 1
                BLKB 1
                BLKB 1
                BLKB 1
                BLKB 1
                BLKB 1
PRAM_BUFFER_08: BLKB 8                  ; DATA XREF: COMMAND_3x_PRAM+2B↓o
                                        ; COMMAND_3x_PRAM+8A↓o
PRAM_BUFFER_10: BLKB $32                ; DATA XREF: COMMAND_3x_PRAM:COMMAND_31_pramWrite↓o
                                        ; COMMAND_3x_PRAM+71↓o
PRAM_BAT_LOW_LEVEL: BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+1A↓w
                                        ; CHECK_BAT_STATUS+28↓r ...
PRAM_BAT_DEAD_LEVEL: BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+1D↓w
                                        ; CHECK_BAT_STATUS+32↓r ...
PRAM_BAT_44: BLKB $3C                ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+20↓w
                                        ; CHECK_BAT_STATUS+3↓r ...
PRAM_CHKSUM:    BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+26↓w
                                        ; CHECK_BAT_STATUS+87↓w ...
STACK_BOTTOM:   BLKB $F
STACK_TOP:      BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE:loc_E85E↓o
                                        ; COMMAND_7x_SLEEP+38↓o
RAMTOP_PLUS_1:  BLKB $20                ; DATA XREF: CHECK_RAM_RW↓o

; I/O Registers
PORT_P0:        BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE:_TIME_VALID↓r
                                        ; VECTOR_INT2_RESET_CONTINUE:loc_E8A8↓w ...
PORT_P0_DIR:    BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+4E↓w
PORT_P1:        BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+51↓w
                                        ; VECTOR_INT2_RESET_CONTINUE+91↓w ...
PORT_P1_DIR:    BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+54↓w
PORT_P2:        BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+57↓w
                                        ; MAIN_LOOP:IRQ_60HZ_TRIGGERED↓w ...
PORT_P2_DIR:    BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+5A↓w
                                        ; MAIN_LOOP↓w ...
                BLKB 1
SFR_E7_unused:  BLKB 1                  ; [FIX] $E7 is not an SFR. The XREFs below are bogus: IDA took the low byte
                                        ; of CHECK_RAM_DATA_TAB ($F2E7) as a zero-page offset.
                                        ;                 ; DATA XREF: CHECK_RAM_BITS:loc_F292↓o
                                        ; CHECK_RAM_BITS:loc_F29F↓o ...
PORT_P3:        BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+5D↓w
                                        ; VECTOR_INT2_RESET_CONTINUE+97↓r ...
PORT_P3_DIR:    BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+60↓w
PORT_P4:        BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+63↓w
                                        ; MAIN_LOOP+62↓w ...
PORT_P4_DIR:    BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+66↓w
                BLKB 1
                BLKB 1
IN:             BLKB 1                  ; DATA XREF: COMMAND_1x_POWER+4A↓r
                                        ; COMMAND_5x_MODEM:loc_F045↓r ...
AD:             BLKB 1                  ; DATA XREF: BATTERY_READ_SUM+11↓r
                                        ; BATTERY_READ_SUM+2A↓r ...
SFR_F0_unused:         BLKB 1
                BLKB 1
AD_START:       BLKB 1                  ; DATA XREF: BATTERY_READ_SUM+9↓w
                                        ; BATTERY_READ_SUM+22↓w ...
AD_CTRL:        BLKB 1                  ; bits 0-2: channel IN0-IN7, bit 3: 1 = A-D drives IRQ_CTRL bit 5
                BLKB 1                  ; $F4 unused
                                        ;                 ; DATA XREF: BATTERY_READ_SUM↓w
                                        ; BATTERY_READ_SUM+2↓w ...
PWM_CTRL:       BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+8C↓w
                                        ; COMMAND_7x_SLEEP+58↓w ...
SERIAL_IO_MODE: BLKB 1
SERIAL_IO:      BLKB 1
                BLKB 1
TIMER_12_PRES:  BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+6F↓w
TIMER1:         BLKB 1                  ; DATA XREF: SETUP_CONTRAST_TIMER+12↓w
TIMER2:         BLKB 1                  ; DATA XREF: SETUP_CONTRAST_TIMER+D↓w
TIMERX_PRES:    BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+72↓w
                                        ; VECTOR_INT2_RESET_CONTINUE+75↓w
TIMERX:         BLKB 1
IRQ_CTRL:       BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+6C↓w
                                        ; VECTOR_INT2_RESET_CONTINUE:IRQ_WAIT↓r ...
TIMER_CTRL:     BLKB 1                  ; DATA XREF: VECTOR_INT2_RESET_CONTINUE+69↓w
; end of 'RAM'

; ===========================================================================

; Segment type: Pure code
                RSEG ROM
                ORG $E800

; =============== S U B R O U T I N E =======================================


; Power-on reset entry ($FFFE). Bytes $E802-$E859 are the ROM header (version, checksum,
; signature, copyright) and are skipped.
;
VECTOR_RESET:                           ; DATA XREF: CHECK_ROM_CHECKSUM↓t
                                        ; ROM:FFFE↓o
                bra     RESET
; ---------------------------------------------------------------------------
ROM_VERSION:    BYTE   2,181            ; $02,$B5 returned by readPmgrVers ($EA)
                                        ;           ; DATA XREF: COMMAND_Ex_INTERNAL:COMMAND_EA_readPmgrVers↓r
                                        ; COMMAND_Ex_INTERNAL+3E↓r
ROM_CHECKSUM:   BYTE $76,$44            ; [FIX] big-endian checksum $7644 over $E806-$FFFF (CHECK_ROM_CHECKSUM)
                                        ;             ; DATA XREF: CHECK_ROM_CHECKSUM:loc_F272↓r
                                        ; CHECK_ROM_CHECKSUM+3A↓r
aMATT:          BYTE 'M','A','T','T'   ; signature the host must send with sleepReq ($7F)
aBUGS:          BYTE 'B','u','g','s'
                BYTE $A8                ; (c) in Macintosh encoding
aCopyrightApple:BYTE "Copyright Apple Computer Inc  1987, 1988, 1989 Written by Micha"
                BYTE "el Hanlon "
; ---------------------------------------------------------------------------

; Cold reset: Y = CMD_78_BITMASK_RESET so the host sees bit 3 in readINT.
;
RESET:                                  ; CODE XREF: VECTOR_RESET↑j
                ldy     #CMD_78_BITMASK_RESET
                bra     loc_E85E
; End of function VECTOR_RESET


; =============== S U B R O U T I N E =======================================


; Common initialisation. Entered with Y=8 (cold reset) or Y=0 (warm: reset/interrupt switch,
; via VECTOR_INT2_RESET).
;  - validate XPRAM checksum, else clear XPRAM and load default battery thresholds
;  - keep the clock if its checksum is valid, else clear clock + alarm
;  - cold: all power planes off. warm: everything on, HD power left as it was
;  - init ports, timers, A-D, contrast PWM; release the keyboard controller reset
;  - cold reset with P32 high (normal case): go straight to ENTER_SLEEP; the Portable stays
;    off until a key is pressed. P32 low (test/forced on) or warm reset: wait 2 ticks,
;    release SYS_RST, pulse the sound latch clear, enable INT2 and enter MAIN_LOOP.
;
VECTOR_INT2_RESET_CONTINUE:             ; CODE XREF: VECTOR_INT2_RESET+14↓j
                ldy     #0

loc_E85E:                               ; CODE XREF: VECTOR_RESET+5A↑j
                ldx     #STACK_TOP
                txs
                clt
                sei
                cld

                jsr     PRAM_IS_VALID
                bcc     _PRAM_VALID     ; valid => yes
                ldx     #0
                lda     #0

_PRAM_CLR_LOOP:                         ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+14↓j
                sta     PRAM_BUFFER, X  ; Erase XPRAM ($2F…$AE)
                inx
                bpl     _PRAM_CLR_LOOP
                sta     BAT_CHG_FLAGS   ; clear all battery flags
                sta     BAT_HICHG_STATE       ; reset battery state
                ldm     #78, PRAM_BAT_LOW_LEVEL ; Battery state in the PRAM
                ldm     #62, PRAM_BAT_DEAD_LEVEL
                ldm     #200, PRAM_BAT_44 ; only read by dead code in CHECK_BAT_STATUS
                jsr     PRAM_IS_VALID
                sta     PRAM_CHKSUM     ; store new checksum

_PRAM_VALID:                            ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+B↑j
                lda     #0
                sta     FLAGS
                sta     ADB_FLAGS

                jsr     TIME_CALC_CHECKSUM
                cmp     TIME_CHECKSUM
                beq     _TIME_VALID
                ldx     #9
                lda     #0

_TIME_CLR_LOOP:                         ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+3C↓j
                sta     IRQ_60Hz_COUNTER, X
                dex
                bpl     _TIME_CLR_LOOP


_TIME_VALID:                            ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+33↑j
                lda     PORT_P0
                and     #M_P02_HD_PWR
                ora     #M_P06_neg5_EN
                sty     CMD_78_STATE

                tst     CMD_78_STATE
                beq     loc_E8A8
                lda     #M_P00_IWM_CNTRL|M_P01_SCC_CNTRL|M_P02_HD_PWR|M_P03_MODEM_PWR|M_P04_SERIAL_PWR|M_P07_SYS_PWR

loc_E8A8:                               ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+48↑j
                                        ; COMMAND_Ex_INTERNAL+B↓j
                sta     PORT_P0
                ldm     #0b11111111, PORT_P0_DIR
                ldm     #M_P10_N_C|M_P16_RING_DETECT|M_P17_MODEM_AB, PORT_P1 ; not connected in the schematics
                ldm     #0b10110101, PORT_P1_DIR
                ldm     #0b11111111, PORT_P2
                ldm     #0b00000000, PORT_P2_DIR
                ldm     #M_P30_RESET|M_P32_VIA_TEST|M_P34_1_SEC|M_P35_PMINT|M_P36_PMACK|M_P37_PMREQ, PORT_P3
                ldm     #0b01111010, PORT_P3_DIR
                ldm     #M_P41_MASK_ADB_IN|M_P42_DISP_BLANK|M_P43_MODEM_INS, PORT_P4 ; [FIX] P4 masks, not P3 masks ($0E)
                ldm     #0b00000101, PORT_P4_DIR

                ldm     #0, TIMER_CTRL  ; Timer off
                ldm     #0, IRQ_CTRL
                ldm     #4, TIMER_12_PRES
                ldm     #1, TIMERX_PRES
                ldm     #1, TIMERX_PRES ; sic: written twice in the ROM (TIMERX was probably meant). Timer X is unused.

                lda     CONTRAST_TIMER_VALUE
                bmi     loc_E8DE
                beq     loc_E8DE
                cmp     #32
                bcc     loc_E8E1

loc_E8DE:                               ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+7A↑j
                                        ; VECTOR_INT2_RESET_CONTINUE+7C↑j
                ldm     #4, CONTRAST_TIMER_VALUE

loc_E8E1:                               ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+80↑j
                lda     CONTRAST_TIMER_VALUE
                sta     PARAMETER
                jsr     SETUP_CONTRAST_TIMER
                seb     PWM_CTRL_FLAGS_PWM_EN, PWM_CTRL ; contrast PWM output

                jsr     BATTERY_READ
                seb     P14_KBD_RST, PORT_P1 ; resets keyboard M50740

                cpy     #0
                beq     loc_E8F9        ; Wait for 1/30s
                bbc     P32_VIA_TEST, PORT_P3, loc_E8F9 ; Wait for 1/30s
                jmp     ENTER_SLEEP
; ---------------------------------------------------------------------------

loc_E8F9:                               ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+95↑j
                                        ; VECTOR_INT2_RESET_CONTINUE+97↑j
                ldx     #2              ; Wait for 1/30s

IRQ_WAIT:                               ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+A1↓j
                                        ; VECTOR_INT2_RESET_CONTINUE+A7↓j
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     IRQ_WAIT        ; Test if 60Hz IRQ triggered
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery
                dex
                bne     IRQ_WAIT        ; Test if 60Hz IRQ triggered

                seb     P31_SYS_RST, PORT_P3 ; Reset line output to 680x0 and many other chips
                seb     P05_SOUND_PWR, PORT_P0 ; SOUND PWR/
                clb     P05_SOUND_PWR, PORT_P0 ; SOUND PWR/
                clb     IRQ_CTRL_FLAGS_INT2_IRQ_REQ, IRQ_CTRL ; INT2 pin interrupt request bit
                seb     IRQ_CTRL_FLAGS_INT2_EN, IRQ_CTRL ; INT2 pin interrupt enable bit
                cli
; End of function VECTOR_INT2_RESET_CONTINUE


; =============== S U B R O U T I N E =======================================


; Main loop: poll for (a) the 60 Hz INT1 request, (b) a pending pMgrADB command, (c) PMREQ low
; (host wants to send a command). Commands $78 and $28 are handled directly, others through
; command_table indexed by the command's high nibble (JSR (PTR)).
; On every 60 Hz tick: clock/alarm/battery (IRQ_60Hz), then ADB auto-poll if enabled and the
; previous ADB result was read, then pulse /PMINT if an interrupt cause is pending.
; While busy P2 drives $07 onto the PMGR data bus (reason unknown).
;
MAIN_LOOP:                              ; CODE XREF: MAIN_LOOP+10↓j
                                        ; MAIN_LOOP+1B↓j ...
                ldm     #0, PORT_P2_DIR
; Polling for 1/60Hz IRQ or ADB or PMREQ

loc_E913:                               ; CODE XREF: MAIN_LOOP+A↓j
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bmi     IRQ_60HZ_TRIGGERED

                bbs     ADB_STATUS_BITS_PENDING, ADB_FLAGS, loc_E95C
                bbs     P37_PMREQ, PORT_P3, loc_E913 ; Test if 60Hz IRQ triggered

                jsr     READ_COMMAND
                bcs     MAIN_LOOP

                lda     COMMAND
                cmp     #PowerManagerCommands_78_readINT ; get PMGR interrupt data
                bne     loc_E92D
                jsr     COMMAND_78_readINT
                bra     MAIN_LOOP
; ---------------------------------------------------------------------------

loc_E92D:                               ; CODE XREF: MAIN_LOOP+16↑j
                cmp     #PowerManagerCommands_28_readADB ; Apple Desktop Bus
                bne     loc_E936        ; The top 4 bits of the command are used for the jump table
                jsr     COMMAND_28_readADB
                bra     MAIN_LOOP
; ---------------------------------------------------------------------------

loc_E936:                               ; CODE XREF: MAIN_LOOP+1F↑j
                and     #$F0            ; The top 4 bits of the command are used for the jump table
                lsr     A
                lsr     A
                lsr     A
                tax
                lda     command_table, X
                sta     PTR
                lda     command_table+1, X
                sta     PTR+1
                jsr     (PTR)
                bra     MAIN_LOOP
; ---------------------------------------------------------------------------

IRQ_60HZ_TRIGGERED:                     ; CODE XREF: MAIN_LOOP+5↑j
                ldm     #7, PORT_P2
                ldm     #$FF, PORT_P2_DIR

                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery
                bbs     CMD_78_BITS_ADB_IRQ, CMD_78_STATE, loc_E998
                bbs     ADB_STATUS_BITS_PENDING, ADB_FLAGS, loc_E95C
                bbc     ADB_STATUS_BITS_AUTOPOLL, ADB_FLAGS, loc_E998

loc_E95C:                               ; CODE XREF: MAIN_LOOP+7↑j
                                        ; MAIN_LOOP+46↑j
                ldm     #7, PORT_P2
                ldm     #$FF, PORT_P2_DIR



                lda     ADB_FLAGS
                and     #0b00000101
                sta     ADB_FLAGS
                lda     ADB_SEND_SIZE
                sta     BUFFER_CNT
                lda     ADB_COMMAND
                and     #$F
                bne     loc_E982
                seb     P40_PMGR_ADB, PORT_P4 ; ADB Reset Command
                ldx     #0
                jsr     \DELAY_LOOP_X
                jsr     \DELAY_LOOP_X   ; 3 x 256 loops = ~4.6ms ADB reset pulse (spec: >= 3ms)
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                seb     ADB_STATUS_BITS_NO_DATA, ADB_FLAGS
                bra     loc_E996
; ---------------------------------------------------------------------------

loc_E982:                               ; CODE XREF: MAIN_LOOP+60↑j
                jsr     ADB_SEND_CMD
                bcc     loc_E98B
                seb     ADB_STATUS_BITS_NO_DATA, ADB_FLAGS
                bra     loc_E996
; ---------------------------------------------------------------------------

loc_E98B:                               ; CODE XREF: MAIN_LOOP+75↑j
                jsr     ADB_RECEIVE_CMD
                bcc     loc_E996
                bbc     ADB_STATUS_BITS_AUTOPOLL, ADB_FLAGS, loc_E996
                bbc     ADB_STATUS_BITS_SRQ, ADB_FLAGS, loc_E998

loc_E996:                               ; CODE XREF: MAIN_LOOP+70↑j
                                        ; MAIN_LOOP+79↑j ...
                seb     CMD_78_BITS_ADB_IRQ, CMD_78_STATE



loc_E998:                               ; CODE XREF: MAIN_LOOP+43↑j
                                        ; MAIN_LOOP+49↑j ...
                lda     CMD_78_STATE
                and     #CMD_78_BITMASK_ADB_IRQ|CMD_78_BITMASK_BATT_IRQ|CMD_78_BITMASK_BATT_2
                beq     loc_E9A4
                clb     P35_PMINT, PORT_P3 ; CB1 (Pin 19) on VIA 65C22 V14H
                seb     FLAGS_Bits_PMINT_SENT, FLAGS
                seb     P35_PMINT, PORT_P3 ; CB1 (Pin 19) on VIA 65C22 V14H

loc_E9A4:                               ; CODE XREF: MAIN_LOOP+8C↑j
                jmp     MAIN_LOOP
; End of function MAIN_LOOP


; =============== S U B R O U T I N E =======================================


; Receive command byte and count from the host. READ_PARAMETER/READ_BYTES read COMMAND_SIZE
; bytes to (PTR). Carry set = handshake timeout. NOTE: COMMAND_SIZE is not limited to the 8
; byte PARAMETER buffer.
;
READ_COMMAND:                           ; CODE XREF: MAIN_LOOP+D↑p
                jsr     READ_BYTE
                bcs     READ_FAILED
                sta     COMMAND
                jsr     READ_BYTE
                bcs     READ_FAILED
                sta     COMMAND_SIZE
                rts
; ---------------------------------------------------------------------------

READ_PARAMETER:                         ; CODE XREF: COMMAND_1x_POWER+B↓p
                                        ; COMMAND_2x_ADB:COMMAND_20_pMgrADB↓p ...
                ldm     #PARAMETER, PTR
                ldm     #0, PTR+1

READ_BYTES:                             ; CODE XREF: COMMAND_3x_PRAM+12↓p
                                        ; COMMAND_3x_PRAM+28↓p ...
                ldy     #0

READ_BYTES_LOOP:                        ; CODE XREF: READ_COMMAND+21↓j
                jsr     READ_BYTE
                bcs     READ_FAILED
                sta     (PTR), Y
                iny
                dec     COMMAND_SIZE
                bne     READ_BYTES_LOOP
                clc

READ_FAILED:                            ; CODE XREF: READ_COMMAND+3↑j
                                        ; READ_COMMAND+A↑j ...
                rts
; End of function READ_COMMAND


; =============== S U B R O U T I N E =======================================


; Receive one byte from the host: wait (~45 us) for PMREQ low, read P2, PMACK low, wait for
; PMREQ high, PMACK high. Carry set = timeout.
;
READ_BYTE:                              ; CODE XREF: READ_COMMAND↑p
                                        ; READ_COMMAND+7↑p ...
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbc     P37_PMREQ, PORT_P3, loc_E9E9 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bra     loc_EA08
; ---------------------------------------------------------------------------

loc_E9E9:                               ; CODE XREF: READ_BYTE↑j
                                        ; READ_BYTE+3↑j ...
                lda     PORT_P2
                clb     P36_PMACK, PORT_P3 ; PB1 (Pin 12) on VIA 65C22 V14H: PMAck handshake flag to the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bbs     P37_PMREQ, PORT_P3, loc_EA0C ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA

loc_EA08:                               ; CODE XREF: READ_BYTE+1B↑j
                seb     P36_PMACK, PORT_P3 ; PB1 (Pin 12) on VIA 65C22 V14H: PMAck handshake flag to the VIA
                sec
                rts
; ---------------------------------------------------------------------------

loc_EA0C:                               ; CODE XREF: READ_BYTE+21↑j
                                        ; READ_BYTE+24↑j ...
                seb     P36_PMACK, PORT_P3 ; PB1 (Pin 12) on VIA 65C22 V14H: PMAck handshake flag to the VIA
                clc
                rts
; End of function READ_BYTE


; =============== S U B R O U T I N E =======================================


; Send COMMAND, COMMAND_SIZE and COMMAND_SIZE bytes from PARAMETER (or from (PTR) when
; entered at SEND_COMMAND, from (PTR),Y at SEND_BUFFER) to the host.
;
SEND_COMMAND_PARAMETER:                 ; CODE XREF: COMMAND_1x_POWER+50↓p
                                        ; COMMAND_4x_SCREEN_CONTRAST+A↓p ...
                ldm     #PARAMETER, PTR
                ldm     #0, PTR+1

SEND_COMMAND:                           ; CODE XREF: COMMAND_28_readADB+D↓p
                                        ; COMMAND_3x_PRAM+66↓p ...
                lda     COMMAND
                jsr     SEND_BYTE
                bcs     locret_EA37
                lda     COMMAND_SIZE
                jsr     SEND_BYTE
                bcs     locret_EA37
                tst     COMMAND_SIZE
                beq     locret_EA37
                ldy     #0

SEND_BUFFER:                            ; CODE XREF: SEND_COMMAND_PARAMETER+24↓j
                                        ; COMMAND_3x_PRAM+87↓p ...
                lda     (PTR), Y
                jsr     SEND_BYTE
                bcs     locret_EA37
                iny
                dec     COMMAND_SIZE
                bne     SEND_BUFFER
                clc

locret_EA37:                            ; CODE XREF: SEND_COMMAND_PARAMETER+B↑j
                                        ; SEND_COMMAND_PARAMETER+12↑j ...
                rts
; End of function SEND_COMMAND_PARAMETER


; =============== S U B R O U T I N E =======================================


; Send one byte: PMREQ must be high (else fail), drive P2, PMACK low ("data valid"), wait up
; to ~4 ms for the host to pull PMREQ low, PMACK high, release the bus. Carry set = timeout.
;
SEND_BYTE:                              ; CODE XREF: SEND_COMMAND_PARAMETER+8↑p
                                        ; SEND_COMMAND_PARAMETER+F↑p ...
                bbc     P37_PMREQ, PORT_P3, loc_EA50 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                ldm     #$FF, PORT_P2_DIR
                sta     PORT_P2
                clb     P36_PMACK, PORT_P3 ; PB1 (Pin 12) on VIA 65C22 V14H: PMAck handshake flag to the VIA
                bbc     P37_PMREQ, PORT_P3, loc_EA57 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                ldx     #0

loc_EA47:                               ; CODE XREF: SEND_BYTE+16↓j
                bbc     P37_PMREQ, PORT_P3, loc_EA57 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                dex
                bbc     P37_PMREQ, PORT_P3, loc_EA57 ; PM0 (Pin 10) on VIA 65C22 V14H: PMReq handshake flag from the VIA
                bne     loc_EA47

loc_EA50:                               ; CODE XREF: SEND_BYTE↑j
                seb     P36_PMACK, PORT_P3 ; PB1 (Pin 12) on VIA 65C22 V14H: PMAck handshake flag to the VIA
                ldm     #0, PORT_P2_DIR
                sec
                rts
; ---------------------------------------------------------------------------

loc_EA57:                               ; CODE XREF: SEND_BYTE+A↑j
                                        ; SEND_BYTE:loc_EA47↑j ...
                seb     P36_PMACK, PORT_P3 ; PB1 (Pin 12) on VIA 65C22 V14H: PMAck handshake flag to the VIA
                ldm     #0, PORT_P2_DIR
                clc
                rts
; End of function SEND_BYTE


; =============== S U B R O U T I N E =======================================


; Called every 1/60 s. Filters the battery voltage and maintains BAT_CHG_FLAGS:
;  - charger plugged/unplugged -> CHARGER_CHANGED + battery interrupt
;  - charger connected: high-rate charge state machine (BAT_HICHG_STATE)
;  - on battery: compare against the XPRAM thresholds $42 (low, default 78) and $43 (dead,
;    default 62; invalid values outside 59..89 or low<dead restore the defaults).
;    Dead battery while awake and P32 high -> ENTER_SLEEP (forced shutdown).
;
CHECK_BAT_STATUS:                       ; CODE XREF: IRQ_60Hz:ALARM_INACTIVE↓p
                jsr     BATTERY_READ_SUM

                lda     PRAM_BAT_44
                cmp     #220
                bcc     loc_EA69        ; clip value to be a max of 220
                lda     #220

loc_EA69:                               ; CODE XREF: CHECK_BAT_STATUS+7↑j
                cmp     BAT_IN0         ; NOTE: original firmware dead code - the result is never used,
                bcs     loc_EA6D        ; the branch target is the next instruction

loc_EA6D:                               ; CODE XREF: CHECK_BAT_STATUS+D↑j
                lda     BAT_CHG_FLAGS
                asl     A
                asl     A
                asl     A
                eor     PORT_P1         ; BAT_CHG_BITS_CHARGER (shifted to bit 3) XOR P13 /CHRG_ON
                bbs     P13_CHRG_ON, A, loc_EA7D
                seb     CMD_78_BITS_BATT_IRQ, CMD_78_STATE
                seb     BAT_CHG_BITS_CHARGER_CHANGED, BAT_CHG_FLAGS
                jsr     BATTERY_READ

loc_EA7D:                               ; CODE XREF: CHECK_BAT_STATUS+16↑j
                clb     BAT_CHG_BITS_CHARGER, BAT_CHG_FLAGS
                clb     BAT_CHG_BITS_DEAD, BAT_CHG_FLAGS
                clb     BAT_CHG_BITS_VERY_LOW, BAT_CHG_FLAGS
                bbc     P13_CHRG_ON, PORT_P1, CHARGER_CONNECTED

                lda     PRAM_BAT_LOW_LEVEL
                cmp     #90
                bcs     loc_EAD9
                cmp     #59
                bcc     loc_EAD9
                lda     PRAM_BAT_DEAD_LEVEL
                cmp     #90
                bcs     loc_EAD9
                cmp     #59
                bcc     loc_EAD9
                lda     PRAM_BAT_LOW_LEVEL
                cmp     PRAM_BAT_DEAD_LEVEL
                bcc     loc_EAD9

loc_EAA0:                               ; CODE XREF: CHECK_BAT_STATUS+89↓j
                lda     PRAM_BAT_LOW_LEVEL
                lsr     A
                sta     BAT_VERY_LOW_LEVEL
                lda     PRAM_BAT_DEAD_LEVEL
                lsr     A
                clc
                adc     BAT_VERY_LOW_LEVEL
                sta     BAT_VERY_LOW_LEVEL

                lda     BAT_VOLTAGE
                cmp     PRAM_BAT_LOW_LEVEL
                bcc     loc_EABC
                bbc     BAT_CHG_BITS_LOW, BAT_CHG_FLAGS, loc_EAD5
                clb     BAT_CHG_BITS_LOW, BAT_CHG_FLAGS
                seb     CMD_78_BITS_BATT_IRQ, CMD_78_STATE
                bra     loc_EAD5
; ---------------------------------------------------------------------------

loc_EABC:                               ; CODE XREF: CHECK_BAT_STATUS+53↑j
                seb     BAT_CHG_BITS_LOW, BAT_CHG_FLAGS
                seb     CMD_78_BITS_BATT_IRQ, CMD_78_STATE
                cmp     BAT_VERY_LOW_LEVEL
                bcs     loc_EAD5
                seb     BAT_CHG_BITS_VERY_LOW, BAT_CHG_FLAGS
                cmp     PRAM_BAT_DEAD_LEVEL
                bcs     loc_EAD5
                seb     BAT_CHG_BITS_DEAD, BAT_CHG_FLAGS
                bbs     FLAGS_Bits_SLEEPING, FLAGS, loc_EAD5
                bbc     P32_VIA_TEST, PORT_P3, loc_EAD5 ; PB2 (Pin 13) on VIA 65C22 V14H
                jmp     ENTER_SLEEP
; ---------------------------------------------------------------------------

loc_EAD5:                               ; CODE XREF: CHECK_BAT_STATUS+55↑j
                                        ; CHECK_BAT_STATUS+5C↑j ...
                ldm     #BAT_STATE_TYPE_0, BAT_HICHG_STATE
                rts
; ---------------------------------------------------------------------------

loc_EAD9:                               ; CODE XREF: CHECK_BAT_STATUS+2C↑j
                                        ; CHECK_BAT_STATUS+30↑j ...
                ldm     #78, PRAM_BAT_LOW_LEVEL
                ldm     #62, PRAM_BAT_DEAD_LEVEL
                ldm     #200, PRAM_BAT_44 ; only read by dead code in CHECK_BAT_STATUS
                jsr     PRAM_IS_VALID
                sta     PRAM_CHKSUM
                bra     loc_EAA0
; ---------------------------------------------------------------------------

CHARGER_CONNECTED:                           ; CODE XREF: CHECK_BAT_STATUS+25↑j
                seb     BAT_CHG_BITS_CHARGER, BAT_CHG_FLAGS
                clb     BAT_CHG_BITS_LOW, BAT_CHG_FLAGS

                lda     BAT_HICHG_STATE
                bne     loc_EB03
; State 0
                seb     P15_HICHG, PORT_P1
                seb     5, PARAMETER+1
                seb     BAT_CHG_BITS_HICHARGE_ON, BAT_CHG_FLAGS
                ldm     #BAT_STATE_TYPE_1, BAT_HICHG_STATE
                ldm     #1, BAT_COUNT_A
                ldm     #1, BAT_COUNT_B
                clb     BAT_CHG_BITS_HICHARGE_OVF, BAT_CHG_FLAGS
                rts
; ---------------------------------------------------------------------------

loc_EB03:                               ; CODE XREF: CHECK_BAT_STATUS+91↑j
                cmp     #BAT_STATE_TYPE_2
                bcs     loc_EB1F
; State 1
                lda     BAT_VOLTAGE
                cmp     #208
                bcs     loc_EB1B
                bbs     BAT_CHG_BITS_HICHARGE_OVF, BAT_CHG_FLAGS, loc_EB32 ; State 3
                inc     BAT_COUNT_A
                bne     loc_EB32        ; State 3
                inc     BAT_COUNT_B
                bne     loc_EB32        ; State 3
                seb     BAT_CHG_BITS_HICHARGE_OVF, BAT_CHG_FLAGS
                rts
; ---------------------------------------------------------------------------

loc_EB1B:                               ; CODE XREF: CHECK_BAT_STATUS+AD↑j
                ldm     #BAT_STATE_TYPE_2, BAT_HICHG_STATE
                rts
; ---------------------------------------------------------------------------

loc_EB1F:                               ; CODE XREF: CHECK_BAT_STATUS+A7↑j
                bne     loc_EB32        ; State 3
; State 2
                dec     BAT_COUNT_A
                bne     loc_EB32        ; State 3
                dec     BAT_COUNT_B
                bne     loc_EB32        ; State 3
                ldm     #BAT_STATE_TYPE_3, BAT_HICHG_STATE
                clb     P15_HICHG, PORT_P1
                clb     5, PARAMETER+1
                clb     BAT_CHG_BITS_HICHARGE_ON, BAT_CHG_FLAGS

loc_EB32:                               ; CODE XREF: CHECK_BAT_STATUS+AF↑j
                                        ; CHECK_BAT_STATUS+B4↑j ...
                lda     BAT_VOLTAGE ; State 3
                cmp     #90
                bcc     loc_EAD5
                rts
; End of function CHECK_BAT_STATUS


; =============== S U B R O U T I N E =======================================


; A-D: IN1 = battery voltage, low-pass filtered (old+new)/2 into BAT_VOLTAGE; IN0 (unknown
; analog input, maybe temperature) into BAT_IN0. Busy-waits on the A-D complete flag.
;
BATTERY_READ_SUM:                       ; CODE XREF: CHECK_BAT_STATUS↑p
                clb     3, AD_CTRL
                ldm     #1, AD_CTRL     ; select IN1 (A/D_FILTER)
                seb     3, AD_CTRL      ; A-D is the interrupt source
                clb     IRQ_CTRL_FLAGS_TIM1_AD_REQ, IRQ_CTRL ; reset A-D result
                ldm     #0, AD_START    ; start the A/D conversion

_BATTERY_READ_LOOP_A:                   ; CODE XREF: BATTERY_READ_SUM+F↓j
                lda     IRQ_CTRL        ; wait for the result
                nop
                bbc     IRQ_CTRL_FLAGS_TIM1_AD_REQ, A, _BATTERY_READ_LOOP_A ; wait for the result
                lda     AD              ; load A/D result
                clc
                adc     BAT_VOLTAGE ; state = (state + AD) / 2
                ror     A
                sta     BAT_VOLTAGE
                clb     3, AD_CTRL
                ldm     #0, AD_CTRL     ; select IN0 (PMGR_IN0)
                seb     3, AD_CTRL      ; A-D is the interrupt source
                clb     IRQ_CTRL_FLAGS_TIM1_AD_REQ, IRQ_CTRL ; reset A-D request flag
                ldm     #0, AD_START    ; start the A/D conversion

_BATTERY_READ_LOOP_B:                   ; CODE XREF: BATTERY_READ_SUM+28↓j
                lda     IRQ_CTRL
                nop
                bbc     IRQ_CTRL_FLAGS_TIM1_AD_REQ, A, _BATTERY_READ_LOOP_B ; wait for the result
                lda     AD
                sta     BAT_IN0
                clb     3, AD_CTRL
                rts
; End of function BATTERY_READ_SUM


; =============== S U B R O U T I N E =======================================


; Same as BATTERY_READ_SUM but stores the unfiltered voltage (batteryNow $69, charger change).
;
BATTERY_READ:                           ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+8E↑p
                                        ; CHECK_BAT_STATUS+1C↑p ...
                clb     3, AD_CTRL
                ldm     #1, AD_CTRL     ; select IN1 (A/D_FILTER)
                seb     3, AD_CTRL
                clb     IRQ_CTRL_FLAGS_TIM1_AD_REQ, IRQ_CTRL ; reset A-D request flag
                ldm     #0, AD_START

_COMMAND_69_LOOP_A:                     ; CODE XREF: BATTERY_READ+F↓j
                lda     IRQ_CTRL
                nop
                bbc     IRQ_CTRL_FLAGS_TIM1_AD_REQ, A, _COMMAND_69_LOOP_A ; wait for the A-D result
                lda     AD
                sta     BAT_VOLTAGE
                clb     3, AD_CTRL
                ldm     #0, AD_CTRL     ; select IN0 (PMGR_IN0)
                seb     3, AD_CTRL
                clb     IRQ_CTRL_FLAGS_TIM1_AD_REQ, IRQ_CTRL ; reset A-D request flag
                ldm     #0, AD_START

_COMMAND_69_LOOP_B:                     ; CODE XREF: BATTERY_READ+24↓j
                lda     IRQ_CTRL
                nop
                bbc     IRQ_CTRL_FLAGS_TIM1_AD_REQ, A, _COMMAND_69_LOOP_B ; wait for the A-D result
                lda     AD
                sta     BAT_IN0
                clb     3, AD_CTRL
                rts
; End of function BATTERY_READ


; =============== S U B R O U T I N E =======================================

; Called at 60Hz to increment time, check alarm and battery

; Called on every INT1 request (60.15 Hz). If awake and P32 low, force the power planes on.
; Every 60th call: 1 Hz pulse to VIA CA1, increment the 32-bit seconds counter, update its
; checksum, check the alarm (only while sleeping). Always runs CHECK_BAT_STATUS.
;
IRQ_60Hz:                               ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+A3↑p
                                        ; MAIN_LOOP+40↑p ...
                clb     IRQ_CTRL_FLAGS_INT1_REQ, IRQ_CTRL ; INT1 pin interrupt request bit
                clb     FLAGS_Bits_ALARM_TRIGGERED, FLAGS ; 1:Alarm time was triggered
                bbs     FLAGS_Bits_SLEEPING, FLAGS, loc_EBA6
                bbs     P32_VIA_TEST, PORT_P3, loc_EBA6 ; PB2 (Pin 13) on VIA 65C22 V14H
                ldm     #M_P03_MODEM_PWR|M_P06_neg5_EN, PORT_P0
                seb     P10_N_C, PORT_P1

loc_EBA6:                               ; CODE XREF: IRQ_60Hz+4↑j
                                        ; IRQ_60Hz+7↑j
                dec     IRQ_60Hz_COUNTER
                beq     IRQ_1Hz
                rts
; ---------------------------------------------------------------------------

IRQ_1Hz:                                ; CODE XREF: IRQ_60Hz+11↑j
                clb     P34_1SEC, PORT_P3 ; CA1 (Pin 44) on VIA 65C22 V14H
                seb     P34_1SEC, PORT_P3 ; Send 1Hz Pulse to the VIA (CA1)
                ldm     #60, IRQ_60Hz_COUNTER

                inc     TIME_S+3
                bne     loc_EBC0
                inc     TIME_S+2
                bne     loc_EBC0
                inc     TIME_S+1
                bne     loc_EBC0
                inc     TIME_S

loc_EBC0:                               ; CODE XREF: IRQ_60Hz+1D↑j
                                        ; IRQ_60Hz+21↑j ...
                jsr     TIME_CALC_CHECKSUM
                sta     TIME_CHECKSUM

                bbc     FLAGS_Bits_ALARM_SET, FLAGS, ALARM_INACTIVE ; 1:Alarm is enabled
                bbc     FLAGS_Bits_SLEEPING, FLAGS, ALARM_INACTIVE
                bbs     FLAGS_Bits_ALARM_TRIGGERED, FLAGS, ALARM_INACTIVE ; 1:Alarm time was triggered
                lda     ALARM_TIME+3
                cmp     TIME_S+3
                bne     ALARM_INACTIVE
                lda     ALARM_TIME+2
                cmp     TIME_S+2
                bne     ALARM_INACTIVE
                lda     ALARM_TIME+1
                cmp     TIME_S+1
                bne     ALARM_INACTIVE
                lda     ALARM_TIME
                cmp     TIME_S
                bne     ALARM_INACTIVE
                seb     FLAGS_Bits_ALARM_TRIGGERED, FLAGS ; 1:Alarm time was triggered

ALARM_INACTIVE:                         ; CODE XREF: IRQ_60Hz+2E↑j
                                        ; IRQ_60Hz+31↑j ...
                jsr     CHECK_BAT_STATUS
                rts
; End of function IRQ_60Hz


; =============== S U B R O U T I N E =======================================


; Send ADB_COMMAND (and for Listen the BUFFER_CNT data bytes) on the ADB, bit-banged with cycle
; counted loops (1 cycle = 1 us). P40 high pulls the bus low, P41 reads the bus.
;   attention 800 us low, sync ~70 us high, 8 bit cells of 100 us ('0' = 65 us low, '1' = 35 us
;   low), stop bit 65 us low. Line low afterwards for up to ~300 us = SRQ (ADB_STATUS_BITS_SRQ).
;   Listen data: Tlt ~160 us, start bit '1', data bytes, stop bit.
; Carry set = bus error (line did not follow our output).
;
ADB_SEND_CMD:                           ; CODE XREF: MAIN_LOOP:loc_E982↑p
                lda     ADB_FLAGS
                and     #5
                sta     ADB_FLAGS
                lda     ADB_COMMAND
                sta     ADB_SEND_BYTE

; 800µs Attention Signal
                seb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                ldx     #131
                jsr     \DELAY_LOOP_X
                nop
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)

; Sync
                ldx     #6
                jsr     \DELAY_LOOP_X
                bbc     P41_FDB, PORT_P4, adb_send_noAck ; ADB In
                nop
                ldy     #8
                bra     loc_EC10
; ---------------------------------------------------------------------------

adb_send_nextBit:                       ; CODE XREF: ADB_SEND_CMD+41↓j
                ldx     #1
                jsr     \DELAY_LOOP_X
                nop

loc_EC10:                               ; CODE XREF: ADB_SEND_CMD+1D↑j
                seb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                ldx     #2
                jsr     \DELAY_LOOP_X
                rol     ADB_SEND_BYTE
                bcc     loc_EC21
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                bbc     P41_FDB, PORT_P4, adb_send_noAck ; ADB In
                bra     loc_EC23
; ---------------------------------------------------------------------------

loc_EC21:                               ; CODE XREF: ADB_SEND_CMD+2C↑j
                jsr     \DELAY_RTS

loc_EC23:                               ; CODE XREF: ADB_SEND_CMD+33↑j
                ldx     #1
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                bbc     P41_FDB, PORT_P4, adb_send_noAck ; ADB In
                dey
                bne     adb_send_nextBit
                ldx     #1
                jsr     \DELAY_LOOP_X
                nop
                nop                     ; send stop bit
                seb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                ldx     #9
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                bbc     P41_FDB, PORT_P4, loc_EC42 ; ADB In

loc_EC40:                               ; CODE XREF: ADB_SEND_CMD:loc_EC44↓j
                bra     loc_EC60
; ---------------------------------------------------------------------------

loc_EC42:                               ; CODE XREF: ADB_SEND_CMD+51↑j
                ldx     #9

loc_EC44:                               ; CODE XREF: ADB_SEND_CMD+5C↓j
                bbs     P41_FDB, PORT_P4, loc_EC40 ; ADB In
                dex
                bne     loc_EC44
                ldx     #19

loc_EC4C:                               ; CODE XREF: ADB_SEND_CMD+64↓j
                bbs     P41_FDB, PORT_P4, loc_EC54 ; ADB In
                dex
                bne     loc_EC4C
                bra     adb_send_noAck
; ---------------------------------------------------------------------------

loc_EC54:                               ; CODE XREF: ADB_SEND_CMD:loc_EC4C↑j
                seb     ADB_STATUS_BITS_SRQ, ADB_FLAGS
                bra     loc_EC60
; ---------------------------------------------------------------------------

adb_send_noAck:                         ; CODE XREF: ADB_SEND_CMD+17↑j
                                        ; ADB_SEND_CMD+30↑j ...
                seb     ADB_STATUS_BITS_BUS_ERR, ADB_FLAGS
                seb     ADB_STATUS_BITS_ERROR, ADB_FLAGS
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                sec
                rts
; ---------------------------------------------------------------------------

loc_EC60:                               ; CODE XREF: ADB_SEND_CMD:loc_EC40↑j
                                        ; ADB_SEND_CMD+6A↑j
                tst     BUFFER_CNT
                bne     loc_EC66
                clc
                rts
; ---------------------------------------------------------------------------

loc_EC66:                               ; CODE XREF: ADB_SEND_CMD+76↑j
                ldy     #8
                ldx     BUFFER_CNT
                dec     BUFFER_CNT
                lda     BUFFER_CNT, X
                sta     ADB_SEND_BYTE
                ldx     #25
                jsr     \DELAY_LOOP_X
                seb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                nop
                ldx     #3
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                nop
                nop
                ldx     #6
                jsr     \DELAY_LOOP_X
                bbc     P41_FDB, PORT_P4, adb_send_noAck ; ADB In
                bra     loc_EC8D
; ---------------------------------------------------------------------------

loc_EC88:                               ; CODE XREF: ADB_SEND_CMD+BE↓j
                ldx     #1
                jsr     \DELAY_LOOP_X
                nop

loc_EC8D:                               ; CODE XREF: ADB_SEND_CMD+9A↑j
                                        ; ADB_SEND_CMD+CA↓j
                seb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                ldx     #2
                jsr     \DELAY_LOOP_X
                rol     ADB_SEND_BYTE
                bcc     loc_EC9E
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                bbc     P41_FDB, PORT_P4, adb_send_noAck ; ADB In
                bra     loc_ECA0
; ---------------------------------------------------------------------------

loc_EC9E:                               ; CODE XREF: ADB_SEND_CMD+A9↑j
                jsr     \DELAY_RTS

loc_ECA0:                               ; CODE XREF: ADB_SEND_CMD+B0↑j
                ldx     #1
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                bbc     P41_FDB, PORT_P4, adb_send_noAck ; ADB In
                dey
                bne     loc_EC88
                ldy     #8
                ldx     BUFFER_CNT
                lda     BUFFER_CNT, X
                sta     ADB_SEND_BYTE
                dec     BUFFER_CNT
                bpl     loc_EC8D
                nop
                seb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                ldx     #9
                jsr     \DELAY_LOOP_X
                clb     P40_PMGR_ADB, PORT_P4 ; PMGR_ADB (ADB out)
                clc
                rts
; End of function ADB_SEND_CMD


; =============== S U B R O U T I N E =======================================


; Receive a Talk response: wait up to ~256 us (Tlt) for the start bit, then measure each bit
; cell with unrolled BBS/BBC chains (5 us resolution). Bits are shifted into A (starting with 1
; as a sentinel); every full byte is PHAed - S was moved to STACK_TOP_ADB_RECEIVE, so the stack
; is the receive buffer at $08-$0F. Up to 8 bytes; afterwards the bytes are copied in order into
; BUFFER and BUFFER_CNT is set. Carry set = no response/timeout (NO_DATA|ERROR).
;
ADB_RECEIVE_CMD:                        ; CODE XREF: MAIN_LOOP:loc_E98B↑p
                ldm     #0, BUFFER_CNT
                tsx
                stx     TEMP
                ldx     #STACK_TOP_ADB_RECEIVE
                txs
                lda     #1
                ldy     #9
                ldx     #16

loc_ECD2:                               ; CODE XREF: ADB_RECEIVE_CMD+16↓j
                bbc     P41_FDB, PORT_P4, loc_ECE6 ; ADB In
                dex
                bbc     P41_FDB, PORT_P4, loc_ECE6 ; ADB In
                bne     loc_ECD2
                bra     loc_ECDD
; ---------------------------------------------------------------------------

loc_ECDD:                               ; CODE XREF: ADB_RECEIVE_CMD+18↑j
                                        ; ADB_RECEIVE_CMD+25↓j ...
                seb     ADB_STATUS_BITS_ERROR, ADB_FLAGS
                seb     ADB_STATUS_BITS_NO_DATA, ADB_FLAGS
                ldx     TEMP
                txs
                sec
                rts
; ---------------------------------------------------------------------------

loc_ECE6:                               ; CODE XREF: ADB_RECEIVE_CMD:loc_ECD2↑j
                                        ; ADB_RECEIVE_CMD+13↑j
                ldx     #3
                bbs     P41_FDB, PORT_P4, loc_ECDD ; ADB In

loc_ECEB:                               ; CODE XREF: ADB_RECEIVE_CMD+2F↓j
                bbs     P41_FDB, PORT_P4, loc_ECF6 ; ADB In
                dex
                bbs     P41_FDB, PORT_P4, loc_ECF6 ; ADB In
                bne     loc_ECEB
                bra     loc_ECDD
; ---------------------------------------------------------------------------

loc_ECF6:                               ; CODE XREF: ADB_RECEIVE_CMD:loc_ECEB↑j
                                        ; ADB_RECEIVE_CMD+2C↑j
                nop
                nop
                nop
                nop
                bit     TEMP
                bbc     P41_FDB, PORT_P4, loc_ECDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ECDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ECDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_ED28 ; ADB In
                bra     loc_ECDD
; ---------------------------------------------------------------------------

loc_ED28:                               ; CODE XREF: ADB_RECEIVE_CMD+42↑j
                                        ; ADB_RECEIVE_CMD+45↑j ...
                bbs     P41_FDB, PORT_P4, loc_ED8E ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED8B ; ADB In

loc_ED2E:                               ; CODE XREF: ADB_RECEIVE_CMD:loc_EDED↓j
                bbs     P41_FDB, PORT_P4, loc_ED88 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED85 ; ADB In

loc_ED34:                               ; CODE XREF: ADB_RECEIVE_CMD+10E↓j
                                        ; ADB_RECEIVE_CMD+127↓j
                bbs     P41_FDB, PORT_P4, loc_ED82 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED7F ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED7C ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED79 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED76 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED73 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED70 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED6D ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED6A ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED67 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED64 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED61 ; ADB In
                bbs     P41_FDB, PORT_P4, loc_ED5E ; ADB In

loc_ED5B:                               ; CODE XREF: ADB_RECEIVE_CMD+FA↓j
                                        ; ADB_RECEIVE_CMD+FE↓j
                jmp     loc_ECDD
; ---------------------------------------------------------------------------

loc_ED5E:                               ; CODE XREF: ADB_RECEIVE_CMD+95↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED61:                               ; CODE XREF: ADB_RECEIVE_CMD+92↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED64:                               ; CODE XREF: ADB_RECEIVE_CMD+8F↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED67:                               ; CODE XREF: ADB_RECEIVE_CMD+8C↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED6A:                               ; CODE XREF: ADB_RECEIVE_CMD+89↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED6D:                               ; CODE XREF: ADB_RECEIVE_CMD+86↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED70:                               ; CODE XREF: ADB_RECEIVE_CMD+83↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED73:                               ; CODE XREF: ADB_RECEIVE_CMD+80↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED76:                               ; CODE XREF: ADB_RECEIVE_CMD+7D↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED79:                               ; CODE XREF: ADB_RECEIVE_CMD+7A↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED7C:                               ; CODE XREF: ADB_RECEIVE_CMD+77↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED7F:                               ; CODE XREF: ADB_RECEIVE_CMD+74↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED82:                               ; CODE XREF: ADB_RECEIVE_CMD:loc_ED34↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED85:                               ; CODE XREF: ADB_RECEIVE_CMD+6E↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED88:                               ; CODE XREF: ADB_RECEIVE_CMD:loc_ED2E↑j
                                        ; ADB_RECEIVE_CMD+114↓j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED8B:                               ; CODE XREF: ADB_RECEIVE_CMD+68↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In

loc_ED8E:                               ; CODE XREF: ADB_RECEIVE_CMD:loc_ED28↑j
                bbc     P41_FDB, PORT_P4, loc_EDC5 ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                bbc     P41_FDB, PORT_P4, loc_EDDD ; ADB In
                cmp     #1
                bne     loc_ED5B
                cpy     #8
                bcs     loc_ED5B
                bra     loc_EDF0
; ---------------------------------------------------------------------------

loc_EDC5:                               ; CODE XREF: ADB_RECEIVE_CMD:loc_ED5E↑j
                                        ; ADB_RECEIVE_CMD:loc_ED61↑j ...
                asl     A
                bcc     loc_EDED
                pha
                lda     #1
                bbs     P41_FDB, PORT_P4, loc_EDD4 ; ADB In
                dey
                beq     loc_EDDA
                jmp     loc_ED34
; ---------------------------------------------------------------------------

loc_EDD4:                               ; CODE XREF: ADB_RECEIVE_CMD+108↑j
                                        ; ADB_RECEIVE_CMD+121↓j
                dey
                beq     loc_EDDA
                jmp     loc_ED88
; ---------------------------------------------------------------------------

loc_EDDA:                               ; CODE XREF: ADB_RECEIVE_CMD+10C↑j
                                        ; ADB_RECEIVE_CMD+112↑j ...
                jmp     loc_ECDD
; ---------------------------------------------------------------------------

loc_EDDD:                               ; CODE XREF: ADB_RECEIVE_CMD+CE↑j
                                        ; ADB_RECEIVE_CMD+D1↑j ...
                sec
                rol     A
                bcc     loc_EDED
                pha
                lda     #1
                bbs     P41_FDB, PORT_P4, loc_EDD4 ; ADB In
                dey
                beq     loc_EDDA
                jmp     loc_ED34
; ---------------------------------------------------------------------------

loc_EDED:                               ; CODE XREF: ADB_RECEIVE_CMD+103↑j
                                        ; ADB_RECEIVE_CMD+11C↑j
                jmp     loc_ED2E
; ---------------------------------------------------------------------------

loc_EDF0:                               ; CODE XREF: ADB_RECEIVE_CMD+100↑j
                ldx     TEMP
                txs
                tya
                eor     #$FF
                clc
                adc     #10
                sta     BUFFER_CNT
                tay
                beq     loc_EE0F
                ldx     #8

loc_EE00:                               ; CODE XREF: ADB_RECEIVE_CMD+142↓j
                lda     BUFFER, X
                pha
                dex
                dey
                bne     loc_EE00
                ldx     BUFFER_CNT

loc_EE09:                               ; CODE XREF: ADB_RECEIVE_CMD+14A↓j
                pla
                sta     BUFFER_CNT, X
                dex
                bne     loc_EE09

loc_EE0F:                               ; CODE XREF: ADB_RECEIVE_CMD+139↑j
                clc
                rts
; End of function ADB_RECEIVE_CMD

; ---------------------------------------------------------------------------
; Handler per command high nibble ($0x-$Fx). $28 and $78 are dispatched in MAIN_LOOP.
;
command_table:  WORD COMMAND_xx_NOP
                WORD COMMAND_1x_POWER
                WORD COMMAND_2x_ADB
                WORD COMMAND_3x_PRAM
                WORD COMMAND_4x_SCREEN_CONTRAST
                WORD COMMAND_5x_MODEM
                WORD COMMAND_6x_BATTERY
                WORD COMMAND_7x_SLEEP
                WORD COMMAND_8x_WAKEUP
                WORD COMMAND_9x_SOUND
                WORD COMMAND_xx_NOP
                WORD COMMAND_xx_NOP
                WORD COMMAND_xx_NOP
                WORD COMMAND_xx_NOP
                WORD COMMAND_Ex_INTERNAL
                WORD COMMAND_xx_NOP

; =============== S U B R O U T I N E =======================================


COMMAND_xx_NOP:                         ; DATA XREF: ROM:command_table↑o
                                        ; ROM:EE25↑o ...
                clc
                rts
; End of function COMMAND_xx_NOP


; =============== S U B R O U T I N E =======================================


; $10 powerCntl: each parameter byte: bit 7 = 1 turn the selected planes on, 0 = off.
;      P0 bits 0-5,7 are active low (/PWR), bit 6 (-5 V enable) active high; SYS_PWR stays on.
; $18 powerRead: 1 byte, active-high power plane state, bit 5 = sound latch (IN2).
;
COMMAND_1x_POWER:                       ; DATA XREF: ROM:EE13↑o
                bbs     3, COMMAND, COMMAND_18_powerRead

COMMAND_10_powerCntl:                   ; parameters are required!
                tst     COMMAND_SIZE
                bne     loc_EE3B
                rts
; ---------------------------------------------------------------------------

loc_EE3B:                               ; CODE XREF: COMMAND_1x_POWER+5↑j
                lda     COMMAND_SIZE
                pha
                jsr     READ_PARAMETER
                pla
                sta     COMMAND_SIZE
                ldx     #0

loc_EE46:                               ; CODE XREF: COMMAND_1x_POWER+2A↓j
                lda     PARAMETER, X
                bpl     loc_EE61
                eor     #$FF
                and     PORT_P0
                sta     TEMP
                lda     PARAMETER, X
                and     #M_P06_neg5_EN
                ora     TEMP
                sta     PORT_P0
                bra     loc_EE5A
; ---------------------------------------------------------------------------

loc_EE5A:                               ; CODE XREF: COMMAND_1x_POWER+25↑j
                                        ; COMMAND_1x_POWER+3E↓j
                inx
                dec     COMMAND_SIZE
                bne     loc_EE46
                clc
                rts
; ---------------------------------------------------------------------------

loc_EE61:                               ; CODE XREF: COMMAND_1x_POWER+15↑j
                and     #~M_P07_SYS_PWR & $FF
                ora     PORT_P0
                sta     TEMP
                lda     PARAMETER, X
                and     #M_P06_neg5_EN
                eor     #~M_P07_SYS_PWR & $FF
                and     TEMP
                sta     PORT_P0
                bra     loc_EE5A
; ---------------------------------------------------------------------------

COMMAND_18_powerRead:                   ; CODE XREF: COMMAND_1x_POWER↑j
                ldm     #1, COMMAND_SIZE
                lda     PORT_P0
                and     #~M_P07_SYS_PWR & $FF
                eor     #~(M_P06_neg5_EN|M_P07_SYS_PWR) & $FF ; [FIX] = $3F: invert active-low bits 0-5
                seb     P05_SOUND_PWR, A ; SOUND PWR/
                bbs     REG_IN_SOUND_LATCH, IN, loc_EE81
                clb     P05_SOUND_PWR, A ; SOUND PWR/

loc_EE81:                               ; CODE XREF: COMMAND_1x_POWER+4A↑j
                sta     PARAMETER
                jsr     SEND_COMMAND_PARAMETER
                rts
; End of function COMMAND_1x_POWER


; =============== S U B R O U T I N E =======================================


; $28 readADB: reply ADB_COMMAND, ADB_FLAGS, BUFFER_CNT, BUFFER_CNT data bytes.
; Clears the ADB interrupt unless a new /PMINT was signalled meanwhile.
;
COMMAND_28_readADB:                     ; CODE XREF: MAIN_LOOP+21↑p
                ldm     #0, PTR+1
                ldm     #ADB_COMMAND, PTR
                lda     BUFFER_CNT
                clc
                adc     #3
                sta     COMMAND_SIZE
                jsr     SEND_COMMAND
                bcs     locret_EE9E
                bbs     FLAGS_Bits_PMINT_SENT, FLAGS, locret_EE9E
                clb     CMD_78_BITS_ADB_IRQ, CMD_78_STATE

locret_EE9E:                            ; CODE XREF: COMMAND_28_readADB+10↑j
                                        ; COMMAND_28_readADB+12↑j
                rts
; End of function COMMAND_28_readADB


; =============== S U B R O U T I N E =======================================


; $20 pMgrADB: params = ADB command, ADB flags (bit 2 auto-poll), count, data. The data is
; stored reversed in BUFFER and sent from the 60 Hz loop. $21 pMgrADBoff: stop ADB/auto-poll.
;
COMMAND_2x_ADB:                         ; DATA XREF: ROM:EE15↑o
                lda     COMMAND
                cmp     #PowerManagerCommands_20_pMgrADB ; send ADB command
                beq     COMMAND_20_pMgrADB
                cmp     #PowerManagerCommands_21_pMgrADBoff ; turn ADB auto-poll off
                bne     loc_EED4

COMMAND_21_pMgrADBoff:
                ldm     #0, ADB_FLAGS
                clb     CMD_78_BITS_ADB_IRQ, CMD_78_STATE
                clc
                rts
; ---------------------------------------------------------------------------

COMMAND_20_pMgrADB:                     ; CODE XREF: COMMAND_2x_ADB+4↑j
                jsr     READ_PARAMETER
                clb     CMD_78_BITS_ADB_IRQ, CMD_78_STATE
                lda     PARAMETER
                sta     ADB_COMMAND
                lda     PARAMETER+1
                sta     ADB_FLAGS
                seb     ADB_STATUS_BITS_PENDING, ADB_FLAGS
                ldy     #0
                ldx     PARAMETER+2
                beq     loc_EECE

loc_EEC5:                               ; CODE XREF: COMMAND_2x_ADB+2D↓j
                lda     PARAMETER+3, Y      ; [FIX] abs,Y ($B9), was shown as (zp),Y
                sta     BUFFER_CNT, X
                iny
                dex
                bne     loc_EEC5

loc_EECE:                               ; CODE XREF: COMMAND_2x_ADB+24↑j
                sty     ADB_SEND_SIZE
                sty     BUFFER_CNT
                clc
                rts
; ---------------------------------------------------------------------------

loc_EED4:                               ; CODE XREF: COMMAND_2x_ADB+8↑j
                sec
                rts
; End of function COMMAND_2x_ADB


; =============== S U B R O U T I N E =======================================


; $30 timeWrite (4 bytes, seconds since 1904, big-endian)
; $31 pramWrite: 20 bytes classic PRAM = XPRAM $10-$1F then $08-$0B
; $32 xPramWrite: params offset, count, data (no bounds check: offset+count may leave XPRAM)
; $38 timeRead, $39 pramRead (20 bytes), $3A xPramRead (offset, count)
;
COMMAND_3x_PRAM:                        ; DATA XREF: ROM:EE17↑o
                bbs     3, COMMAND, COMMAND_38_3F
                lda     COMMAND
                cmp     #PowerManagerCommands_30_timeWrite ; write the time to the clock chip
                bne     loc_EEF1

COMMAND_30_timeWrite:
                ldm     #TIME_S, PTR
                ldm     #0, PTR+1
                ldm     #4, COMMAND_SIZE
                jsr     READ_BYTES
                jsr     TIME_CALC_CHECKSUM
                sta     TIME_CHECKSUM
                rts
; ---------------------------------------------------------------------------

loc_EEF1:                               ; CODE XREF: COMMAND_3x_PRAM+7↑j
                cmp     #PowerManagerCommands_31_pramWrite ; write the original 20 bytes of PRAM (Portable only)
                bne     COMMAND_32_xPramWrite ; write data in PRAM

COMMAND_31_pramWrite:
                ldm     #PRAM_BUFFER_10, PTR
                ldm     #0, PTR+1
                ldm     #$10, COMMAND_SIZE
                jsr     READ_BYTES
                ldm     #PRAM_BUFFER_08, PTR
                ldm     #4, COMMAND_SIZE
                jsr     READ_BYTES
                jsr     PRAM_IS_VALID
                sta     PRAM_CHKSUM
                rts
; ---------------------------------------------------------------------------

COMMAND_32_xPramWrite:                  ; CODE XREF: COMMAND_3x_PRAM+1D↑j
                ldm     #2, COMMAND_SIZE ; write data in PRAM
                jsr     READ_PARAMETER
                lda     PARAMETER
                clc
                adc     #PRAM_BUFFER
                sta     PTR
                ldm     #0, PTR+1
                lda     PARAMETER+1
                sta     COMMAND_SIZE
                jsr     READ_BYTES
                jsr     PRAM_IS_VALID
                sta     PRAM_CHKSUM
                rts
; ---------------------------------------------------------------------------

COMMAND_38_3F:                          ; CODE XREF: COMMAND_3x_PRAM↑j
                lda     COMMAND
                cmp     #PowerManagerCommands_38_timeRead ; read the time from the clock
                bne     loc_EF40

COMMAND_38_timeRead:
                ldm     #TIME_S, PTR
                ldm     #0, PTR+1
                ldm     #4, COMMAND_SIZE
                jsr     SEND_COMMAND
                rts
; ---------------------------------------------------------------------------

loc_EF40:                               ; CODE XREF: COMMAND_3x_PRAM+5B↑j
                cmp     #PowerManagerCommands_39_pramRead ; read the original 20 bytes of PRAM
                bne     COMMAND_3A_xPramRead ; read data from PRAM

COMMAND_39_pramRead:
                ldm     #0, PTR+1
                ldm     #PRAM_BUFFER_10, PTR
                ldm     #$10, COMMAND_SIZE
                ldy     #0
                lda     COMMAND
                jsr     SEND_BYTE
                bcs     locret_EF6B
                lda     #$14
                jsr     SEND_BYTE
                bcs     locret_EF6B
                jsr     SEND_BUFFER
                ldm     #PRAM_BUFFER_08, PTR
                ldm     #4, COMMAND_SIZE
                ldy     #0
                jsr     SEND_BUFFER

locret_EF6B:                            ; CODE XREF: COMMAND_3x_PRAM+7E↑j
                                        ; COMMAND_3x_PRAM+85↑j
                rts
; ---------------------------------------------------------------------------

COMMAND_3A_xPramRead:                   ; CODE XREF: COMMAND_3x_PRAM+6C↑j
                ldm     #2, COMMAND_SIZE ; read data from PRAM
                jsr     READ_PARAMETER
                lda     PARAMETER
                clc
                adc     #PRAM_BUFFER
                sta     PTR
                ldm     #0, PTR+1
                lda     PARAMETER+1
                sta     COMMAND_SIZE
                jsr     SEND_COMMAND
                rts
; End of function COMMAND_3x_PRAM


; =============== S U B R O U T I N E =======================================


; Sum XPRAM ($2F-$AE). Carry clear if sum == PRAM_CHKSUM and the XPRAM is not all zero.
; Returns the sum in A (also used to compute a new checksum). Preserves X.
;
PRAM_IS_VALID:                          ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+8↑p
                                        ; VECTOR_INT2_RESET_CONTINUE+23↑p ...
                txa
                pha
                ldx     #0
                lda     #0
                clc

loc_EF8B:                               ; CODE XREF: PRAM_IS_VALID+A↓j
                adc     PRAM_BUFFER, X  ; checksum from $2F…$AE
                inx
                bpl     loc_EF8B        ; checksum from $2F…$AE
                sta     TEMP
                cmp     PRAM_CHKSUM
                bne     loc_EFA3
                sta     TEMP
                bne     loc_EFA9
                ldx     #0

loc_EF9C:                               ; CODE XREF: PRAM_IS_VALID+1D↓j
                ora     PRAM_BUFFER, X  ; at least one bit set?
                bne     loc_EFA9        ; => yes
                inx
                bpl     loc_EF9C        ; at least one bit set?

loc_EFA3:                               ; CODE XREF: PRAM_IS_VALID+10↑j
                pla
                tax
                lda     TEMP
                sec                     ; invalid
                rts
; ---------------------------------------------------------------------------

loc_EFA9:                               ; CODE XREF: PRAM_IS_VALID+14↑j
                                        ; PRAM_IS_VALID+1A↑j
                pla
                tax
                lda     TEMP
                clc                     ; buffer valid
                rts
; End of function PRAM_IS_VALID


; =============== S U B R O U T I N E =======================================


; A = 8-bit sum of the 4 clock bytes (detects a clock lost at power-up).
;
TIME_CALC_CHECKSUM:                     ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+2E↑p
                                        ; IRQ_60Hz:loc_EBC0↑p ...
                lda     #0
                clc
                adc     TIME_S
                adc     TIME_S+1
                adc     TIME_S+2
                adc     TIME_S+3
                rts
; End of function TIME_CALC_CHECKSUM


; =============== S U B R O U T I N E =======================================


; $40 contrast: 1 byte 0-31. $48: read the current contrast value.
;
COMMAND_4x_SCREEN_CONTRAST:             ; DATA XREF: ROM:EE19↑o
                bbc     3, COMMAND, COMMAND_40_contrast

COMMAND_48_contrast_read:
                lda     CONTRAST_TIMER_VALUE
                sta     PARAMETER
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts
; ---------------------------------------------------------------------------

COMMAND_40_contrast:                    ; CODE XREF: COMMAND_4x_SCREEN_CONTRAST↑j
                ldm     #1, COMMAND_SIZE
                jsr     READ_PARAMETER
; End of function COMMAND_4x_SCREEN_CONTRAST


; =============== S U B R O U T I N E =======================================


; PWM high time TIMER1 = table[n], low time TIMER2 = 66-table[n]: duty cycle (2..64)/66.
;
SETUP_CONTRAST_TIMER:                   ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+89↑p
                lda     PARAMETER
                and     #$1F
                tax
                sta     CONTRAST_TIMER_VALUE
                lda     #66
                sec
                sbc     CONTRAST_TIMER_TABLE, X
                sta     TIMER2
                lda     CONTRAST_TIMER_TABLE, X
                sta     TIMER1
                clc
                rts
; End of function SETUP_CONTRAST_TIMER

; ---------------------------------------------------------------------------
CONTRAST_TIMER_TABLE:BYTE   2,  4,  6,  8, 10, 12, 14, 16, 18, 20, 22, 24, 26
                BYTE  28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52
                BYTE  54, 56, 58, 60, 62, 64

; =============== S U B R O U T I N E =======================================


; $50 modemSet: bit 0 modem power on, bit 1 MODEM_A/B select (P17), bit 2 wake on ring.
; $58 modemRead: bit 0 power on, 1 A/B, 2 ring wakeup, 3 modem installed (P43 low),
;                4 ring detect (P16 low), 5 off hook (IN3 low).
;
COMMAND_5x_MODEM:                       ; DATA XREF: ROM:EE1B↑o
                bbs     3, COMMAND, COMMAND_58_modemRead

COMMAND_50_modemSet:
                ldm     #1, COMMAND_SIZE
                jsr     READ_PARAMETER
                clb     FLAGS_Bits_RING_WAKEUP, FLAGS
                bbc     2, PARAMETER, loc_F015
                seb     FLAGS_Bits_RING_WAKEUP, FLAGS

loc_F015:                               ; CODE XREF: COMMAND_5x_MODEM+B↑j
                bbc     1, PARAMETER, loc_F01C
                seb     P17_MODEM_AB, PORT_P1
                bra     loc_F01E
; ---------------------------------------------------------------------------

loc_F01C:                               ; CODE XREF: COMMAND_5x_MODEM:loc_F015↑j
                clb     P17_MODEM_AB, PORT_P1

loc_F01E:                               ; CODE XREF: COMMAND_5x_MODEM+15↑j
                bbc     0, PARAMETER, loc_F025
                clb     P03_MODEM_PWR, PORT_P0 ; MODEM PWR/
                clc
                rts
; ---------------------------------------------------------------------------

loc_F025:                               ; CODE XREF: COMMAND_5x_MODEM:loc_F01E↑j
                seb     P03_MODEM_PWR, PORT_P0 ; MODEM PWR/
                clc
                rts
; ---------------------------------------------------------------------------

COMMAND_58_modemRead:                   ; CODE XREF: COMMAND_5x_MODEM↑j
                ldm     #0, PARAMETER
                bbs     P03_MODEM_PWR, PORT_P0, loc_F031 ; MODEM PWR/
                seb     0, PARAMETER

loc_F031:                               ; CODE XREF: COMMAND_5x_MODEM+27↑j
                bbc     P17_MODEM_AB, PORT_P1, loc_F036
                seb     1, PARAMETER

loc_F036:                               ; CODE XREF: COMMAND_5x_MODEM:loc_F031↑j
                bbc     FLAGS_Bits_RING_WAKEUP, FLAGS, loc_F03B
                seb     2, PARAMETER

loc_F03B:                               ; CODE XREF: COMMAND_5x_MODEM:loc_F036↑j
                bbs     P43_MODEM_INS, PORT_P4, loc_F040 ; MODEM (J9) and EPMGR (J21) - Modem Installed?
                seb     3, PARAMETER

loc_F040:                               ; CODE XREF: COMMAND_5x_MODEM:loc_F03B↑j
                bbs     P16_RING_DETECT, PORT_P1, loc_F045
                seb     4, PARAMETER

loc_F045:                               ; CODE XREF: COMMAND_5x_MODEM:loc_F040↑j
                bbs     REG_IN_OFF_HOOK, IN, loc_F04A
                seb     5, PARAMETER

loc_F04A:                               ; CODE XREF: COMMAND_5x_MODEM:loc_F045↑j
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts
; End of function COMMAND_5x_MODEM


; =============== S U B R O U T I N E =======================================


; $68 batteryRead / $69 batteryNow (fresh A-D sample): reply 3 bytes BAT_CHG_FLAGS,
; BAT_VOLTAGE, BAT_IN0. Clears the battery interrupt and CHARGER_CHANGED.
;
COMMAND_6x_BATTERY:                     ; DATA XREF: ROM:EE1D↑o
                lda     COMMAND
                cmp     #PowerManagerCommands_68_batteryRead ; read battery/charger level and status
                beq     COMMAND_68_batteryRead
                cmp     #PowerManagerCommands_69_batteryNow ; read battery/charger instantaneous level and status
                bne     locret_F075

COMMAND_69_batteryNow:
                jsr     BATTERY_READ

COMMAND_68_batteryRead:                 ; CODE XREF: COMMAND_6x_BATTERY+4↑j
                ldm     #BAT_CHG_FLAGS, PTR
                ldm     #0, PTR+1
                ldm     #3, COMMAND_SIZE
                jsr     SEND_COMMAND
                bcs     locret_F075
                bbs     FLAGS_Bits_PMINT_SENT, FLAGS, locret_F075
                clb     CMD_78_BITS_BATT_2, CMD_78_STATE
                clb     CMD_78_BITS_BATT_IRQ, CMD_78_STATE
                clb     BAT_CHG_BITS_CHARGER_CHANGED, BAT_CHG_FLAGS

locret_F075:                            ; CODE XREF: COMMAND_6x_BATTERY+8↑j
                                        ; COMMAND_6x_BATTERY+19↑j ...
                rts
; End of function COMMAND_6x_BATTERY


; =============== S U B R O U T I N E =======================================


; $78 readINT: reply CMD_78_STATE (1 byte), then clear the RESET bit.
;
COMMAND_78_readINT:                     ; CODE XREF: MAIN_LOOP+18↑p
                lda     CMD_78_STATE
                sta     PARAMETER
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                clb     CMD_78_BITS_RESET, CMD_78_STATE
                clb     FLAGS_Bits_PMINT_SENT, FLAGS
                rts
; End of function COMMAND_78_readINT


; =============== S U B R O U T I N E =======================================


; $7F sleepReq: 4 byte signature 'MATT'. Replies $70 (ok) or $AA (bad), then sleeps.
;
COMMAND_7x_SLEEP:                       ; DATA XREF: ROM:EE1F↑o
                lda     COMMAND
                cmp     #PowerManagerCommands_7F_sleepReq ; put the system to sleep
                bne     COMMAND_7F_sleepReq_FAIL

COMMAND_7F_sleepReq:
                ldm     #4, COMMAND_SIZE
                jsr     READ_PARAMETER
                ldm     #PowerManagerCommands_70_response_success, COMMAND
                ldx     #4

COMMAND_7F_sleepReq_LOOP:               ; CODE XREF: COMMAND_7x_SLEEP+19↓j
                dex
                bmi     COMMAND_7F_sleepReq_REPLY
                lda     aMATT, X
                cmp     PARAMETER, X
                beq     COMMAND_7F_sleepReq_LOOP
                ldm     #PowerManagerCommands_AA_response_fail, COMMAND

COMMAND_7F_sleepReq_REPLY:              ; CODE XREF: COMMAND_7x_SLEEP+12↑j
                ldm     #0, COMMAND_SIZE
                jsr     SEND_COMMAND
                bcs     COMMAND_7F_sleepReq_FAIL
                lda     COMMAND
                cmp     #PowerManagerCommands_70_response_success
                beq     ENTER_SLEEP

COMMAND_7F_sleepReq_FAIL:               ; CODE XREF: COMMAND_7x_SLEEP+4↑j
                                        ; COMMAND_7x_SLEEP+24↑j
                sec
                rts
; ---------------------------------------------------------------------------

; Sleep / power off (also used for power-on and dead battery). Blank display, wait for tick
; boundaries, save P0/P1, PWM and sound off, assert SYS_RST, all planes off. Loop on 60 Hz
; ticks pulsing STOP_CLK until a wake event: key press (after AKD was seen idle), alarm, or
; ring (if enabled) - never while BAT_CHG_BITS_VERY_LOW. Then restore power, wait for key
; release, reset keyboard controller, enable display/PWM, release SYS_RST after 1/30 s and
; continue in MAIN_LOOP with a fresh stack. Interrupts stay disabled while asleep.
;
ENTER_SLEEP:                           ; CODE XREF: VECTOR_INT2_RESET_CONTINUE+9A↑j
                                        ; CHECK_BAT_STATUS+74↑j ...
                clb     P42_DISP_BLANK, PORT_P4 ; DISPLAY (J19) Display Blank Line
                sei
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     ENTER_SLEEP
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery
                ldx     #STACK_TOP
                txs
; Wait for 1/30s

loc_F0C0:                               ; CODE XREF: COMMAND_7x_SLEEP+3D↓j
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     loc_F0C0        ; Test if 60Hz IRQ triggered
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery

loc_F0C7:                               ; CODE XREF: COMMAND_7x_SLEEP+44↓j
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     loc_F0C7        ; Test if 60Hz IRQ triggered
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery

                seb     P05_SOUND_PWR, PORT_P0 ; SOUND PWR/
                clb     P05_SOUND_PWR, PORT_P0 ; SOUND PWR/
                lda     PORT_P0
                seb     P07_SYS_PWR, A  ; SYS_PWR/
                sta     PARAMETER
                lda     PORT_P1
                sta     PARAMETER+1
                clb     P33_SOUND_OFF, PORT_P3 ; Audio subsystem power control
                clb     PWM_CTRL_FLAGS_PWM_EN, PWM_CTRL ; contrast PWM output
                clb     P31_SYS_RST, PORT_P3 ; Reset line output to 680x0 and many other chips

                clb     FLAGS_Bits_AKD_IDLE_SEEN, FLAGS ; Any Key Down
                seb     FLAGS_Bits_SLEEPING, FLAGS
                ldm     #M_P00_IWM_CNTRL|M_P01_SCC_CNTRL|M_P02_HD_PWR|M_P03_MODEM_PWR|M_P04_SERIAL_PWR|M_P07_SYS_PWR, PORT_P0
                bra     loc_F0F2
; ---------------------------------------------------------------------------

loc_F0EA:                               ; CODE XREF: COMMAND_7x_SLEEP+71↓j
                                        ; COMMAND_7x_SLEEP+7D↓j ...
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery
                bbs     P11_AKD, PORT_P1, loc_F0F2 ; Any Key Down
                seb     FLAGS_Bits_AKD_IDLE_SEEN, FLAGS ; Any Key Down

loc_F0F2:                               ; CODE XREF: COMMAND_7x_SLEEP+63↑j
                                        ; COMMAND_7x_SLEEP+68↑j
                clb     P12_STOP_CLK, PORT_P1
                seb     P12_STOP_CLK, PORT_P1
                bbs     BAT_CHG_BITS_VERY_LOW, BAT_CHG_FLAGS, loc_F0EA
                bbc     FLAGS_Bits_AKD_IDLE_SEEN, FLAGS, loc_F0FF ; Any Key Down
                bbs     P11_AKD, PORT_P1, loc_F10F ; Any Key Down

loc_F0FF:                               ; CODE XREF: COMMAND_7x_SLEEP+74↑j
                bbs     FLAGS_Bits_ALARM_TRIGGERED, FLAGS, loc_F108 ; 1:Alarm time was triggered
                bbc     FLAGS_Bits_RING_WAKEUP, FLAGS, loc_F0EA
                bbs     P16_RING_DETECT, PORT_P1, loc_F0EA

loc_F108:                               ; CODE XREF: COMMAND_7x_SLEEP:loc_F0FF↑j
                sei
                clb     IRQ_CTRL_FLAGS_INT1_REQ, IRQ_CTRL ; INT1 pin interrupt request bit
                clb     FLAGS_Bits_ALARM_TRIGGERED, FLAGS ; 1:Alarm time was triggered
                clb     FLAGS_Bits_ALARM_SET, FLAGS ; 1:Alarm is enabled

loc_F10F:                               ; CODE XREF: COMMAND_7x_SLEEP+77↑j
                sei
                clb     FLAGS_Bits_SLEEPING, FLAGS

                lda     ADB_FLAGS
                and     #4
                sta     ADB_FLAGS

                lda     PARAMETER
                sta     PORT_P0
                lda     PARAMETER+1
                sta     PORT_P1

loc_F120:                               ; CODE XREF: COMMAND_7x_SLEEP:loc_F127↓j
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     loc_F127
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery

loc_F127:                               ; CODE XREF: COMMAND_7x_SLEEP+9D↑j
                bbs     P11_AKD, PORT_P1, loc_F120 ; wait until the key that woke us is released

                clb     P07_SYS_PWR, PORT_P0 ; SYS_PWR/
                clb     P14_KBD_RST, PORT_P1 ; resets keyboard M50740
                seb     PWM_CTRL_FLAGS_PWM_EN, PWM_CTRL ; contrast PWM output
                seb     P42_DISP_BLANK, PORT_P4 ; DISPLAY (J19) Display Blank Line

                ldx     #2              ; Wait for 1/30s

loc_F134:                               ; CODE XREF: COMMAND_7x_SLEEP+B1↓j
                                        ; COMMAND_7x_SLEEP+B7↓j
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     loc_F134        ; Test if 60Hz IRQ triggered
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery
                dex
                bne     loc_F134        ; Test if 60Hz IRQ triggered

                seb     P14_KBD_RST, PORT_P1 ; resets keyboard M50740
                seb     P31_SYS_RST, PORT_P3 ; Reset line output to 680x0 and many other chips
                clb     IRQ_CTRL_FLAGS_INT2_IRQ_REQ, IRQ_CTRL ; INT2 pin interrupt request bit
                seb     IRQ_CTRL_FLAGS_INT2_EN, IRQ_CTRL ; INT2 pin interrupt enable bit
                cli

                jmp     MAIN_LOOP
; End of function COMMAND_7x_SLEEP


; =============== S U B R O U T I N E =======================================


; $80 timerSet (4 bytes) + enable, $82 timerDisable, $88 timerRead: 4 bytes + enable flag.
; (The "bbs 3, COMMAND" test after cmp #$80 can never branch.)
;
COMMAND_8x_WAKEUP:                      ; DATA XREF: ROM:EE21↑o
                lda     COMMAND
                cmp     #PowerManagerCommands_80_timerSet ; set the wakeup timer
                bne     loc_F162

COMMAND_80_timerSet:
                bbs     3, COMMAND, COMMAND_88_timerRead
                ldm     #4, COMMAND_SIZE
                ldm     #ALARM_TIME, PTR
                ldm     #0, PTR+1
                jsr     READ_BYTES
                seb     FLAGS_Bits_ALARM_SET, FLAGS ; 1:Alarm is enabled
                rts
; ---------------------------------------------------------------------------

loc_F162:                               ; CODE XREF: COMMAND_8x_WAKEUP+4↑j
                cmp     #PowerManagerCommands_82_timerDisable
                bne     COMMAND_88_timerRead
                clb     FLAGS_Bits_ALARM_SET, FLAGS ; 1:Alarm is enabled
                rts
; ---------------------------------------------------------------------------

COMMAND_88_timerRead:                   ; CODE XREF: COMMAND_8x_WAKEUP:COMMAND_80_timerSet↑j
                                        ; COMMAND_8x_WAKEUP+1A↑j
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
                bbc     FLAGS_Bits_ALARM_SET, FLAGS, loc_F184 ; 1:Alarm is enabled
                seb     0, PARAMETER+4

loc_F184:                               ; CODE XREF: COMMAND_8x_WAKEUP+35↑j
                jsr     SEND_COMMAND_PARAMETER
                rts
; End of function COMMAND_8x_WAKEUP


; =============== S U B R O U T I N E =======================================


; $90 soundSet: bit 0 -> P33, bit 1 = pulse P05 (clears the sound latch).
; $98 soundRead: bit 0 = P33, bit 1 = sound latch (IN2 low).
;
COMMAND_9x_SOUND:                       ; DATA XREF: ROM:EE23↑o
                bbs     3, COMMAND, COMMAND_98_soundRead

COMMAND_90_soundSet:
                ldm     #1, COMMAND_SIZE
                jsr     READ_PARAMETER
                bbc     0, PARAMETER, loc_F198
                seb     P33_SOUND_OFF, PORT_P3 ; Audio subsystem power control
                bra     loc_F19A
; ---------------------------------------------------------------------------

loc_F198:                               ; CODE XREF: COMMAND_9x_SOUND+9↑j
                clb     P33_SOUND_OFF, PORT_P3 ; Audio subsystem power control

loc_F19A:                               ; CODE XREF: COMMAND_9x_SOUND+E↑j
                bbc     1, PARAMETER, locret_F1A1
                seb     P05_SOUND_PWR, PORT_P0 ; SOUND PWR/
                clb     P05_SOUND_PWR, PORT_P0 ; SOUND PWR/

locret_F1A1:                            ; CODE XREF: COMMAND_9x_SOUND:loc_F19A↑j
                rts
; ---------------------------------------------------------------------------

COMMAND_98_soundRead:                   ; CODE XREF: COMMAND_9x_SOUND↑j
                ldm     #0, PARAMETER
                bbc     P33_SOUND_OFF, PORT_P3, loc_F1AA ; Audio subsystem power control
                seb     0, PARAMETER

loc_F1AA:                               ; CODE XREF: COMMAND_9x_SOUND+1D↑j
                bbs     REG_IN_SOUND_LATCH, IN, loc_F1AF
                seb     1, PARAMETER

loc_F1AF:                               ; CODE XREF: COMMAND_9x_SOUND:loc_F1AA↑j
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts
; End of function COMMAND_9x_SOUND


; =============== S U B R O U T I N E =======================================


; $EF PmgrSoftReset: ack, then jump into the port initialisation. NOTE: S is not reset
;        (2 bytes lost per soft reset unless it ends in ENTER_SLEEP) and A/Y are stale.
; $EC PmgrSelfTest: reply 1 byte, bit0 ROM checksum, bit1 RAM address lines, bit2 RAM r/w (1=fail)
; $EA readPmgrVers: 2 bytes $02,$B5
; $E0 writePmgrRAM: addr hi, addr lo, data...   $E8 readPmgrRAM: addr hi, addr lo, count
;        (any 16-bit address - can read the ROM)
;
COMMAND_Ex_INTERNAL:                    ; DATA XREF: ROM:EE2D↑o
                lda     COMMAND
                cmp     #PowerManagerCommands_EF_PmgrSoftReset ; soft reset of the PMGR
                bne     loc_F1C4

COMMAND_EF_PmgrSoftReset:
                jsr     SEND_COMMAND
                bcs     COMMAND_E0_fail
                jmp     loc_E8A8
; ---------------------------------------------------------------------------

loc_F1C4:                               ; CODE XREF: COMMAND_Ex_INTERNAL+4↑j
                cmp     #PowerManagerCommands_EC_PmgrSelfTest ; run the PMGR selftest
                bne     loc_F1EB

COMMAND_EC_PmgrSelfTest:
                ldm     #0, PARAMETER
                jsr     CHECK_ROM_CHECKSUM ; Bit 0
                ror     PARAMETER
                jsr     CHECK_RAM_BITS  ; Bit 1
                ror     PARAMETER
                jsr     CHECK_RAM_RW    ; Bit 2
                ror     PARAMETER
                ror     PARAMETER
                ror     PARAMETER
                ror     PARAMETER
                ror     PARAMETER
                ror     PARAMETER
                ldm     #1, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts
; ---------------------------------------------------------------------------

loc_F1EB:                               ; CODE XREF: COMMAND_Ex_INTERNAL+10↑j
                cmp     #PowerManagerCommands_EA_readPmgrVers ; read the PMGR version number
                bne     COMMAND_E0_E8_writePmgrRAM_readPmgrRAM

COMMAND_EA_readPmgrVers:
                lda     ROM_VERSION
                sta     PARAMETER
                lda     ROM_VERSION+1
                sta     PARAMETER+1
                ldm     #2, COMMAND_SIZE
                jsr     SEND_COMMAND_PARAMETER
                rts
; ---------------------------------------------------------------------------

COMMAND_E0_E8_writePmgrRAM_readPmgrRAM: ; CODE XREF: COMMAND_Ex_INTERNAL+37↑j
                lda     COMMAND_SIZE
                sta     TEMP
                jsr     READ_PARAMETER
                lda     PARAMETER
                sta     PTR+1
                lda     PARAMETER+1
                sta     PTR
                ldx     TEMP
                beq     COMMAND_E0_fail
                dex
                beq     COMMAND_E0_fail
                dex
                beq     COMMAND_E0_success
                lda     COMMAND
                cmp     #PowerManagerCommands_E0_writePmgrRAM ; write to internal PMGR RAM
                bne     COMMAND_E8_readPmgrRAM

COMMAND_E0_writePmgrRAM:
                ldy     #0

COMMAND_E0_writePmgrRAM_LOOP:           ; CODE XREF: COMMAND_Ex_INTERNAL+72↓j
                lda     PARAMETER+2, Y      ; [FIX] abs,Y ($B9), was shown as (zp),Y
                sta     (PTR), Y
                iny
                dex
                bne     COMMAND_E0_writePmgrRAM_LOOP

COMMAND_E0_success:                     ; CODE XREF: COMMAND_Ex_INTERNAL+61↑j
                clc
                rts
; ---------------------------------------------------------------------------

COMMAND_E0_fail:                        ; CODE XREF: COMMAND_Ex_INTERNAL+9↑j
                                        ; COMMAND_Ex_INTERNAL+5B↑j ...
                sec
                rts
; ---------------------------------------------------------------------------

COMMAND_E8_readPmgrRAM:                 ; CODE XREF: COMMAND_Ex_INTERNAL+67↑j
                ldx     PARAMETER+2
                beq     loc_F238
                stx     COMMAND_SIZE

loc_F234:                               ; CODE XREF: COMMAND_Ex_INTERNAL+85↓j
                jsr     SEND_COMMAND
                rts
; ---------------------------------------------------------------------------

loc_F238:                               ; CODE XREF: COMMAND_Ex_INTERNAL+7A↑j
                ldm     #0, COMMAND_SIZE
                bra     loc_F234
; End of function COMMAND_Ex_INTERNAL


; =============== S U B R O U T I N E =======================================


; 16-bit rotate-and-add checksum over $E806-$FFFF, compared with ROM_CHECKSUM.
; Services the 60 Hz tick while running. Carry set = fail.
;
CHECK_ROM_CHECKSUM:                     ; CODE XREF: COMMAND_Ex_INTERNAL+15↑p
                lda     #>VECTOR_RESET
                sta     PTR+1
                ldy     #6
                lda     #0
                sta     PARAMETER+1
                sta     PTR

CHECK_ROM_CHECKSUM_LOOP1:               ; CODE XREF: CHECK_ROM_CHECKSUM+19↓j
                                        ; CHECK_ROM_CHECKSUM+2A↓j
                clc
                adc     (PTR), Y
                bcc     CHECK_ROM_CHECKSUM_LOOP2
                inc     PARAMETER+1

CHECK_ROM_CHECKSUM_LOOP2:               ; CODE XREF: CHECK_ROM_CHECKSUM+F↑j
                cmp     #$80
                rol     PARAMETER+1
                rol     A
                iny
                bne     CHECK_ROM_CHECKSUM_LOOP1

                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     loc_F265
                sta     PARAMETER+2
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery
                lda     PARAMETER+2
                ldy     #0

loc_F265:                               ; CODE XREF: CHECK_ROM_CHECKSUM+1D↑j
                inc     PTR+1
                bne     CHECK_ROM_CHECKSUM_LOOP1
                ldx     PARAMETER+1
                tay
                ora     PARAMETER+1
                bne     loc_F272
                dex
                dey

loc_F272:                               ; CODE XREF: CHECK_ROM_CHECKSUM+31↑j
                cpx     ROM_CHECKSUM
                bne     CHECK_ROM_CHECKSUM_fail
                cpy     ROM_CHECKSUM+1
                bne     CHECK_ROM_CHECKSUM_fail
                clc
                rts
; ---------------------------------------------------------------------------

CHECK_ROM_CHECKSUM_fail:                ; CODE XREF: CHECK_ROM_CHECKSUM+38↑j
                                        ; CHECK_ROM_CHECKSUM+3D↑j
                sec
                rts
; End of function CHECK_ROM_CHECKSUM


; =============== S U B R O U T I N E =======================================


; Address line test: write 9 patterns to $00,$01,$02,$04,...,$80, verify, then the
; complement; original contents saved at PARAMETER+1.. and restored. Carry set = fail, I flag
; preserved (php / rol / plp / ror).
;
CHECK_RAM_BITS:                         ; CODE XREF: COMMAND_Ex_INTERNAL+1A↑p
                php
                sei
                sec
                ldy     #8

loc_F285:                               ; CODE XREF: CHECK_RAM_BITS+E↓j
                ldx     CHECK_RAM_ADR_TAB, Y
                lda     0, X
                sta     PARAMETER+1, Y      ; [FIX] abs,Y ($99), was shown as (zp),Y
                dey
                bpl     loc_F285
                ldy     #8

loc_F292:                               ; CODE XREF: CHECK_RAM_BITS+1B↓j
                lda     CHECK_RAM_DATA_TAB, Y
                ldx     CHECK_RAM_ADR_TAB, Y
                sta     0, X
                dey
                bpl     loc_F292
                ldy     #8

loc_F29F:                               ; CODE XREF: CHECK_RAM_BITS+2A↓j
                lda     CHECK_RAM_DATA_TAB, Y
                ldx     CHECK_RAM_ADR_TAB, Y
                eor     0, X
                bne     loc_F2CD
                dey
                bpl     loc_F29F
                ldy     #8

loc_F2AE:                               ; CODE XREF: CHECK_RAM_BITS+39↓j
                lda     CHECK_RAM_DATA_TAB, Y
                eor     #$FF
                ldx     CHECK_RAM_ADR_TAB, Y
                sta     0, X
                dey
                bpl     loc_F2AE
                ldy     #8

loc_F2BD:                               ; CODE XREF: CHECK_RAM_BITS+4A↓j
                lda     CHECK_RAM_DATA_TAB, Y
                eor     #$FF
                ldx     CHECK_RAM_ADR_TAB, Y
                eor     0, X
                bne     loc_F2CD
                dey
                bpl     loc_F2BD
                clc

loc_F2CD:                               ; CODE XREF: CHECK_RAM_BITS+27↑j
                                        ; CHECK_RAM_BITS+47↑j
                ldy     #8

loc_F2CF:                               ; CODE XREF: CHECK_RAM_BITS+58↓j
                ldx     CHECK_RAM_ADR_TAB, Y
                lda     PARAMETER+1, Y      ; [FIX] abs,Y ($B9), was shown as (zp),Y
                sta     0, X
                dey
                bpl     loc_F2CF
                rol     A
                plp
                ror     A
                rts
; End of function CHECK_RAM_BITS

; ---------------------------------------------------------------------------
CHECK_RAM_ADR_TAB:BYTE   0,  1,  2,  4,  8,$10,$20,$40,$80
CHECK_RAM_DATA_TAB:BYTE $F0,$E1,$D2,$C3,$B4,$A5,$96,$87,$78

; =============== S U B R O U T I N E =======================================


; Non-destructive walking-bit test of every RAM byte $BF..$00 (incl. the stack). Carry set = fail.
;
CHECK_RAM_RW:                           ; CODE XREF: COMMAND_Ex_INTERNAL+1F↑p
                ldx     #RAMTOP_PLUS_1

CHECK_RAM_RW_LOOP:                      ; CODE XREF: CHECK_RAM_RW+24↓j
                                        ; CHECK_RAM_RW+2D↓j
                dex
                cpx     #$FF
                beq     CHECK_RAM_RW_success
                ldy     0, X
                lda     #0
                sec

CHECK_RAM_RW_LOOP2:                     ; CODE XREF: CHECK_RAM_RW+1E↓j
                rol     A
                sta     0, X
                cmp     0, X
                bne     CHECK_RAM_RW_fail
                eor     #$FF
                sta     0, X
                cmp     0, X
                bne     CHECK_RAM_RW_fail
                eor     #$FF
                clc
                bne     CHECK_RAM_RW_LOOP2
                sty     0, X
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     CHECK_RAM_RW_LOOP
                stx     PARAMETER+2
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery
                ldx     PARAMETER+2
                bra     CHECK_RAM_RW_LOOP
; ---------------------------------------------------------------------------

CHECK_RAM_RW_success:                   ; CODE XREF: CHECK_RAM_RW+5↑j
                clc
                rts
; ---------------------------------------------------------------------------

CHECK_RAM_RW_fail:                       ; CODE XREF: CHECK_RAM_RW+11↑j
                                        ; CHECK_RAM_RW+19↑j
                sty     0, X
                sec
                rts
; End of function CHECK_RAM_RW


; =============== S U B R O U T I N E =======================================

; S2/S3 reset/NMI keys - RESET

; INT2: reset/interrupt switch. Assert SYS_RST (P31 low), wait at least 2 ticks and until
; the switch (P30) is released, then warm-restart (Y=0) at VECTOR_INT2_RESET_CONTINUE.
;
VECTOR_INT2_RESET:                      ; DATA XREF: ROM:FFF4↓o
                nop
                clb     P31_SYS_RST, PORT_P3 ; [FIX] bit 1 (opcode $3F): assert SYS_RST to the 68000 (was shown as mask M_P30_RESET)
; Delay by 1/30s

loc_F328:                               ; CODE XREF: VECTOR_INT2_RESET+5↓j
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     loc_F328        ; Test if 60Hz IRQ triggered
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery

loc_F32F:                               ; CODE XREF: VECTOR_INT2_RESET+C↓j
                                        ; VECTOR_INT2_RESET+11↓j
                bit     IRQ_CTRL        ; Test if 60Hz IRQ triggered
                bpl     loc_F32F        ; Test if 60Hz IRQ triggered
                jsr     IRQ_60Hz        ; Called at 60Hz to increment time, check alarm and battery

                bbc     P30_RESET, PORT_P3, loc_F32F ; wait until the reset/interrupt switch is released

                jmp     VECTOR_INT2_RESET_CONTINUE
; End of function VECTOR_INT2_RESET


; =============== S U B R O U T I N E =======================================

; rti - unused

; Timer 2 / serial I/O vector ($FFF6) - unused.
;
VECTOR_TIMER2:                          ; DATA XREF: ROM:FFF6↓o
                rti
; End of function VECTOR_TIMER2


; =============== S U B R O U T I N E =======================================

; rti - unused

; Timer 1 / A-D vector ($FFF8) - unused (A-D completion is polled).
;
VECTOR_TIMER1:                          ; DATA XREF: ROM:FFF8↓o
                rti
; End of function VECTOR_TIMER1


; =============== S U B R O U T I N E =======================================

; rti - unused

VECTOR_TIMERX:                          ; DATA XREF: ROM:FFFA↓o
                rti
; End of function VECTOR_TIMERX


; =============== S U B R O U T I N E =======================================

; rti - unused - 60.15 Hz clock

; INT1 ($FFFC): 60.15 Hz tick - interrupt not enabled, the request bit is polled.
;
VECTOR_INT1_60Hz_CLOCK:                 ; DATA XREF: ROM:FFFC↓o
                rti
; End of function VECTOR_INT1_60Hz_CLOCK

; ---------------------------------------------------------------------------
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0

; =============== S U B R O U T I N E =======================================


; Special page ($FF00). JSR \DELAY_LOOP_X takes 5+6X+6 cycles (X=0: 256 loops).
; DELAY_SMALL ($FF00) is never called. DELAY_RTS is an 11 cycle delay.
;
DELAY_SMALL:
                ldx     #3
; End of function DELAY_SMALL


; =============== S U B R O U T I N E =======================================


DELAY_LOOP_X:                           ; CODE XREF: MAIN_LOOP+66↑p
                                        ; MAIN_LOOP+68↑p ...
                dex
                bne     DELAY_LOOP_X
; End of function DELAY_LOOP_X


; =============== S U B R O U T I N E =======================================


DELAY_RTS:                              ; CODE XREF: ADB_SEND_CMD:loc_EC21↑p
                                        ; ADB_SEND_CMD:loc_EC9E↑p
                rts
; End of function DELAY_RTS

; ---------------------------------------------------------------------------
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0
                BYTE   0,  0,  0,  0
                WORD VECTOR_INT2_RESET  ; S2/S3 reset/NMI keys - RESET
                WORD VECTOR_TIMER2      ; rti - unused
                WORD VECTOR_TIMER1      ; rti - unused
                WORD VECTOR_TIMERX      ; rti - unused
                WORD VECTOR_INT1_60Hz_CLOCK ; rti - unused - 60.15 Hz clock
                WORD VECTOR_RESET
; end of 'ROM'


                END
