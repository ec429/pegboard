.ifndef _SPINLOCK_INC
_SPINLOCK_INC equ 1

SPINLOCK_UNLOCKED equ 0xfe

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

.macro spin_lock_at disp; acquire lock at IX+disp, disabling interrupts
	CLI
	.byte 0xdd		; locked-instruction prefix
	sra (IX+\disp)	; contains the second DD
	jr c,.-5
.endm

.macro spin_unlock_at disp; release lock at IX+disp.  Clobbers: A
	ld a,SPINLOCK_UNLOCKED
	.byte 0xdd		; locked-instruction prefix
	ld (IX+\disp),a
	STI
.endm

.endif
