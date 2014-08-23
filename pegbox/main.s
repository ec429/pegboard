.include "sched.inc"
.include "debug.inc"
.text

.globl main			; per-CPU OS entry point.  Does not return
main:
	LD A,0x0f		; set intvec = 0x0f
	LD I,A
; we are now online
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,start_msg_1
	CALL kputs_unlocked
	LD A,(IY+0)
	CALL kprint_hex_unlocked
	LD HL,start_msg_2
	CALL kputs_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
	LD A,(IY+0)
	AND A
	CALL Z,cpu0_setup
	EI
_main_idle:
	HALT
	JR _main_idle
cpu0_setup:
	CALL setup_mem_map
	CALL setup_scheduler
	CALL setup_interrupts
	LD HL,STR_booting
	CALL kputs
	LD HL,can_start_other_cpus
	LD (HL),1
	RET				; init is now ready to be entered by whichever CPU schedules first

setup_interrupts:
	LD HL,INT_timer	; plumb timer interrupt
	LD (0x0f02),HL
	RET

INT_timer:			; handler for timer interrupt
	EX AF,AF'
	EXX
	PERCPU
	LD IY,0xfffe
	EX DE,HL
	ADD IY,DE		; IY points to the percpu_struct
	LD A,(IY+1)		; current PID
	AND A
	JR Z,_int_timer_schedule
	EXX				; we're in a process, so we need to save state.
	EX AF,AF'		; XXX for now we'll assume we were in kernel-space, so the right stack is already paged in
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	SPSWAP
	CALL sched_exit
	CALL sched_put
_int_timer_schedule:; pick a process and schedule into it.  (And we're not in a process, so we can trash regs)
					; but first, check no-one has panicked
	LD A,(can_start_other_cpus)
	AND A
	JR Z,_int_timer_panicked
	CALL sched_choose
	JR C,_int_timer_noproc
	CALL sched_enter
	LD HL,STR_finished
	CALL kputs
	CALL panic
_int_timer_noproc:	; no process found, so just return (to _main_idle)
	EI
	RETI
_int_timer_panicked:; panic on another cpu, so stop
	HALT

.section isr
.globl unhandled_irq
unhandled_irq:
EI
RETI

.section ivt
.skip 0x100,0x0e	; fill interrupt table with 0x0e0e (unhandled IRQ)

.data
STR_booting: .ascii "Booting PEGBOx kernel 0.0.1-pre"
.byte 0x0a,0
STR_finished: .ascii "Failed to sched_enter!"
.byte 0x0a,0
start_msg_1: .asciz "CPU #"
start_msg_2: .ascii " online"
.byte 0x0a,0
