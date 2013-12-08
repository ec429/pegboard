.text

.globl main			; per-CPU OS entry point.  Does not return
main:
	LD A,(IY+0)
	AND A
	CALL Z,cpu0_setup
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,start_msg_1
	CALL kputs_unlocked
	LD A,(IY+0)
	CALL kprint_hex_unlocked
	LD HL,start_msg_2
	CALL kputs_unlocked
	LD IX,kprint_lock
	CALL spin_unlock
	HALT

cpu0_setup:
	CALL setup_mem_map
	LD HL,can_start_other_cpus
	LD (HL),1
	RET

setup_mem_map:		; called with A=0
	INC A
	OUT (0x05),A	; set pi 1 to page 1
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
	OUT (C),D		; set pi 2 to page %D
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

.data
start_msg_1: .asciz "CPU #"
start_msg_2: .ascii " online"
.byte 0x0a,0
mem_map_ready: .ascii "Memory map ready"
.byte 0x0a,0

.section mem_page
.org 0
mem_lock: .byte 0xfe
mem_free: .byte 0
mem_map: .skip 254
