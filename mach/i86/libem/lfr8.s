.sect .text
.define .lfr8
.extern .retarea

.lfr8:
	pop	bx
	push	(.retarea+6)
	push	(.retarea+4)
	push	(.retarea+2)
	push	(.retarea)
	jmp	bx
