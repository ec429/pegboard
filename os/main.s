.text

.globl main			; per-CPU OS entry point.  Does not return
main:
	LD A,0x1f		; set intvec = 0x1f
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
	JR Z,cpu0_setup
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
					; schedule into init
	LD IX,runq_lock
	CALL spin_lock
	LD A,1
	CALL sched_enter
_main_never:
					; Shouldn't get here
	LD HL,STR_finished
	CALL kputs
	CALL panic
	RET

setup_interrupts:
	LD HL,INT_timer	; plumb timer interrupt
	LD (0x0f02),HL
	RET

INT_timer:			; handler for timer interrupt
	; currently have to trust IY is still pointing right!  XXX this is a problem
	EX AF,AF'
	LD A,(IY+1)		; current PID
	AND A
	JR Z,_int_timer_schedule
	EX AF,AF'		; a process is already running, let it continue
	EI
	RETI			; we will have a proper scheduler eventually, but not yet
_int_timer_schedule:; pick a process and schedule into it.  (And we're not in a process, so we can trash regs)
	EX AF,AF'
	LD IX,runq_lock
	CALL spin_lock
	CALL sched_choose
	JR C,_int_timer_noproc
	CALL sched_enter
	JR _main_never
_int_timer_noproc:	; no process found, so just return
	LD IX,runq_lock
	CALL spin_unlock
	EI
	RETI

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
STR_finished: .ascii "main() exited!"
.byte 0x0a,0
start_msg_1: .asciz "CPU #"
start_msg_2: .ascii " online"
.byte 0x0a,0
