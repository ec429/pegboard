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
	;spin_lock(sem->lock);
	SPIN_LOCK_AT SEMA_LOCK
	;if (!sem->value) { /* contention case - put us on the waitq */
	LD A,(IX+SEMA_VAL)
	DEC A
	JR NC,_down_fast
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
	;	sched_sleep();
	CALL sched_sleep
	;	/* We've returned from sched_sleep(), so we must hold the sem now */
	RET
	;} else { /* no contention - it's ours */
_down_fast:
	;	sem->value--;
	LD (IX+SEMA_VAL),A
	;	spin_unlock(sem->lock);
	SPIN_UNLOCK_AT SEMA_LOCK
	;}
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
	RET
