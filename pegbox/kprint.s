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

kputs_prepare:
	LD BC,0x100
	PUSH HL
	XOR A
	CPIR
	POP HL
	RET NZ
	LD A,C
	NEG
	LD B,A
	DEC B			; don't write the NUL
	LD C,0x10
	RET

.globl kputs		; write string (at HL) to terminal; max length 256
kputs:
	CALL kputs_prepare
	LD IX,kprint_lock
	CALL spin_lock
	OTIR
	CALL spin_unlock
	RET

.globl kputs_unlocked ; as kputs but must already hold the kprint_lock
kputs_unlocked:
	CALL kputs_prepare
	OTIR
	RET

kprint_hex_prepare:
	PUSH AF
	AND 0xf
	ADD A,0x30
	CP 0x3a
	JR C,khp_save
	ADD A,7
khp_save:
	LD D,A
	POP AF
	SRL A
	SRL A
	SRL A
	SRL A
	ADD A,0x30
	CP 0x3a
	RET C
	ADD A,7
	RET

.globl kprint_hex	; write value in A as hex to terminal (no 0x prefix), plus trailing \n
kprint_hex:
	CALL kprint_hex_prepare
	LD IX,kprint_lock
	CALL spin_lock
	OUT (0x10),A
	LD A,D
	OUT (0x10),A
	LD A,0x0a
	OUT (0x10),A
	CALL spin_unlock
	RET

.globl kprint_hex_unlocked ; as kprint_hex but must already hold the kprint_lock; and no \n
kprint_hex_unlocked:
	CALL kprint_hex_prepare
	OUT (0x10),A
	LD A,D
	OUT (0x10),A
	RET

.data
.globl kprint_lock
kprint_lock: .byte 0xfe
