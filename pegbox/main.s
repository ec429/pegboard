.include "sched.inc"
.include "debug.inc"
.include "mem.inc"
.include "spinlock.inc"
.text

.globl main			; per-CPU OS entry point.  Does not return
main:
	LD A,1			; page in all kernel ppages
_main_page_loop:
	OUT (4),A		; page in A at pi A
	INC A
	CP KERNEL_PPAGES
	JR NZ,_main_page_loop
	LD A,0x02		; set intvec = 0x02
	LD I,A
; we are now online
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	LD HL,start_msg_1
	CALL kputs_unlocked
	LD A,(IY+0)
	CALL kprint_hex_unlocked
	LD HL,start_msg_2
	CALL kputs_unlocked
	LD IX,kprint_lock
	CALL spin_unlock_irqsave
	LD A,(IY+0)
	AND A
	CALL Z,cpu0_setup
	STI
_main_idle:
	HALT
	JR _main_idle
cpu0_setup:
	CALL setup_mem_map
	CALL init_kmalloc_arena
	CALL setup_scheduler
	CALL setup_interrupts
	CALL pegbus_setup
	LD HL,STR_booting
	CALL kputs
	LD HL,can_start_other_cpus
	LD (HL),1
	RET				; init is now ready to be entered by whichever CPU schedules first

setup_interrupts:
	LD HL,INT_timer	; plumb timer interrupt
	LD (ivtbl+2),HL
	RET

INT_timer:			; handler for timer interrupt
	EX AF,AF'
	EXX
	PERCPU
	LD IY,-PERCPU_SIZE
	EX DE,HL
	ADD IY,DE		; IY points to the percpu_struct
	LD A,(IY+1)		; current PID
	AND A
	JR Z,_int_timer_schedule
	EXX				; we're in a process, so we need to save state.
	EX AF,AF'		; XXX for now we'll assume we were in kernel-space, so the right stack is already paged in
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IX
	SPSWAP
	CALL sched_exit
	CALL sched_put
_int_timer_schedule:; pick a process and schedule into it.  (And we're not in a process, so we can trash regs)
					; but first, check no-one has panicked
	LD A,(can_start_other_cpus)
	AND A
	JR Z,_int_timer_panicked
	CALL sched_choose
	JR C,_int_timer_noproc
	CLI				; taking the interrupt DI'd us; so increment the cli_depth
	JP sched_enter
_int_timer_noproc:	; no process found, so just return (to _main_idle)
	EI
	RETI
_int_timer_panicked:; panic on another cpu, so stop
	HALT

.section isr
.globl unhandled_irq
unhandled_irq:
	EX AF,AF'
	EXX
	PUSH IX
	PERCPU
	LD IY,-PERCPU_SIZE
	EX DE,HL
	ADD IY,DE		; IY points to the percpu_struct
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	LD HL,unh_irq
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock_irqsave
	POP IX
	EXX
	EX AF,AF'
	EI
	RETI

.section ivt
.globl ivtbl
ivtbl:
.rept 0x80
.word unhandled_irq	; fill interrupt table with unhandled_IRQ vector
.endr

.data
STR_booting: .ascii "Booting PEGBOx kernel 0.0.1-pre"
.byte 0x0a,0
start_msg_1: .asciz "CPU #"
start_msg_2: .ascii " online"
.byte 0x0a,0
unh_irq: .asciz "Unhandled IRQ on CPU "
