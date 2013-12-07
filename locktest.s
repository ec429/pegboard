.text
	LD D,0
	LD IX,namelock
	CALL spin_lock
	LD HL,cpuindex
	LD E,(HL)
	INC (HL)
	CALL spin_unlock
main:
	LD IX,slotlock
	CALL spin_lock
	LD HL,slots
	ADD HL,DE
busy:
	INC (HL)
	JR NZ,busy
	CALL spin_unlock
rest:
	DEC A
	JR NZ,rest
	JR main

spin_lock:			; acquire lock at IX
	.byte 0xdd		; locked-instruction prefix
	sra (IX+0)		; contains the second DD
	jr c,spin_lock
	ret

spin_unlock:		; release lock at IX
	ld a,0xfe
	ld (IX+0),a		; no need for a locked op
	ret

.data
namelock: .byte 0xfe
slotlock: .byte 0xfe
cpuindex: .byte 0
slots: .skip 8		; byte[NR_CPUS]
