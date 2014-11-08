.ifndef _BLOCK_INC
_BLOCK_INC equ 1

BLOCK_DEVICE_OPS_SIZE equ 6; sizeof(struct block_device_ops)
; struct block_device_ops {
BDOP_SIZE equ 0;	uint16_t (*bsize)(__IX struct pegbus_device *dev); /* get size (in pages) of dev */
BDOP_READ equ 2;	int (*bread)(__IX struct pegbus_device *dev, __HL uint16_t bpage, __D uint8_t rpage); /* read bpage from dev into rpage */
BDOP_WRITE equ 4;	int (*bwrite)(__IX struct pegbus_device *dev, __A uint8_t rpage, __DE uint16_t bpage); /* write rpage to dev at bpage */
;}

.macro DECLARE_BLOCK_OPS bsize=0,bread=0,bwrite=0
.word bsize,bread,bwrite
.endm

BLOCK_DEVICE_SIZE equ 8; struct block_device {
BDEV_LIST equ 0;	struct list_head list;
BDEV_DEV  equ 4;	struct pegbus_device *dev;
BDEV_OPS  equ 6;	struct block_device_ops *ops;
;}

.endif
