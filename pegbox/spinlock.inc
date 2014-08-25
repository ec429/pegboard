.ifndef _SPINLOCK_INC
_SPINLOCK_INC equ 1

.macro cli			; counting DI
	DI
	INC (IY+2)
	CALL Z,panic
.endm

.macro sti			; counting EI
	DEC (IY+2)
	CALL M,panic
	JR NZ,.+3
	EI
.endm

.macro spin_lock_at disp; acquire lock at IX+disp
	CLI
	.byte 0xdd		; locked-instruction prefix
	sra (IX+\disp)	; contains the second DD
	jr c,.-5
.endm

.macro spin_unlock_at disp; release lock at IX+disp.  Clobbers: A
	ld a,0xfe
	ld (IX+\disp),a		; no need for a locked op
	STI
.endm

.endif
