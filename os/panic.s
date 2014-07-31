.text

.globl panic
panic:
	LD IX,kprint_lock
	CALL spin_lock
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
	LD B,0x10		; number of stack entries to print
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
	CALL spin_unlock
	DI
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
