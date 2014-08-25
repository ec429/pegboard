.include "sched.inc"
.include "mem.inc"
.include "errno.inc"
.include "debug.inc"
.include "semaphore.inc"
.include "spinlock.inc"

PROC_SLOTS equ	8

.text

.globl get_current	; returns (in HL) struct process for running pid
get_current:
	LD A,(IY+1)
	; fall into get_process
.globl get_process	; returns (in HL) struct process for pid A
get_process:
	BUILD_BUG_ON(PROCESS_SIZE != 8)
	LD HL,procs		; slot = procs + (pid*PROCESS_SIZE)
	LD C,A
	LD B,0
	SLA C
	RL B
	SLA C
	RL B
	SLA C
	RL B
	ADD HL,BC
	RET

.globl sched_choose	; returns (in IX) a runnable process from the runq, if there is one, else carry flag
sched_choose:		; must be called with interrupts disabled
	LD IX,runq_lock
	CALL spin_lock
	LD HL,runq
	CALL list_empty
	JR NZ,_sched_choose_pop
					; no process runnable
	LD IX,runq_lock
	CALL spin_unlock
.if DEBUG
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
.if DEBUG
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
	LD BC,(VPAGE_STACK<<8)|IO_MMU
	OUT (C),D
	SPSWAP
	POP IX
	POP HL
	POP DE
	POP BC
	POP AF
	STI				; process must have had interrupts enabled before, because it got pre-empted (or it'd still be running)
	RET

.globl sched_exit	; returns (in HL) struct process for current pid
sched_exit:
.if DEBUG
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,sched_exit_1
	CALL kputs_unlocked
	LD A,(IY+1)		; pid
	CALL kprint_hex_unlocked
	LD HL,sched_exit_2
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
.endif
	LD A,(IY+1)		; pid
	CALL get_process
	RET

.globl sched_put	; places process at (struct process *)HL onto the runq and marks it TASK_RUNNABLE
sched_put:			; must be called with interrupts disabled
	PUSH HL
	POP IX
	LD (IX+5),TASK_RUNNABLE
	LD IX,runq_lock
	CALL spin_lock
	LD DE,runq
	CALL list_add_tail
	LD IX,runq_lock
	CALL spin_unlock
	XOR A
	LD (IY+1),A		; no pid
	RET

.globl sched_sleep	; saves stack, chooses a new runnable process and enters it.  Caller should have already CLI'd and placed current process on a waitq
sched_sleep:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	SPSWAP
.if DEBUG
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,sched_sleep_1
	CALL kputs_unlocked
	LD A,(IY+1)		; pid
	CALL kprint_hex_unlocked
	LD HL,sched_sleep_2
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
.endif
	XOR A
	LD (IY+1),A		; no pid
	CALL sched_choose
	JP NC,sched_enter
	STI
	RET

.globl sched_yield	; voluntarily give up rest of timeslice
sched_yield:
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	CLI
	SPSWAP
	CALL get_current
	PUSH HL
.if DEBUG
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,sched_yield_1
	CALL kputs_unlocked
	LD A,(IY+1)		; pid
	CALL kprint_hex_unlocked
	LD HL,sched_yield_2
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
.endif
	POP HL
	CALL sched_put
	CALL sched_choose
	CALL NC,sched_enter; it's possible that another CPU could have started running our process between the sched_put and the sched_choose
	RET				; if no process was found, this will return to _main_idle.  Otherwise it will return to sched_yield's caller

.globl do_fork		; adds new process to tail of runqueue, returns new pid in A.  errno in E
do_fork:
	CALL choose_pid
	CP 1
	RET C
	PUSH AF			; stash child pid, carry flag is clear
	CALL get_process
	PUSH HL
	POP IX
	LD (IX+4),A
	LD (IX+5),TASK_UNINTERRUPTIBLE
	LD A,(IY+1)		; get our own pid
	LD (IX+7),A		; and save it in child's ppid
	PUSH IX
	CALL get_page	; obtain stack page
	POP IX
	AND A
	JR NZ,_do_fork_gotpage
	LD (IX+4),0
	POP AF			; A=pid
	PUSH DE			; save errno
	CALL free_pid
	POP DE
	SCF
	RET
_do_fork_gotpage:
	LD (IX+6),A		; assign stack page
	POP BC			; retrieve child pid
	CLI				; put process image into a schedulable state before copying
	XOR A			; ensure child returns 0 from fork()
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	SPSWAP
					; copy stack page
	LD A,(IX+6)
	LD BC,(VPAGE_FORK_STACK<<8)|IO_MMU
	IN E,(C)		; get page currently mapped in
	LD B,0x10|VPAGE_FORK_STACK
	IN D,(C)		; get prot_bits - specifically the IO bit
	PUSH DE
	OUT (C),A		; page in new stack page at pi VPAGE_FORK_STACK
	LD HL,MEM_SAVESP; bottom of stack page
	LD DE,MEM_STKTOP; top of stack page
	LD BC,PAGE_SIZE
	LDIR			; do the copy
	POP DE
	LD A,2
	AND D
	RRCA
	RRCA
	RRCA			; IO bit
	OR B
	LD B,A
	OUT (C),E		; page oldpage back in
					; mark task as runnable
	SPSWAP
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
	STI
	POP AF
.if DEBUG
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
	BUG_UNLESS(A)	; ... so let's give up now
	POP IX
	LD (IY+1),0		; clear our running process (as we're not actually running init)
	LD (IX+6),A
	LD (IX+7),0		; ppid: init has no parent
	LD BC,(VPAGE_STACK<<8)|IO_MMU
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

.globl getppid		; returns the ppid in A
getppid:
	LD A,(IY+1)		; our own pid
	LD IX,procs		; slot = procs + (pid*PROCESS_SIZE)
	LD C,A
	LD B,0
	SLA C
	RL B
	SLA C
	RL B
	SLA C
	RL B
	ADD IX,BC
	LD A,(IX+7)
	RET

.globl exit_proc
exit_proc:			; A process which RETs its entry point ends up here
	CALL panic		; Should really mark process as TASK_EXITED or something, so parent can wait()

.globl exec_init
exec_init:
.if DEBUG
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
	LD IX,test_sema
	CALL sema_init_mutex
	CALL do_fork
	JR NC,_exec_forked
	LD HL,fork
	CALL perror
	RET
_exec_forked:
	CALL kprint_hex	; show value of A register (should be <child pid> in parent, 0 in child)
	CALL getppid
	CALL kprint_hex	; show ppid
	LD IX,test_sema
	CALL down
	CALL sched_yield
	CALL up
	CALL sched_yield
	CALL sched_yield
	CALL panic		; Haven't yet written a process loader (or a filesystem to load init from)

.data
.globl runq_lock, runq, nextpid_lock
runq_lock: .byte 0xfe
nextpid_lock: .byte 0xfe ; also guards pid_map
nextpid: .byte 2
.if DEBUG
got_proc_1: .asciz "Created process "
exec_init_1: .asciz "CPU #"
exec_init_2: .asciz " started init, pid="
sched_waiting: .asciz "No process runnable on CPU "
sched_chose_1: sched_exit_1: sched_yield_1: sched_sleep_1: .asciz "pid "
sched_chose_2: .asciz " scheduled on CPU "
sched_exit_2: .asciz " preempted on CPU "
sched_yield_2: .asciz " yield     on CPU "
sched_sleep_2: .asciz " slept     on CPU "
.endif
fork: .asciz "fork"

.bss
runq: .skip 4
procs: .skip PROCESS_SIZE * PROC_SLOTS; we're actually being inefficient and reserving a slot for the non-existent pid 0
pid_map: .skip (PROC_SLOTS+7)/8
test_sema: .skip SEMAPHORE_SIZE
