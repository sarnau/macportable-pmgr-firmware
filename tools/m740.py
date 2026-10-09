#!/usr/bin/env python3
# Mitsubishi 740 family (MELPS 740) opcode table, verified against the 740 Software Manual (REJ09B0322)
# modes: imp, acc, imm, zp, zpx, zpy, abs, absx, absy, idx, idy, ind, zpind, rel, sp,
#        bbsA (bit,A,rel), bbsZ (bit,zp,rel), sebA, sebZ, ldm (#imm,zp)
OPS = {}
def op(code, mn, mode): OPS[code] = (mn, mode)

std = {  # 6502 core
 0x00:('brk','imp'),0x01:('ora','idx'),0x05:('ora','zp'),0x06:('asl','zp'),0x08:('php','imp'),0x09:('ora','imm'),
 0x0A:('asl','acc'),0x0D:('ora','abs'),0x0E:('asl','abs'),0x10:('bpl','rel'),0x11:('ora','idy'),0x15:('ora','zpx'),
 0x16:('asl','zpx'),0x18:('clc','imp'),0x19:('ora','absy'),0x1D:('ora','absx'),0x1E:('asl','absx'),
 0x20:('jsr','abs'),0x21:('and','idx'),0x24:('bit','zp'),0x25:('and','zp'),0x26:('rol','zp'),0x28:('plp','imp'),
 0x29:('and','imm'),0x2A:('rol','acc'),0x2C:('bit','abs'),0x2D:('and','abs'),0x2E:('rol','abs'),0x30:('bmi','rel'),
 0x31:('and','idy'),0x35:('and','zpx'),0x36:('rol','zpx'),0x38:('sec','imp'),0x39:('and','absy'),0x3D:('and','absx'),
 0x3E:('rol','absx'),0x40:('rti','imp'),0x41:('eor','idx'),0x45:('eor','zp'),0x46:('lsr','zp'),0x48:('pha','imp'),
 0x49:('eor','imm'),0x4A:('lsr','acc'),0x4C:('jmp','abs'),0x4D:('eor','abs'),0x4E:('lsr','abs'),0x50:('bvc','rel'),
 0x51:('eor','idy'),0x55:('eor','zpx'),0x56:('lsr','zpx'),0x58:('cli','imp'),0x59:('eor','absy'),0x5D:('eor','absx'),
 0x5E:('lsr','absx'),0x60:('rts','imp'),0x61:('adc','idx'),0x65:('adc','zp'),0x66:('ror','zp'),0x68:('pla','imp'),
 0x69:('adc','imm'),0x6A:('ror','acc'),0x6C:('jmp','ind'),0x6D:('adc','abs'),0x6E:('ror','abs'),0x70:('bvs','rel'),
 0x71:('adc','idy'),0x75:('adc','zpx'),0x76:('ror','zpx'),0x78:('sei','imp'),0x79:('adc','absy'),0x7D:('adc','absx'),
 0x7E:('ror','absx'),0x81:('sta','idx'),0x84:('sty','zp'),0x85:('sta','zp'),0x86:('stx','zp'),0x88:('dey','imp'),
 0x8A:('txa','imp'),0x8C:('sty','abs'),0x8D:('sta','abs'),0x8E:('stx','abs'),0x90:('bcc','rel'),0x91:('sta','idy'),
 0x94:('sty','zpx'),0x95:('sta','zpx'),0x96:('stx','zpy'),0x98:('tya','imp'),0x99:('sta','absy'),0x9A:('txs','imp'),
 0x9D:('sta','absx'),0xA0:('ldy','imm'),0xA1:('lda','idx'),0xA2:('ldx','imm'),0xA4:('ldy','zp'),0xA5:('lda','zp'),
 0xA6:('ldx','zp'),0xA8:('tay','imp'),0xA9:('lda','imm'),0xAA:('tax','imp'),0xAC:('ldy','abs'),0xAD:('lda','abs'),
 0xAE:('ldx','abs'),0xB0:('bcs','rel'),0xB1:('lda','idy'),0xB4:('ldy','zpx'),0xB5:('lda','zpx'),0xB6:('ldx','zpy'),
 0xB8:('clv','imp'),0xB9:('lda','absy'),0xBA:('tsx','imp'),0xBC:('ldy','absx'),0xBD:('lda','absx'),0xBE:('ldx','absy'),
 0xC0:('cpy','imm'),0xC1:('cmp','idx'),0xC4:('cpy','zp'),0xC5:('cmp','zp'),0xC6:('dec','zp'),0xC8:('iny','imp'),
 0xC9:('cmp','imm'),0xCA:('dex','imp'),0xCC:('cpy','abs'),0xCD:('cmp','abs'),0xCE:('dec','abs'),0xD0:('bne','rel'),
 0xD1:('cmp','idy'),0xD5:('cmp','zpx'),0xD6:('dec','zpx'),0xD8:('cld','imp'),0xD9:('cmp','absy'),0xDD:('cmp','absx'),
 0xDE:('dec','absx'),0xE0:('cpx','imm'),0xE1:('sbc','idx'),0xE4:('cpx','zp'),0xE5:('sbc','zp'),0xE6:('inc','zp'),
 0xE8:('inx','imp'),0xE9:('sbc','imm'),0xEA:('nop','imp'),0xEC:('cpx','abs'),0xED:('sbc','abs'),0xEE:('inc','abs'),
 0xF0:('beq','rel'),0xF1:('sbc','idy'),0xF5:('sbc','zpx'),0xF6:('inc','zpx'),0xF8:('sed','imp'),0xF9:('sbc','absy'),
 0xFD:('sbc','absx'),0xFE:('inc','absx'),
 # 740 specific
 0x02:('jsr','zpind'),0x12:('clt','imp'),0x22:('jsr','sp'),0x32:('set','imp'),0x42:('stp','imp'),0xC2:('wit','imp'),
 0x82:('rrf','zp'),0xB2:('jmp','zpind'),0x3C:('ldm','ldm'),0x44:('com','zp'),0x64:('tst','zp'),0x80:('bra','rel'),
 0x1A:('dec','acc'),0x3A:('inc','acc'),
}
OPS.update(std)
for i in range(8):
    op(i*0x20+0x03, 'bbs', 'bbsA'); op(i*0x20+0x13, 'bbc', 'bbsA')
    op(i*0x20+0x07, 'bbs', 'bbsZ'); op(i*0x20+0x17, 'bbc', 'bbsZ')
    op(i*0x20+0x0B, 'seb', 'sebA'); op(i*0x20+0x1B, 'clb', 'sebA')
    op(i*0x20+0x0F, 'seb', 'sebZ'); op(i*0x20+0x1F, 'clb', 'sebZ')
SIZE = {'imp':1,'acc':1,'imm':2,'zp':2,'zpx':2,'zpy':2,'abs':3,'absx':3,'absy':3,'idx':2,'idy':2,'ind':3,
        'zpind':2,'rel':2,'sp':2,'bbsA':2,'bbsZ':3,'sebA':1,'sebZ':2,'ldm':3}
BASE = 0xE800
def rd(d, a): return d[a-BASE]
def decode(d, a):
    o = rd(d, a)
    if o not in OPS: return None
    mn, m = OPS[o]; n = SIZE[m]
    b = [rd(d, a+i) for i in range(n)]
    bit = o >> 5
    if m == 'rel': t = (a+2+((b[1]^0x80)-0x80)) & 0xFFFF; s = f'${t:04X}'
    elif m == 'bbsA': t = (a+2+((b[1]^0x80)-0x80)) & 0xFFFF; s = f'{bit},A,${t:04X}'
    elif m == 'bbsZ': t = (a+3+((b[2]^0x80)-0x80)) & 0xFFFF; s = f'{bit},${b[1]:02X},${t:04X}'
    elif m == 'sebA': s = f'{bit},A'
    elif m == 'sebZ': s = f'{bit},${b[1]:02X}'
    elif m == 'imp': s = ''
    elif m == 'acc': s = 'A'
    elif m == 'imm': s = f'#${b[1]:02X}'
    elif m == 'zp': s = f'${b[1]:02X}'
    elif m == 'zpx': s = f'${b[1]:02X},X'
    elif m == 'zpy': s = f'${b[1]:02X},Y'
    elif m in ('abs','absx','absy','ind'):
        v = b[1]|b[2]<<8; s = {'abs':f'${v:04X}','absx':f'${v:04X},X','absy':f'${v:04X},Y','ind':f'(${v:04X})'}[m]
    elif m == 'idx': s = f'(${b[1]:02X},X)'
    elif m == 'idy': s = f'(${b[1]:02X}),Y'
    elif m == 'zpind': s = f'(${b[1]:02X})'
    elif m == 'sp': s = f'\\$FF{b[1]:02X}'
    elif m == 'ldm': s = f'#${b[1]:02X},${b[2]:02X}'
    return mn, m, n, s, b
