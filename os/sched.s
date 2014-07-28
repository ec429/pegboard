.include "sched.inc"
.include "mem.inc"
.include "errno.inc"

.text

.globl createproc	; adds process with pid A to tail of waitqueue.  errno in E
createproc:
	PUSH AF
	LD IX,waitq_lock
	CALL spin_lock
	LD B,0xf8
	LD HL,waitq
_createproc_nextslot:
	LD A,(HL)
	AND A
	JR Z,_createproc_foundslot
	INC HL
	INC HL
	INC HL
	INC B
	JR NZ,_createproc_nextslot
	CALL spin_unlock
	POP BC
	LD E,EAGAIN
	RET
_createproc_foundslot:
	POP AF
	LD (HL),A
	INC HL
	LD (HL),TASK_UNINTERRUPTIBLE
	INC HL
	LD (HL),NOPAGE
	LD IX,waitq_lock
	CALL spin_unlock
	RET

.data
.globl runq_lock, waitq_lock
runq_lock: .byte 0xfe
runq: .skip 24
waitq_lock: .byte 0xfe
waitq: .skip 24
