.ifndef _MEM_INC
_MEM_INC equ 1

NOPAGE equ 0
IO_MMU equ 0x04
PAGE_SIZE equ 0x1000

KERNEL_PPAGES equ 0x2; number of pages used by kernel binary image

; process stack page and addresses
VPAGE_STACK equ KERNEL_PPAGES
VPAGE_FORK_STACK equ VPAGE_STACK+1
MEM_SAVESP equ (VPAGE_STACK<<12)
MEM_VM_MAP equ (VPAGE_STACK<<12)+2
MEM_STKTOP equ (VPAGE_STACK<<12)+PAGE_SIZE

.endif
