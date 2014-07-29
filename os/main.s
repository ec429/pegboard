.text

.globl main			; per-CPU OS entry point.  Does not return
main:
	LD A,(IY+0)
	AND A
	CALL Z,cpu0_setup
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
; scheduler test
	LD A,1
stest:
	INC A
	PUSH AF
	CALL createproc
	LD HL,STR_createproc
	CALL C,perror
	POP AF
	CP 0x0c
	JR NZ,stest
; finished
	POP AF
	LD HL,STR_finished
	CALL kputs
	HALT

cpu0_setup:
	CALL setup_mem_map
	LD HL,can_start_other_cpus
	LD (HL),1
	RET

.data
STR_stest: .ascii "stest"
.byte 0x0a,0
STR_createproc: .asciz "createproc"
STR_finished: .ascii "finished"
.byte 0x0a,0
start_msg_1: .asciz "CPU #"
start_msg_2: .ascii " online"
.byte 0x0a,0
