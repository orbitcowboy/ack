.define _unlink
.sect .text
.sect .rom
.sect .data
.sect .bss
.sect .text
.extern _unlink
_unlink:		trap #0
.data2	0xA
			bcc	1f
			jmp	cerror
1:
			clr.l	d0
			rts
