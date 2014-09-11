TARGET_AS := z80-unknown-coff-as
TARGET_ASFLAGS := -z80
TARGET_LD := z80-unknown-coff-ld
TARGET_LDFLAGS := -T kernel.ld

TARGET_OBJS := init.zo main.zo spinlock.zo kprint.zo mem.zo errno.zo sched.zo panic.zo list.zo pegbus.zo semaphore.zo kmalloc.zo

all: kernel.bin

# Rules to build target executables
kernel.bin: $(TARGET_OBJS) kernel.ld
	$(TARGET_LD) -o $@ $(TARGET_LDFLAGS) $(TARGET_OBJS) -Map kernel.sym

init.zo: sched.inc list.inc mem.inc
main.zo: sched.inc list.inc mem.inc spinlock.inc
sched.zo: sched.inc list.inc mem.inc spinlock.inc
mem.zo: mem.inc
panic.zo: mem.inc spinlock.inc
pegbus.zo: pegbus.inc sched.inc list.inc mem.inc spinlock.inc
semaphore.zo: semaphore.inc spinlock.inc sched.inc
spinlock.zo: spinlock.inc
kmalloc.zo: mem.inc list.inc spinlock.inc

%.zo: %.s errno.inc debug.inc
	$(TARGET_AS) $(TARGET_ASFLAGS) $< -o $@

FORCE:

clean:
	-rm -f *.zo *.bin

