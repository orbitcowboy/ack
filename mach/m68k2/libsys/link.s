.define _link
.sect .text
.sect .rom
.sect .data
.sect .bss
.extern _link
.sect .text
_link:		move.w #0x9,d0
		move.l 4(sp),a0
		move.w 8(sp),d1
		ext.l  d1
		jmp callc
