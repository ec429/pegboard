.include "debug.inc"
.include "sched.inc"
.include "pegbus.inc"

.text

.globl pegbus_setup	; initialise pegbus handling
pegbus_setup:
	LD IX,pegbus_drivers
	CALL init_list_head
	LD IX,test_device_driver; register driver for test device (0xff0d)
	LD (IX+PDRV_ID),0x0d
	LD (IX+PDRV_ID+1),0xff
	LD BC,test_device_driver_probe
	LD (IX+PDRV_PROB),C
	LD (IX+PDRV_PROB+1),B
	CALL pegbus_register_driver
					; hook up the IRQ lines for all 16 possible pegbus slots
	LD HL,INT_pegbus_0
	LD DE,(INT_pegbus_1-INT_pegbus_0); makes use of the fact that they're all the same length
	LD (0x0f80),HL
	ADD HL,DE
	LD (0x0f82),HL
	ADD HL,DE
	LD (0x0f84),HL
	ADD HL,DE
	LD (0x0f86),HL
	ADD HL,DE
	LD (0x0f88),HL
	ADD HL,DE
	LD (0x0f8a),HL
	ADD HL,DE
	LD (0x0f8c),HL
	ADD HL,DE
	LD (0x0f8e),HL
	ADD HL,DE
	LD (0x0f90),HL
	ADD HL,DE
	LD (0x0f92),HL
	ADD HL,DE
	LD (0x0f94),HL
	ADD HL,DE
	LD (0x0f96),HL
	ADD HL,DE
	LD (0x0f98),HL
	ADD HL,DE
	LD (0x0f9a),HL
	ADD HL,DE
	LD (0x0f9c),HL
	ADD HL,DE
	LD (0x0f9e),HL
	RET

INT_pegbus_0:
	EX AF,AF'
	LD A,0
	JR INT_pegbus

INT_pegbus_1:
	EX AF,AF'
	LD A,1
	JR INT_pegbus

INT_pegbus_2:
	EX AF,AF'
	LD A,2
	JR INT_pegbus

INT_pegbus_3:
	EX AF,AF'
	LD A,3
	JR INT_pegbus

INT_pegbus_4:
	EX AF,AF'
	LD A,4
	JR INT_pegbus

INT_pegbus_5:
	EX AF,AF'
	LD A,5
	JR INT_pegbus

INT_pegbus_6:
	EX AF,AF'
	LD A,6
	JR INT_pegbus

INT_pegbus_7:
	EX AF,AF'
	LD A,7
	JR INT_pegbus

INT_pegbus_8:
	EX AF,AF'
	LD A,8
	JR INT_pegbus

INT_pegbus_9:
	EX AF,AF'
	LD A,9
	JR INT_pegbus

INT_pegbus_a:
	EX AF,AF'
	LD A,0xa
	JR INT_pegbus

INT_pegbus_b:
	EX AF,AF'
	LD A,0xb
	JR INT_pegbus

INT_pegbus_c:
	EX AF,AF'
	LD A,0xc
	JR INT_pegbus

INT_pegbus_d:
	EX AF,AF'
	LD A,0xd
	JR INT_pegbus

INT_pegbus_e:
	EX AF,AF'
	LD A,0xe
	JR INT_pegbus

INT_pegbus_f:
	EX AF,AF'
	LD A,0xf

INT_pegbus:
	EXX
	PUSH IX
.if DEBUG
	PUSH AF
	PERCPU
	LD IY,0xfffe
	EX DE,HL
	ADD IY,DE		; IY points to the percpu_struct
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,pegbus_irq_1
	CALL kputs_unlocked
	POP AF			; pegbus slot id
	PUSH AF
	CALL kprint_half_hex_unlocked
	LD HL,pegbus_irq_2
	CALL kputs_unlocked
	LD A,(IY+0)		; cpuid
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	POP AF
.endif
	LD BC,0x0f00|IO_MMU; get page mapped in at 0xf000
	IN E,(C)
	LD B,0x1f
	IN D,(C)		; get prot_bits - specifically the IO bit
	PUSH DE
	LD D,A
	PUSH AF
	LD B,0x4f
	RLCA
	RLCA
	RLCA
	RLCA
	OUT (C),A		; map in device's first page at 0xf000
	LD IX,pegbus_devices; device = pegbus_devices+(slot*PEGBUS_DEVICE_SIZE)
	BUILD_BUG_ON(PEGBUS_DEVICE_SIZE!=8)
	SLA D
	SLA D
	SLA D
	LD B,0
	LD C,D
	ADD IX,BC
	CALL spin_lock
	LD L,(IX+PDEV_DRIV)
	LD H,(IX+PDEV_DRIV+1)
	LD A,L
	OR H
	JR NZ,_INT_pegbus_call_driver
	POP AF
	LD (IX+PDEV_SLOT),A
	LD HL,(0xf000)
	LD (IX+PDEV_ID),L
	LD (IX+PDEV_ID+1),H
	LD A,(0xf002)
	LD (IX+PDEV_BVER),A
	PUSH IX
	LD IX,pegbus_drivers; find a matching driver (by device_id HL)
_INT_pegbus_next_driver:
	LD E,(IX+PDRV_LIST)
	LD D,(IX+PDRV_LIST+1)
	PUSH HL
	LD HL,pegbus_drivers; end of the list?
	AND A			; clear carry
	SBC HL,DE
	POP HL
	JR Z,_INT_pegbus_no_driver_found
	PUSH DE
	POP IX
	LD A,(IX+PDRV_ID)
	CP L
	JR NZ,_INT_pegbus_next_driver
	LD A,(IX+PDRV_ID+1)
	CP H
	JR NZ,_INT_pegbus_next_driver
	PUSH IX
	POP DE			; driver
	POP IX			; device
	LD (IX+PDEV_DRIV),E
	LD (IX+PDEV_DRIV+1),D
	PUSH IX
	PUSH DE
	POP IX
	CALL _INT_pegbus_do_probe
	POP IX			; device
	CALL spin_unlock
	JR _INT_pegbus_out
_INT_pegbus_call_driver:
	CALL spin_unlock
	CALL panic
_INT_pegbus_no_driver_found:
	LD IX,0xf000	; send it a SHUTUP so we won't get any more interrupts
	LD (IX+3),PEGBUS_CMD_SHUTUP; if we register a matching driver later, it'll get probed then
	POP IX
	CALL spin_unlock
	PUSH HL
	LD IX,kprint_lock
	CALL spin_lock
	LD HL,pegbus_no_driver
	CALL kputs_unlocked
	POP HL
	PUSH HL
	LD A,H
	CALL kprint_hex_unlocked
	POP HL
	LD A,L
	CALL kprint_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
_INT_pegbus_out:
	POP DE			; E=oldpage, D=oldprotbits
	LD BC,0x0f00|IO_MMU; restore previously mapped page
	LD A,2
	AND D
	RRCA
	RRCA
	RRCA			; IO bit
	OR B
	LD B,A
	OUT (C),E
	POP IX
	EXX
	EX AF,AF'
	EI
	RETI

_INT_pegbus_do_probe:; ((struct pegbus_driver *)IX)->probe((struct pegbus_device *)(SP+4))
	LD L,(IX+PDRV_PROB); TODO really we ought to add it to some kind of workthread, rather than doing all this in interrupt context
	LD H,(IX+PDRV_PROB+1)
	POP BC			; return address
	POP IX			; struct pegbus_device
	PUSH IX
	PUSH BC
	JP (HL)

.globl pegbus_register_driver; register (struct pegbus_driver *)IX
pegbus_register_driver:
	PUSH IX
	LD L,(IX+PDRV_ID); get driver->device_id
	LD H,(IX+PDRV_ID+1)
	LD IX,pegbus_drivers_lock
	CALL spin_lock
	LD B,16
	LD IX,pegbus_devices
_pegbus_register_driver_loop:
	LD A,(IX+PDEV_DRIV); check for device->driver
	OR (IX+PDEV_DRIV+1)
	JR NZ,_pegbus_register_driver_next; there's already a driver on this device, so skip it
	PUSH HL
	LD E,(IX+PDEV_ID); device->device_id
	LD D,(IX+PDEV_ID+1)
	SBC HL,DE
	POP HL
	JR NZ,_pegbus_register_driver_next
	POP DE			; driver
	PUSH DE
	PUSH BC
	PUSH IX			; device
	LD (IX+PDEV_DRIV),E; device->driver=driver
	LD (IX+PDEV_DRIV+1),D
	CALL _INT_pegbus_do_probe
	POP IX
	POP BC
_pegbus_register_driver_next:
	LD DE,PEGBUS_DEVICE_SIZE
	ADD IX,DE
	DJNZ _pegbus_register_driver_loop
	LD DE,pegbus_drivers
	POP HL
	CALL list_add_tail
	LD IX,pegbus_drivers_lock
	CALL spin_unlock
	RET

test_device_driver_probe:; probe device *IX
	LD A,(IX+PDEV_SLOT)
	PUSH AF
	LD BC,0x0f00|IO_MMU; get page mapped in at 0xf000
	IN E,(C)
	LD B,0x1f
	IN D,(C)		; get prot_bits - specifically the IO bit
	PUSH DE
	LD BC,0x4f00|IO_MMU
	RLCA
	RLCA
	RLCA
	RLCA
	OUT (C),A		; map in device's first page at 0xf000
	LD A,PEGBUS_CMD_SHUTUP
	LD (0xf003),A
	POP DE			; E=oldpage, D=oldprotbits
	LD BC,0x0f00|IO_MMU; restore previously mapped page
	LD A,2
	AND D
	RRCA
	RRCA
	RRCA			; IO bit
	OR B
	LD B,A
	OUT (C),E
	LD HL,test_device_driver_probed
	LD IX,kprint_lock
	CALL spin_lock
	CALL kputs_unlocked
	POP AF
	CALL kprint_half_hex_unlocked
	LD A,0x0a
	CALL kputc_unlocked
	CALL spin_unlock
	RET

.data
.if DEBUG
pegbus_irq_1: .asciz "pegbus device in slot "
pegbus_irq_2: .asciz " interrupted CPU "
.endif
pegbus_no_driver: .asciz "No driver for pegbus device_id "
test_device_driver_probed: .asciz "test_device: Probed device (id 0xff0d) in slot "
pegbus_drivers_lock: .byte 0xfe
pegbus_devices:.rept 16
.byte 0xfe,0,0,0,0,0,0,0
.endr

.bss
pegbus_drivers: .skip 4; list_head
test_device_driver: .skip PEGBUS_DRIVER_SIZE
