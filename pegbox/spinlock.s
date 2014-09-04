.include "spinlock.inc"

.text

.globl spin_lock_irqsave
spin_lock_irqsave:	; acquire lock at IX, disabling interrupts
	CLI
.globl spin_lock	; acquire lock at IX
spin_lock:
	.byte 0xdd		; locked-instruction prefix
	SRA (IX+0)		; contains the second DD
	JR C,.-5
	RET

.globl spin_unlock	; release lock at IX.  Clobbers: A
spin_unlock:
	LD A,0xfe
	.byte 0xdd		; locked-instruction prefix
	LD (IX+0),A
	RET

.globl spin_unlock_irqsave; release lock at IX.  Clobbers: A
spin_unlock_irqsave:
	LD A,0xfe
	.byte 0xdd		; locked-instruction prefix
	LD (IX+0),A
	STI
	RET
