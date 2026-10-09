#!/usr/bin/env python3
# Re-assemble the IDA IAR-740 listing and compare it byte for byte against the ROM image.
# usage: python3 tools/reasm740.py pmuv1.bin.asm pmuv1.bin
import sys, re, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from m740 import OPS, SIZE, BASE
d = open(sys.argv[2],'rb').read()
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
REV = {}
for c,(mn,m) in OPS.items():
    if mn in ('bbs','bbc','seb','clb'): REV.setdefault((mn,m),{})[c>>5]=c
    else: REV[(mn,m)] = c
def strip(l):
    # remove comment (not inside quotes)
    q=False
    for i,ch in enumerate(l):
        if ch=='"' : q=not q
        if ch==';' and not q: return l[:i]
    return l
sym = {}
def ev(e):
    e=e.strip()
    e=e.replace('$','0x')
    e=re.sub(r"'(.)'", lambda m: str(ord(m.group(1))), e)
    hi = e.startswith('>'); lo = e.startswith('<')
    if hi or lo: e=e[1:]
    v = eval(re.sub(r'0x[0-9A-Fa-f]+|0b[01]+|\d+|[A-Za-z_]\w*', lambda m: m.group(0) if m.group(0)[0].isdigit() else f'sym["{m.group(0)}"]', e))
    return (v>>8)&0xFF if hi else v&0xFF if lo else v
def parse(passno):
    seg=None; pc=0; out=[]
    for ln,raw in enumerate(lines,1):
        l=strip(raw).rstrip()
        if not l.strip(): continue
        m=re.match(r'^([A-Za-z_][\w]*):\s*(.*)$', l)
        if m and 'EQU' in m.group(2):
            sym[m.group(1)] = eval(m.group(2).split('EQU')[1].strip().replace('$','0x')); continue
        body=l
        if m:
            if passno==1: sym[m.group(1)] = pc
            body=m.group(2)
        body=body.strip()
        if not body: continue
        t=body.split(None,1); mn=t[0]; arg=t[1].strip() if len(t)>1 else ''
        if mn=='RSEG': seg=arg; pc=0; continue
        if mn=='ORG': pc=int(arg.replace('$',''),16); continue
        if mn in('END',): continue
        if mn=='BLKB': pc+=ev(arg) if passno==2 or not re.search('[A-Za-z]',arg) else ev(arg); continue
        if mn=='BYTE':
            bs=[]
            for part in re.findall(r'"[^"]*"|[^,]+', arg):
                part=part.strip()
                if part.startswith('"'): bs+= [ord(c) for c in part[1:-1]]
                else: bs.append(ev(part) if passno==2 else 0)
            out.append((ln,pc,bs,raw)); pc+=len(bs); continue
        if mn=='WORD':
            bs=[]
            for part in arg.split(','):
                v=ev(part) if passno==2 else 0; bs+=[v&0xFF,v>>8]
            out.append((ln,pc,bs,raw)); pc+=len(bs); continue
        # instruction
        a=arg.replace(' ','')
        def V(x): return ev(x) if passno==2 else 0
        def known(x):
            try: return ev(x)
            except Exception: return 0x100
        if mn in('bbs','bbc'):
            b,op1,tg=a.split(',')
            if op1=='A': mode='bbsA'
            else: mode='bbsZ'
            c=REV[(mn,mode)][ev(b)] if passno==2 else 0
            n=SIZE[mode]
            if passno==2:
                rel=(ev(tg)-(pc+n))
                bs=[c]+([] if mode=='bbsA' else [ev(op1)])+[rel&0xFF]
                if not -128<=rel<=127: print('range',ln)
            else: bs=[0]*n
        elif mn in('seb','clb'):
            b,op1=a.split(','); mode='sebA' if op1=='A' else 'sebZ'
            bs=[REV[(mn,mode)][ev(b)]]+([] if mode=='sebA' else [ev(op1)]) if passno==2 else [0]*SIZE[mode]
        elif mn=='ldm':
            im,zp=a.split(','); bs=[0x3C,V(im[1:]),V(zp)]
        else:
            if a=='': mode='imp'
            elif a=='A': mode='acc'
            elif a.startswith('#'): mode='imm'
            elif a.startswith('\\'): mode='sp'
            elif a.endswith(',X)'): mode='idx'
            elif a.startswith('(') and a.endswith('),Y'): mode='idy'
            elif a.startswith('(') and a.endswith(')') and mn in('jmp','jsr'):
                mode='zpind' if known(a[1:-1])<0x100 else 'ind'
            elif a.endswith(',X') or a.endswith(',Y'):
                r=a[-1]; e=a[:-2]
                mode=('zp'+r.lower()) if known(e)<0x100 and (mn,'zp'+r.lower()) in REV else 'abs'+r.lower()
            elif mn in('bra','bpl','bmi','bne','beq','bcc','bcs','bvc','bvs'): mode='rel'
            else: mode='zp' if known(a)<0x100 and (mn,'zp') in REV and mn!='jsr' and mn!='jmp' else 'abs'
            if (mn,mode) not in REV: print('NOMODE',ln,mn,mode,raw); bs=[0]*SIZE.get(mode,1)
            else:
                c=REV[(mn,mode)]; n=SIZE[mode]
                if passno==1: bs=[0]*n
                else:
                    e=a
                    if mode=='imm': e=a[1:]
                    elif mode=='sp': e=a[1:]
                    elif mode=='idx': e=a[1:-3]
                    elif mode=='idy': e=a[1:-3]
                    elif mode in('zpind','ind'): e=a[1:-1]
                    elif mode in('zpx','zpy','absx','absy'): e=a[:-2]
                    v=ev(e) if mode not in('imp','acc') else 0
                    if mode=='rel': r=v-(pc+2); bs=[c,r&0xFF]
                    elif n==1: bs=[c]
                    elif n==2: bs=[c,v&0xFF]
                    else: bs=[c,v&0xFF,(v>>8)&0xFF]
        out.append((ln,pc,bs,raw)); pc+=len(bs)
    return out
parse(1); out=parse(2)
bad=0
for ln,pc,bs,raw in out:
    if pc<BASE: continue
    real=list(d[pc-BASE:pc-BASE+len(bs)])
    if real!=bs:
        bad+=1; print(f'line {ln} ${pc:04X}: listing->{bytes(bs).hex()} binary={bytes(real).hex()} | {raw.strip()[:90]}')
print('mismatches',bad, 'last pc %04X'%(out[-1][1]+len(out[-1][2])))
