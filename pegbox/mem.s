.include "errno.inc"
.include "mem.inc"
.include "debug.inc"

.text

.globl setup_mem_map
setup_mem_map:
	LD IX,mem_lock
	CALL spin_lock_irqsave
	LD (IX+1),0
	LD BC,256-RESERVED_PPAGES
	LD DE,mem_map+1
	LD HL,mem_map
	LD (HL),0
	LDIR
	LD C,IO_MMU
	LD B,VPAGE_STACK
	LD D,RESERVED_PPAGES
	LD HL,MEM_SAVESP
smm_next_page:
	OUT (C),D		; set pi 1 to page D
	XOR A
	LD (HL),A
	LD A,(HL)
	AND A
	JR NZ,smm_end_free_pages
	INC (IX+1)
	INC D
	JR NZ,smm_next_page
smm_end_free_pages:
	PUSH DE
	CALL spin_unlock_irqsave
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	LD HL,mem_map_ready
	CALL kputs_unlocked
	LD HL,mem_size_1
	CALL kputs_unlocked
	POP AF
	CALL kprint_hex_unlocked
	LD HL,mem_size_2
	CALL kputs_unlocked
	CALL spin_unlock_irqsave
	RET

.globl get_page		; returns page number (or 0) in A, errno in E
get_page:
	LD A,(IY+1)		; check PID != 0
	AND A
	LD E,EFAULT
	RET Z
	LD IX,mem_lock
	PUSH IX
	CALL spin_lock_irqsave
	LD A,(IX+1)
	AND A
	LD E,ENOMEM
	JR Z,gp_fail
	DEC (IX+1)
	LD D,RESERVED_PPAGES-1
	LD IX,mem_map-1
gp_next_page:
	INC IX
	INC D
	LD A,(IX+0)
	AND A
	JR NZ,gp_next_page ; will succeed before running out of pages, because mem_free was nonzero
	LD A,(IY+1)		; PID
	LD (IX+0),A
	POP IX
	CALL spin_unlock_irqsave
	PUSH DE
.if DEBUG
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	LD HL,got_page_1
	CALL kputs_unlocked
	LD A,(IY+1)		; PID
	CALL kprint_hex_unlocked
	LD HL,got_page_2
	CALL kputs_unlocked
	POP AF
	PUSH AF
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	LD IX,kprint_lock
	CALL spin_unlock_irqsave
.endif
	LD E,0
	POP AF
	RET
gp_fail:
	POP IX
	CALL spin_unlock_irqsave
.if DEBUG
	PUSH DE
	LD HL,get_page_fail
	CALL perror
	POP DE
.endif
	XOR A
	RET

.globl free_page	; frees page A, if owned by current PID.  errno in E
free_page:
	CP 1
	LD E,EINVAL
	RET C
	LD D,(IY+1)		; PID
	LD IX,mem_lock
	CALL spin_lock_irqsave
	LD B,0
	LD C,A
	LD HL,mem_map-RESERVED_PPAGES
	ADD HL,BC
	LD A,(HL)
	SUB D
	LD E,EFAULT
	JR NZ,fp_fail
	LD (HL),A		; the SUB will have left A=0
	INC (IX+1)		; mem_free
	CALL spin_unlock_irqsave
.if DEBUG
	PUSH BC
	PUSH DE
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	LD HL,freed_page_1
	CALL kputs_unlocked
	POP AF
	CALL kprint_hex_unlocked
	LD HL,freed_page_2
	CALL kputs_unlocked
	POP BC
	LD A,C
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	LD IX,kprint_lock
	CALL spin_unlock_irqsave
.endif
	LD E,0
	RET
fp_fail:
	CALL spin_unlock_irqsave
	RET

.data
; debugging strings
mem_map_ready: .ascii "Memory map ready"
.byte 0x0a,0
mem_size_1: .asciz "Found 0x"
mem_size_2: .ascii " pages"
.byte 0x0a,0
.if DEBUG
got_page_1: .asciz "Process "
freed_page_1 equ got_page_1
got_page_2: .asciz " got page "
freed_page_2: .asciz " freed page "
get_page_fail: .asciz "get_page failed"
.endif
; allocation state
.globl mem_lock
mem_lock: .byte 0xfe
mem_free: .byte 0	; mustn't be in .bss as we depend on it being mem_lock+1

.bss
mem_map: .skip 256-RESERVED_PPAGES
