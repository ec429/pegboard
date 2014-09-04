.include "mem.inc"
.include "spinlock.inc"

.text

.globl panic
panic:
	CLI
	LD HL,can_start_other_cpus
	LD (HL),0
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	LD HL,panic_msg_1
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD HL,panic_msg_2
	CALL kputs_unlocked
	LD A,(IY+1)		; pid
	CALL kprint_hex_unlocked
	LD HL,panic_msg_3
	CALL kputs_unlocked
	LD HL,0
	ADD HL,SP
	PUSH HL
	LD A,H
	CALL kprint_hex_unlocked
	POP HL
	LD A,L
	CALL kprint_hex_unlocked
	LD HL,panic_msg_4
	CALL kputs_unlocked
	LD B,0x10		; max. number of stack entries to print
	XOR A			; make sure carry is clear
	LD HL,MEM_STKTOP
	SBC HL,SP
	CP H
	JR NZ,_panic_stack_loop; we've got at least 128 items, so we're fine
	SRL L			; 2 bytes per stack item.  L is now stack depth in items
	LD A,L
	CP B
	JR NC,_panic_stack_loop; stack depth exceeds B, so we're fine
	LD B,A			; only print as much stack as we have
_panic_stack_loop:
	POP HL
	LD A,H
	CALL kprint_hex_unlocked
	LD A,L
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	DJNZ _panic_stack_loop
	LD HL,panic_msg_5
	CALL kputs_unlocked
	CALL spin_unlock_irqsave
	HALT

.data
panic_msg_1: .asciz "KERNEL PANIC on CPU #"
panic_msg_2: .asciz " (pid="
panic_msg_3: .ascii "), halting."
.byte 0x0a
.asciz "Stack @0x"
panic_msg_4: .byte ':',0x0a,0
panic_msg_5: .ascii "cut here: ------8<------"
.byte 0x0a,0
