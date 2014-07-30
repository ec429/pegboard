.include "sched.inc"
.include "mem.inc"
.include "errno.inc"

.text

.macro spswap		; swaps SP with [MEM_SAVESP]
	LD HL,0
	ADD HL,SP
	LD SP,(MEM_SAVESP)
	LD (MEM_SAVESP),HL
.endm

newproc_entry:
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,enter_proc_1
	CALL kputs_unlocked
	LD A,(IX+0)
	CALL kprint_hex_unlocked
	LD HL,enter_proc_2
	CALL kputs_unlocked
	LD A,(IX+1)
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	CALL panic		; Haven't yet written a process loader

.globl createproc	; adds new process to tail of waitqueue, returns new pid in A.  errno in E
createproc:
	LD IX,waitq_lock
	CALL spin_lock
	LD B,8
	LD HL,waitq
_createproc_nextslot:
	LD A,(HL)
	AND A
	JR Z,_createproc_foundslot
	INC HL
	INC HL
	INC HL
	DJNZ _createproc_nextslot
	CALL spin_unlock
	LD E,EAGAIN
	SCF
	RET
_createproc_foundslot:
	PUSH HL
	CALL choose_pid
	AND A
	JR NZ,_createproc_gotpid
	LD IX,waitq_lock
	CALL spin_unlock
	POP HL
	XOR A
	SCF
	RET
_createproc_gotpid:
	POP HL
	PUSH AF			; stash pid
	LD (HL),A
	INC HL
	LD (HL),TASK_UNINTERRUPTIBLE
	PUSH HL
	CALL get_page	; obtain stack page
	POP HL
	AND A
	JR Z,_createproc_fail1
	INC HL
	LD (HL),A		; assign stack page
	LD IX,waitq_lock
	CALL spin_unlock
	LD A,(HL)
	LD BC,0x0105
	OUT (C),A		; page in stack at pi 1
	LD HL,0x8000	; set the stack pointer to 0x8000 (top of page 1)
	LD (MEM_SAVESP),HL
	SPSWAP
	LD HL,newproc_entry; Stack slot for PC
	PUSH HL
	LD HL,0			; Stack slots for AF BC DE HL IX IY.  Fill all (except IY=&percpu_struct) with 0
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH IY
	SPSWAP
	LD (HL),NOPAGE	; fill in the vm_map with zeroes
	PUSH HL
	POP DE
	INC DE
	LD BC,3
	LDIR
	POP AF			; A=pid, carry flag will be clear
;#ifdef DEBUG
	PUSH AF
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,got_proc_1
	CALL kputs_unlocked
	POP AF
	PUSH AF
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP AF
;#endif
	LD E,0
	RET
_createproc_fail1:
	LD (HL),0
	LD IX,waitq_lock
	CALL spin_unlock
	POP AF			; A=pid
	CALL free_pid
	SCF
	RET

choose_pid:			; returns chosen pid in A, or 0 with errno in E
	LD IX,nextpid_lock
	CALL spin_lock
	LD HL,nextpid
	LD A,(HL)
	LD B,A
	LD C,A
_choose_pid_loop:
	CALL claim_pid
	LD A,B
	JR Z,_choose_pid_chosen
	INC A
	CP C
	JR NZ,_choose_pid_loop
	CALL spin_unlock
	LD A,0
	LD E,EAGAIN
	RET
_choose_pid_chosen:
	LD E,0
	LD HL,nextpid
	PUSH AF
	INC A
	LD (HL),A
	CALL spin_unlock
	POP AF
	RET

claim_pid:			; Tries to claim pid A.  Returns Z if pid was available to claim.  Caller must hold nextpid_lock
	LD HL,pid_map
	LD D,0
	LD E,A
	SRL E
	SRL E
	SRL E
	ADD HL,DE
	LD E,1			; generate the mask for the (A&7)th bit
	AND 7
	JR Z,_claim_pid_mask
_claim_pid_loop:
	SLA E
	DEC A
	JR NZ,_claim_pid_loop
_claim_pid_mask:	; test the corresponding bit
	LD A,E
	LD D,(HL)
	AND D
	RET NZ
	LD A,E
	OR D
	LD (HL),A
	XOR A			; will set Z flag
	RET

free_pid:			; Frees pid A
	LD IX,nextpid_lock
	CALL spin_lock
	LD HL,pid_map
	LD D,0
	LD E,A
	SRL E
	SRL E
	SRL E
	ADD HL,DE
	LD E,1			; generate the mask for the (A&7)th bit
	AND 7
	JR Z,_free_pid_mask
_free_pid_loop:
	SLA E
	DEC A
	JR NZ,_free_pid_loop
_free_pid_mask:		; test the corresponding bit
	LD D,(HL)
	LD A,E
	AND D
	CALL Z,panic
	LD A,E
	XOR D
	LD (HL),A
	CALL spin_unlock
	RET

.globl setup_scheduler
setup_scheduler:	; no need to take locks as we run this before allowing other CPUs to start
	LD HL,pid_map
	LD (HL),0x3		; pid 0 is unusable, pid 1 is init which is already running
	LD IX,runq
	LD (IX+0),1
	LD (IX+1),TASK_RUNNING
	LD (IX+2),NOPAGE; init doesn't have a conventional stack page
	RET

.data
.globl runq_lock, waitq_lock, nextpid_lock,got_proc_1
runq_lock: .byte 0xfe
waitq_lock: .byte 0xfe
nextpid_lock: .byte 0xfe ; also guards pid_map
nextpid: .byte 2
got_proc_1: .asciz "Created process "
enter_proc_1: .asciz "CPU #"
enter_proc_2: .asciz " entered process "

.bss
runq: .skip 24
waitq: .skip 24
pid_map: .skip 32
