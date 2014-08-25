.ifndef _SCHED_INC
_SCHED_INC equ 1

.include "list.inc"
.include "mem.inc"

PROCESS_SIZE equ	8
; struct process {
PROC_RUNQ equ 0;	struct list_head runq;
PROC_PID  equ 4;	byte pid;
PROC_STAT equ 5;	enum status_t status;
PROC_BASE equ 6;	byte basepage;
PROC_PPID equ 7;	byte ppid;
;}

; enum status_t
TASK_RUNNING equ 0
TASK_RUNNABLE equ 1
TASK_INTERRUPTIBLE equ 2
TASK_UNINTERRUPTIBLE equ 3

; struct percpu_struct {
;   u8 cpuid;
;	u8 current_pid;
;	u8 cli_depth;
;	u8 unused;
; }

PERCPU_SIZE equ 4

.macro percpu		; stores address of top of percpu data area in HL (and cpuid in E)
	LD BC,0x2004
	IN E,(C)		; read cpuid from MMU
	LD HL,PERCPU_TOP>>PERCPU_SHIFT
	LD D,0
	AND A			; clear carry flag
	SBC HL,DE
.rept PERCPU_SHIFT
	SLA L
	RL H
.endr
	LD A,PERCPU_PPAGE
	OUT (4),A		; page in PERCPU_PPAGE at pi PERCPU_PPAGE
.endm

.macro spswap		; swaps SP with [MEM_SAVESP]
	LD HL,0
	ADD HL,SP
	LD SP,(MEM_SAVESP)
	LD (MEM_SAVESP),HL
.endm

.endif
