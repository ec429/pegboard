.ifndef _DEBUG_INC
_DEBUG_INC equ 1

DEBUG equ 1			; enable debug messages

.macro BUILD_BUG_ON expr; compile-time assertion
.if \expr
.error "Assertion failed \expr"
.endif
.endm

.macro BUG_ON register; run-time assertion 8-bit operand is zero (clobbers: A)
.if \register != A
	LD A,\register
.endif
	AND A
	CALL NZ,panic
.endm

.macro BUG_UNLESS register; run-time assertion 8-bit operand is zero (clobbers: A)
.if \register != A
	LD A,\register
	.error "\register"
.endif
	AND A
	CALL Z,panic
.endm

.macro BUG_ON_HL; run-time assertion HL is zero (clobbers: A)
	LD A,H
	OR L
	CALL NZ,panic
.endm

.macro BUG_UNLESS_HL; run-time assertion HL nonzero (clobbers: A)
	LD A,H
	OR L
	CALL Z,panic
.endm

.endif
