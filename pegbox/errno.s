.text

.globl perror		; writes "[HL]: strerror(E)\n" to terminal
perror:
	LD IX,kprint_lock
	PUSH IX
	CALL spin_lock_irqsave
	CALL kputs_unlocked
	LD HL,error_string_1
	CALL kputs_unlocked
	LD HL,error_table
	LD D,0
	PUSH DE
	ADD HL,DE
	ADD HL,DE
	PUSH HL
	POP BC
	LD HL,error_table_end
	AND A			; clear carry
	SBC HL,BC
	JR NC,perror_table
	LD HL,ehwhatnow
	JR perror_doprint
perror_table:
	LD A,(BC)
	LD L,A
	INC BC
	LD A,(BC)
	LD H,A
perror_doprint:
	PUSH HL
	CALL kputs_unlocked
	AND A			; clear carry
	LD BC,ehwhatnow
	POP HL
	SBC HL,BC
	POP DE
	JR NZ,perror_donl
	LD A,E
	CALL kprint_hex_unlocked
perror_donl:
	LD A,0x0a
	CALL kputc_unlocked
	POP IX
	CALL spin_unlock_irqsave
	RET

.data
error_string_1: .asciz ": "
error_table:
	.word success
	.rept 10
	.word ehwhatnow
	.endr
	.word eagain
	.word enomem
	.word ehwhatnow
	.word efault
	.rept 7
	.word ehwhatnow
	.endr
	.word einval
error_table_end:
success: .asciz "Success"
eagain: .asciz "Resource temporarily unavailable"
enomem: .asciz "Out of memory"
efault: .asciz "Bad address"
einval: .asciz "Invalid argument"
ehwhatnow: .asciz "Unknown error "
