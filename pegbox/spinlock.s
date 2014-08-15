.text

.globl spin_lock	; acquire lock at IX
spin_lock:
	.byte 0xdd		; locked-instruction prefix
	sra (IX+0)		; contains the second DD
	jr c,spin_lock
	ret

.globl spin_unlock	; release lock at IX.  Clobbers: A
spin_unlock:
	ld a,0xfe
	ld (IX+0),a		; no need for a locked op
	ret
