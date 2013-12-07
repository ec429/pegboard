.text

.globl kputc		; write single character (in A) to terminal
kputc:
	LD IX,kprint_lock
	CALL spin_lock
	OUT (0x10),A
	CALL spin_unlock
	RET

.globl kputc_unlocked ; as kputc but must already hold the kprint_lock
kputc_unlocked:
	OUT (0x10),A
	RET

.globl kputs		; write string (at HL) to terminal; max length 256
kputs:
	LD BC,0x100
	PUSH HL
	POP IX
	XOR A
	CPIR
	RET NZ
	LD A,C
	NEG
	LD B,A
	LD C,0x10
	PUSH IX
	POP HL
	LD IX,kprint_lock
	CALL spin_lock
	OTIR
	CALL spin_unlock
	RET

.globl kputs_unlocked ; as kputs but must already hold the kprint_lock
kputs_unlocked:
	LD BC,0x100
	PUSH HL
	POP IX
	XOR A
	CPIR
	RET Z
	LD A,C
	NEG
	LD B,A
	LD C,0x10
	PUSH IX
	POP HL
	OTIR
	RET

.data
.globl kprint_lock
kprint_lock: .byte 0xfe
