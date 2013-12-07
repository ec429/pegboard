.text

.globl main			; per-CPU OS entry point.  Does not return
main:
	LD HL,hello
	CALL kputs
	LD A,(IY+0)
	ADD A,0x30
	LD IX,kprint_lock
	CALL spin_lock
	CALL kputc_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	JR main

.data
hello: .ascii "Hello World"
.byte 0x0a,0
