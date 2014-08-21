.include "list.inc"

; struct process { struct list_head runq; byte pid; enum status_t status; byte basepage; };
PROCESS_SIZE equ	LIST_HEAD_SIZE+3

; enum status_t
TASK_RUNNING equ 0
TASK_RUNNABLE equ 1
TASK_INTERRUPTIBLE equ 2
TASK_UNINTERRUPTIBLE equ 3

.macro percpu		; stores address of top of percpu data area in HL (and cpuid in E)
	LD BC,0x2004
	IN E,(C)		; read cpuid from MMU
	LD A,0x80		; percpu data is at 0x1000 - cpuindex*0x20 = (0x8000 - cpuindex*0x100)/8
	SUB E
	LD H,A
	LD L,0
	SRL H
	RR L
	SRL H
	RR L
	SRL H
	RR L
.endm
