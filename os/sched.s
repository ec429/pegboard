.include "sched.inc"
.include "mem.inc"
.include "errno.inc"
.include "flags.inc"

.text

.macro spswap		; swaps SP with [MEM_SAVESP]
	LD HL,0
	ADD HL,SP
	LD SP,(MEM_SAVESP)
	LD (MEM_SAVESP),HL
.endm

.globl sched_choose	; returns (in HL) a runnable process from the runq, if there is one, else carry flag.  Caller must hold runq_lock
sched_choose:
	LD HL,runq+1
	LD B,8
	LD A,TASK_RUNNABLE
_sched_choose_nextslot:
	CP (HL)
	JR Z,_sched_choose_found
	INC HL
	INC HL
	INC HL
	DJNZ _sched_choose_nextslot
.ifdef DEBUG
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,sched_waiting
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
.endif
	SCF
	RET
_sched_choose_found:
	DEC HL
.ifdef DEBUG
	PUSH HL
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,sched_chose_1
	CALL kputs_unlocked
	POP HL
	PUSH HL
	LD A,(HL)		; pid
	CALL kprint_hex_unlocked
	LD HL,sched_chose_2
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP HL
.endif
	LD A,(HL)		; pid
	AND A			; clear carry flag
	RET

.globl sched_enter	; starts running pid A (doesn't save current state).  Releases: runq_lock
sched_enter:
	LD (IY+1),A		; store percpu_struct.current_pid
	CALL find_pid_in_q; find the runq entry
	CALL C,panic
					; mark task as running
	INC HL
	LD (HL),TASK_RUNNING
					; page in process stack
	INC HL
	LD D,(HL)
					; now it's safe to release runq_lock
	LD IX,runq_lock
	CALL spin_unlock
	LD BC,0x0100|IO_MMU
	OUT (C),D
	LD SP,(MEM_SAVESP)
	LD (MEM_SAVESP),IY
	POP IX
	POP HL
	POP DE
	POP BC
	POP AF
	EI				; process must have had interrupts enabled before, because it got pre-empted (or it'd still be running)
	RET

find_q_slot:		; finds an empty slot on the runq.  Caller must hold runq_lock
	LD A,0
	JR find_pid_in_q

find_pid_in_q:		; finds pid A in the runq.  Caller must hold runq_lock
	LD HL,runq
	LD B,8
_find_pid_in_q_nextslot:
	CP (HL)
	RET Z			; if Z, then carry is clear also.  Returns address of struct process in HL
	INC HL
	INC HL
	INC HL
	DJNZ _find_pid_in_q_nextslot
	LD E,EAGAIN
	SCF
	RET

.globl do_fork		; adds new process to tail of runqueue, returns new pid in A.  errno in E
do_fork:
	LD IX,runq_lock
	CALL spin_lock
	LD HL,runq
	CALL find_q_slot
	JR C,_do_fork_unlock_out
	PUSH HL
	CALL choose_pid
	AND A
	JR NZ,_do_fork_gotpid
	POP HL
_do_fork_unlock_out:
	LD IX,runq_lock
	CALL spin_unlock
	XOR A
	SCF
	RET
_do_fork_gotpid:
	POP HL
	PUSH AF			; stash child pid
	LD (HL),A
	INC HL
	LD (HL),TASK_UNINTERRUPTIBLE
	PUSH HL
	CALL get_page	; obtain stack page
	POP HL
	AND A
	JR Z,_do_fork_fail1
	INC HL
	LD (HL),A		; assign stack page
	LD IX,runq_lock
	CALL spin_unlock
	POP BC			; retrieve child pid
	DI				; put process image into a schedulable state before copying
	XOR A			; ensure child returns 0 from fork()
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	LD (MEM_SAVESP),SP
					; copy stack page
	LD A,(HL)
	LD BC,0x0200|IO_MMU
	OUT (C),A		; page in stack at pi 2
	LD HL,0x1000
	PUSH HL
	POP BC
	LD DE,MEM_STKTOP
	LDIR			; do the copy
					; mark task as runnable
	POP IX
	POP HL
	POP DE
	POP BC
	POP AF
	EI
	PUSH BC			; stash child pid again
	LD IX,runq_lock
	CALL spin_lock
	POP AF			; A=pid, carry flag will be clear
	PUSH AF
	CALL find_pid_in_q
	CALL C,panic	; should have been added by choose_pid
	INC HL
	LD (HL),TASK_RUNNABLE
	CALL spin_unlock
	POP AF
.ifdef DEBUG
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
.endif
	LD E,0
	EI
	RET
_do_fork_fail1:
	LD (HL),0
	LD IX,runq_lock
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
	LD (HL),0x3		; pid 0 is unusable, pid 1 is init
					; create init process
	LD (IY+1),1		; mark our running process as init, so we can get_page
	LD IX,runq
	LD (IX+0),1
	LD (IX+1),TASK_RUNNABLE
	PUSH IX
	CALL get_page	; If this fails, the system only has one working page...
	POP IX
	AND A
	CALL Z,panic	; ... so let's give up now
	LD (IX+2),A
	LD BC,0x0100|IO_MMU
	OUT (C),A		; page in init's stack page at pi=1
	LD HL,MEM_STKTOP
	LD (MEM_SAVESP),HL
	SPSWAP
	LD HL,exec_init	; Stack slot for PC
	PUSH HL
	LD HL,0			; Stack slots for AF BC DE HL IX.  Fill all with 0
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
	PUSH HL
	SPSWAP
	LD HL,MEM_VM_MAP
	LD (HL),NOPAGE	; fill in the vm_map with zeroes
	PUSH HL
	POP DE
	INC DE
	LD BC,0xf
	LDIR
	RET

.globl exec_init
exec_init:
.ifdef DEBUG
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,exec_init_1
	CALL kputs_unlocked
	LD A,(IY+0)
	CALL kprint_hex_unlocked
	LD HL,exec_init_2
	CALL kputs_unlocked
	LD A,(IY+1)
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
.endif
	CALL do_fork
	CALL kprint_hex	; show value of A register (should be <child pid> in parent, 0 in child)
	CALL panic		; Haven't yet written a process loader (or a filesystem to load init from)

.data
.globl runq_lock, nextpid_lock
runq_lock: .byte 0xfe
nextpid_lock: .byte 0xfe ; also guards pid_map
nextpid: .byte 2
.ifdef DEBUG
got_proc_1: .asciz "Created process "
exec_init_1: .asciz "CPU #"
exec_init_2: .asciz " started init, pid="
sched_chose_1: .asciz "pid "
sched_chose_2: .asciz " scheduled on CPU "
sched_waiting: .asciz "No process runnable on CPU "
.endif

.bss
runq: .skip 24
pid_map: .skip 32
