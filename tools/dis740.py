#!/usr/bin/env python3
# Independent recursive-descent disassembler for the M50753 PMGR ROM.
# usage: python3 tools/dis740.py pmuv1.bin out.txt
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from m740 import *
d = open(sys.argv[1],'rb').read()
code = {}
todo = [rd(d,0xFFF4+2*i)|rd(d,0xFFF5+2*i)<<8 for i in range(6)]
# command table
for i in range(16): todo.append(rd(d,0xEE11+2*i)|rd(d,0xEE12+2*i)<<8)
while todo:
    a = todo.pop()
    while a not in code and BASE <= a <= 0xFFFF:
        r = decode(d,a)
        if r is None: print('BAD opcode at %04X'%a); break
        mn,m,n,s,b = r; code[a]=r
        if m in('rel','bbsA','bbsZ'): todo.append(int(s.split('$')[-1],16))
        if mn in('jsr','jmp') and m=='abs': todo.append(b[1]|b[2]<<8)
        if m=='sp': todo.append(0xFF00|b[1])
        if mn in ('rts','rti','bra','jmp'): break
        a += n
a=BASE
out=[]
while a<=0xFFFF:
    if a in code:
        mn,m,n,s,b=code[a]; out.append(f'{a:04X}  {" ".join("%02X"%x for x in b):9s} {mn} {s}'); a+=n
    else:
        st=a
        while a<=0xFFFF and a not in code: a+=1
        out.append(f'{st:04X}  data {a-st} bytes: {d[st-BASE:min(a,st+24)-BASE].hex()}')
open(sys.argv[2],'w').write('\n'.join(out)+'\n')
print(len(code),'instructions')
