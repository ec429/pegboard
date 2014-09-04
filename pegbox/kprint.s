IO_TERMINAL	equ 0x10

.text

.globl kputc		; write single character (in A) to terminal
kputc:
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	OUT (IO_TERMINAL),A
	CALL spin_unlock_irqsave
	RET

.globl kputc_unlocked ; as kputc but must already hold the kprint_lock
kputc_unlocked:
	OUT (IO_TERMINAL),A
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
	LD C,IO_TERMINAL
	RET

.globl kputs		; write string (at HL) to terminal; max length 256
kputs:
	CALL kputs_prepare
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	OTIR
	CALL spin_unlock_irqsave
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
	CALL spin_lock_irqsave
	OUT (IO_TERMINAL),A
	LD A,D
	OUT (IO_TERMINAL),A
	LD A,0x0a
	OUT (IO_TERMINAL),A
	CALL spin_unlock_irqsave
	RET

.globl kprint_hex_unlocked ; as kprint_hex but must already hold the kprint_lock; and no \n
kprint_hex_unlocked:
	CALL kprint_hex_prepare
	OUT (IO_TERMINAL),A
	LD A,D
	OUT (IO_TERMINAL),A
	RET

.globl kprint_half_hex; write low nybble of A as hex to terminal (no 0x prefix), plus trailing \n
kprint_half_hex:
	CALL kprint_hex_prepare
	LD A,D
	LD IX,kprint_lock
	CALL spin_lock_irqsave
	OUT (IO_TERMINAL),A
	LD A,0x0a
	OUT (IO_TERMINAL),A
	CALL spin_unlock_irqsave
	RET

.globl kprint_half_hex_unlocked ; as kprint_half_hex but must already hold the kprint_lock; and no \n
kprint_half_hex_unlocked:
	CALL kprint_hex_prepare
	LD A,D
	OUT (IO_TERMINAL),A
	RET

.data
.globl kprint_lock
kprint_lock: .byte 0xfe
