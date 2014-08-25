.include "semaphore.inc"
.include "spinlock.inc"
.include "sched.inc"
.include "debug.inc"

.text

.globl sema_init_mutex; initialise (struct semaphore *)IX with count 1; i.e. a binary semaphore
sema_init_mutex:
	LD A,1
	; fall into sema_init
.globl sema_init
sema_init:			; initialise (struct semaphore *)IX with count A
	CALL init_list_head
	LD (IX+SEMA_VAL),A
	LD (IX+SEMA_LOCK),0xfe
	RET

.globl down			; (struct semaphore *)IX
down:
	LD D,TASK_UNINTERRUPTIBLE
	JR _down

.globl down_interruptible; (struct semaphore *)IX
down_interruptible:
	LD D,TASK_INTERRUPTIBLE
	; fall into _down
_down:				; (struct semaphore *)IX, enum status_t D
	CLI
	;spin_lock(sem->lock);
	SPIN_LOCK_AT SEMA_LOCK
	;if (!sem->value) { /* contention case - put us on the waitq */
	LD A,(IX+SEMA_VAL)
	AND A
	JR NZ,_down_fast
	;	current->status = wstate;
	CALL get_current
	PUSH HL
	LD BC,PROC_STAT
	ADD HL,BC
	LD (HL),D
	;	list_add_tail(&current->runq, &sem->waitq);
	POP HL
	PUSH IX
	PUSH IX
	POP DE
	CALL list_add_tail
	;	spin_unlock(sem->lock);
	POP IX
	SPIN_UNLOCK_AT SEMA_LOCK
.if DEBUG
	PUSH IX
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,contention_in_down
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP IX
.endif
	;	sched_sleep();
	STIDI
	CALL sched_sleep
	;	/* We've returned from sched_sleep(), so we must hold the sem now */
.if DEBUG
	PUSH IX
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,down_after_contention
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP IX
.endif
	RET
	;} else { /* no contention - it's ours */
_down_fast:
	;	sem->value--;
	DEC (IX+SEMA_VAL)
	;	spin_unlock(sem->lock);
	SPIN_UNLOCK_AT SEMA_LOCK
	;}
.if DEBUG
	PUSH IX
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,down_without_contention
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP IX
.endif
	STI
	RET

.globl up			; (struct semaphore *)IX
up:
	;spin_lock(sem->lock);
	SPIN_LOCK_AT SEMA_LOCK
	;if (list_empty(sem->waitq)) {
	CALL list_empty_ix
	JR NZ,_up_wake
	;	sem->value++;
	INC (IX+SEMA_VAL)
	;	BUG_ON(!sem->value);
	CALL Z,panic
	;	spin_unlock(sem->lock);
	SPIN_UNLOCK_AT SEMA_LOCK
.if DEBUG
	PUSH IX
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,up_no_waiter
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP IX
.endif
	RET
	;} else { /* wake up first waiter */
_up_wake:
	;	next = list_pop(sem->waitq);
	PUSH IX
	CALL list_pop
	;	spin_unlock(sem->lock);
	POP IX
	SPIN_UNLOCK_AT SEMA_LOCK
	;	next->status = TASK_RUNNABLE;
	PUSH HL
	POP IX
	LD (IX+PROC_STAT),TASK_RUNNABLE
	;	spin_lock(runq_lock);
	LD IX,runq_lock
	CALL spin_lock
	;	list_add(&next->runq, runq); /* we add it to the head of the runq because it's been waiting.  Untested heuristic */
	LD BC,runq
	CALL list_add
	;	spin_unlock(runq_lock);
	LD IX,runq_lock
	CALL spin_unlock
	;	wake_one_cpu(); /* not implemented yet, requires IPIs */
	;}
.if DEBUG
	PUSH IX
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,up_woke_waiter
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP IX
.endif
	RET

.data:
.if DEBUG
down_after_contention: .asciz "Down after contention on CPU "
contention_in_down: .asciz "Contention in down() on CPU "
down_without_contention: .asciz "Down without contention on CPU "
up_no_waiter: .asciz "Up (no waiter) on CPU "
up_woke_waiter: .asciz "Up (woke waiter) on CPU "
.endif
