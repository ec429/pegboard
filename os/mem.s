.include "errno.s"

.text

.globl setup_mem_map
setup_mem_map:
	LD IX,mem_lock
	CALL spin_lock
	LD (IX+1),0
	LD BC,0xfe
	LD DE,mem_map
	LD HL,mem_free
	LDIR
	LD C,0x05
	LD B,2
	LD D,B
	LD HL,0x8000
smm_next_page:
	OUT (C),D		; set pi 2 to page D
	XOR A
	LD (HL),A
	LD A,(HL)
	AND A
	JR NZ,smm_end_free_pages
	INC (IX+1)
	INC D
	JR NZ,smm_next_page
smm_end_free_pages:
	CALL spin_unlock
	LD HL,mem_map_ready
	CALL kputs
	RET

.globl get_page		; returns page number (or 0) in A, errno in E
get_page:
	LD IX,mem_lock
	PUSH IX
	CALL spin_lock
	INC IX			; mem_free
	LD A,(IX+0)
	AND A
	LD E,ENOMEM
	JR Z,gp_fail
	DEC (IX+0)
	LD D,1
gp_next_page:
	INC IX
	INC D
	LD A,(IX+0)
	AND A
	JR NZ,gp_next_page ; will succeed before running out of pages, because mem_free was nonzero
	LD A,(IY+1)		; PID
	LD (IX+0),A
	POP IX
	CALL spin_unlock
	PUSH DE
;#ifdef DEBUG
	LD IX,kprint_lock
	CALL spin_lock
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
	CALL spin_unlock
;#endif
	LD E,0
	POP AF
	RET
gp_fail:
	POP IX
	CALL spin_unlock
	XOR A
	RET

.globl free_page	; frees page A, if owned by current PID.  errno in E
free_page:
	CP 2
	LD E,EINVAL
	RET C
	LD D,(IY+1)		; PID
	LD IX,mem_lock
	CALL spin_lock
	LD B,0
	LD C,A
	PUSH IX
	ADD IX,BC
	LD A,(IX+0)
	SUB D
	LD E,EFAULT
	JR NZ,fp_fail
	LD (IX+0),A		; the SUB will have left A=0
	POP IX
	INC (IX+1)		; mem_free
	CALL spin_unlock
;#ifdef DEBUG
	PUSH BC
	PUSH DE
	LD IX,kprint_lock
	CALL spin_lock
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
	CALL spin_unlock
;#endif
	LD E,0
	RET
fp_fail:
	POP IX
	CALL spin_unlock
	RET

.data
; debugging strings
mem_map_ready: .ascii "Memory map ready"
.byte 0x0a,0
got_page_1: .asciz "Process "
freed_page_1 equ got_page_1
got_page_2: .asciz " got page "
freed_page_2: .asciz " freed page "

.section mem_page
.org 0
mem_lock: .byte 0xfe
mem_free: .byte 0
mem_map: .skip 254
