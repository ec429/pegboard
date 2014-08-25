.include "sched.inc"

.section init, "rx"
	DI
	IM 2
	LD D,0			; initially, we're not running in any process
	PERCPU			; get percpu data area
	LD SP,HL		; set up (temporary) stack
	LD IY,-PERCPU_SIZE
	ADD IY,SP		; IY points to the percpu_struct
	LD C,1
	PUSH BC
	PUSH DE
	LD A,E			; are we CPU0?
	AND A
	JR Z,start_main	; if so, start up immediately
	LD HL,can_start_other_cpus; else wait for CPU0 to give us the go-ahead
wait_to_start:
	DJNZ .
	LD A,(HL)
	AND A
	JR Z,wait_to_start
start_main:
	JP main

.bss
.globl can_start_other_cpus
can_start_other_cpus: .byte 0
