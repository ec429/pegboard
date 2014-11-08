.ifndef _PEGBUS_INC
_PEGBUS_INC equ 1

PEGBUS_CMD_SHUTUP	equ 0xf0

PEGBUS_DEVICE_SIZE	equ 10
; struct pegbus_device {
PDEV_LOCK equ 0;	spinlock_t lock;
PDEV_SLOT equ 1;	uint8_t slot;
PDEV_ID	  equ 2;	uint16_t device_id;
PDEV_BVER equ 4;	uint8_t bus_version;
;	uint8_t reserved; /* padding */
PDEV_DRIV equ 6;	struct pegbus_driver *driver;
PDEV_DATA equ 8;	void *driver_data;
;}

PEGBUS_DRIVER_SIZE	equ 8; sizeof(struct pegbus_driver)
; struct pegbus_driver {
PDRV_LIST equ 0;	struct list_head list;
PDRV_ID   equ 4;	uint16_t device_id;
PDRV_PROB equ 6;	void (*probe)(__IX struct pegbus_device *device); /* called with device->lock held */
;}

.macro DECLARE_PEGBUS_DRIVER id,probe
.word 0, 0, \id, \probe
.endm

.endif
