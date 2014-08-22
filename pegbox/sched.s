.include "sched.inc"
.include "mem.inc"
.include "errno.inc"
.include "flags.inc"

PROC_SLOTS equ	8

.text

.macro spswap		; swaps SP with [MEM_SAVESP]
	LD HL,0
	ADD HL,SP
	LD SP,(MEM_SAVESP)
	LD (MEM_SAVESP),HL
.endm

.globl sched_choose	; returns (in IX) a runnable process from the runq, if there is one, else carry flag
sched_choose:
	LD IX,runq_lock
	CALL spin_lock
	LD HL,runq
	CALL list_empty
	JR NZ,_sched_choose_pop
					; no process runnable
	LD IX,runq_lock
	CALL spin_unlock
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
_sched_choose_pop:
	PUSH HL
	POP IX
	LD L,(IX+0)		; head->next
	LD H,(IX+1)
	PUSH HL
	CALL list_del	; remove from runq
	LD IX,runq_lock	; now we're unreachable from the runq, so we can release the runq_lock
	CALL spin_unlock
	POP IX
.ifdef DEBUG
	PUSH IX
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,sched_chose_1
	CALL kputs_unlocked
	POP IX
	PUSH IX
	LD A,(IX+4)		; pid
	CALL kprint_hex_unlocked
	LD HL,sched_chose_2
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
	POP IX
.endif
	AND A			; clear carry
	RET

.globl sched_enter	; starts running (struct process *)IX (doesn't save current state)
sched_enter:
	LD A,(IX+4)		; pid
	LD (IY+1),A		; store percpu_struct.current_pid
	LD (IX+5),TASK_RUNNING
					; page in process stack
	LD D,(IX+6)
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

.globl do_fork		; adds new process to tail of runqueue, returns new pid in A.  errno in E
do_fork:
	CALL choose_pid
	CP 1
	RET C
.if PROCESS_SIZE != 8
.error "assert PROCESS_SIZE == 8"
.endif
	LD HL,procs		; slot = procs + (pid*PROCESS_SIZE)
	PUSH AF			; stash child pid, carry flag is clear
	LD C,A
	LD B,0
	SLA C
	RL B
	SLA C
	RL B
	SLA C
	RL B
	ADD HL,BC
	PUSH HL
	POP IX
	LD (IX+4),A
	LD (IX+5),TASK_UNINTERRUPTIBLE
	PUSH IX
	CALL get_page	; obtain stack page
	POP IX
	AND A
	JR Z,_do_fork_fail1
	LD (IX+6),A		; assign stack page
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
	LD A,(IX+6)
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
	PUSH BC
	PUSH IX
	LD IX,runq_lock
	CALL spin_lock
	POP IX
	LD (IX+5),TASK_RUNNABLE
	PUSH IX
	POP HL
	LD DE,runq
	CALL list_add_tail
	LD IX,runq_lock
	CALL spin_unlock
	EI
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
	POP IX
	LD (IX+4),0
	POP AF			; A=pid
	CALL free_pid
	SCF
	RET

.globl choose_pid
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
	CP PROC_SLOTS
	JR C,_choose_pid_cont
	XOR A			; wrap around to pid 0
_choose_pid_cont:
	CP C			; are we back to the nextpid we started with?
	JR NZ,_choose_pid_loop; then there must be no free slots
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
	LD IX,runq
	CALL init_list_head
	LD BC,runq		; add init to runq
	LD HL,procs+PROCESS_SIZE; procs[1] is pid 1, init
	PUSH HL
	CALL list_add
	POP IX
	LD (IX+4),1
	LD (IX+5),TASK_RUNNABLE
	PUSH IX
	LD (IY+1),1		; mark our running process as init, so we can get_page
	CALL get_page	; If this fails, the system only has one working page...
	POP IX
	AND A
	CALL Z,panic	; ... so let's give up now
	LD (IY+1),0		; clear our running process (as we're not actually running init)
	LD (IX+6),A
	LD BC,0x0100|IO_MMU
	OUT (C),A		; page in init's stack page at pi=1
	LD HL,MEM_STKTOP
	LD (MEM_SAVESP),HL
	SPSWAP
	LD HL,exit_proc	; Process return address
	PUSH HL
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

.globl exit_proc
exit_proc:			; Return address for a process
	CALL panic		; Should really mark process as TASK_EXITED or something, so parent can wait()

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
	JR NC,_exec_forked
	LD HL,fork
	CALL perror
	RET
_exec_forked:
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
fork: .asciz "fork"
.endif

.bss
runq: .skip 4
procs: .skip PROCESS_SIZE * PROC_SLOTS; we're actually being inefficient and reserving a slot for the non-existent pid 0
pid_map: .skip (PROC_SLOTS+7)/8
