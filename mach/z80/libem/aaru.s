.define .aaru

! AAR NOT DEFINED

.aaru:
	pop ix
	pop hl
	xor a
	xor h
	jp nz,1f
	ld a,2
	xor l
	jp z,2f
1:
	ld hl,EARRAY
	call .trp.z
2:
	push ix
	jp .aar
