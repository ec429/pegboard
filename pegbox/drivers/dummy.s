.include "pegbus.inc"

; driver for test device (0xff0d)

PDEV_ID_TEST_DEVICE equ 0xff0d

.text
test_device_driver_probe:; probe device *IX, mapped at 0xf000
	LD A,(IX+PDEV_SLOT)
	PUSH AF
	LD A,PEGBUS_CMD_SHUTUP
	LD (0xf003),A
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
test_device_driver_probed: .asciz "test_device: Probed device (id 0xff0d) in slot "
test_device_driver: DECLARE_PEGBUS_DRIVER PDEV_ID_TEST_DEVICE, test_device_driver_probe

.section drv
.word test_device_driver
