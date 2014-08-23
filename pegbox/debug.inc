DEBUG equ 1			; enable debug messages

.macro BUILD_BUG_ON expr
.if \expr
.error "Assertion failed \expr"
.endif
.endm
