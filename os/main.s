.text

.globl main			; per-CPU OS entry point.  Does not return
main:
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
; schedule into a process
	LD IX,runq_lock
	CALL spin_lock
	LD A,(IY+0)
	AND A
	LD A,1			; if we're cpu0, run init
	CALL NZ,sched_choose; otherwise get a process from the scheduler
	CALL sched_enter
; Shouldn't get here
	LD HL,STR_finished
	CALL kputs
	CALL panic

cpu0_setup:
	CALL setup_mem_map
	CALL setup_scheduler
	LD HL,can_start_other_cpus
	LD (HL),1
	RET

.data
STR_stest: .ascii "stest"
.byte 0x0a,0
STR_do_fork: .asciz "do_fork"
STR_finished: .ascii "finished"
.byte 0x0a,0
start_msg_1: .asciz "CPU #"
start_msg_2: .ascii " online"
.byte 0x0a,0
