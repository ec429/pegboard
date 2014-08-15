.include "sched.inc"

.section init, "rx"
	DI
	IM 2
	LD D,0			; initially, we're not running in any process
	PERCPU			; get percpu data area
	LD SP,HL		; set up (temporary) stack
	LD IY,0xfffe
	ADD IY,SP		; IY points to the percpu_struct
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

.text
.globl get_percpu_data; given E=cpuid, returns HL=(&percpu_struct+2)
get_percpu_data:
	LD A,0x7f
	SUB E
	LD H,A
	LD L,0xf0
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
	RET

.bss
.globl can_start_other_cpus
can_start_other_cpus: .byte 0

; struct percpu_struct {
;   u8 cpuid;
;	u8 current_pid;
; }
