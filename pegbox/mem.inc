.ifndef _MEM_INC
_MEM_INC equ 1

NOPAGE equ 0
IO_MMU equ 0x04

KERNEL_PPAGES equ 0x1; number of pages used by kernel binary image

; process stack page and addresses
VPAGE_STACK equ 0x1
VPAGE_FORK_STACK equ VPAGE_STACK+1
MEM_SAVESP equ 0x1000
MEM_VM_MAP equ 0x1002
MEM_STKTOP equ 0x2000

.endif
