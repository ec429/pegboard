.ifndef _SEMAPHORE_INC
_SEMAPHORE_INC equ 1

SEMAPHORE_SIZE	equ 6
; struct semaphore {
SEMA_WQ   equ 0;	struct list_head waitq;
SEMA_VAL  equ 4;	byte value;
SEMA_LOCK equ 5;	spinlock_t lock;
;}

.endif
