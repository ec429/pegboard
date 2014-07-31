TARGET_AS := z80-unknown-coff-as
TARGET_ASFLAGS := -z80
TARGET_LD := z80-unknown-coff-ld
TARGET_LDFLAGS := -T ../m80.ld

TARGET_OBJS := init.zo main.zo spinlock.zo kprint.zo mem.zo errno.zo sched.zo panic.zo

all: kernel.bin

# Rules to build target executables
kernel.bin: $(TARGET_OBJS) ../m80.ld
	$(TARGET_LD) -o $@ $(TARGET_LDFLAGS) $(TARGET_OBJS) -Map main.sym

sched.zo: sched.inc mem.inc flags.inc
mem.zo: flags.inc

%.zo: %.s errno.inc
	$(TARGET_AS) $(TARGET_ASFLAGS) $< -o $@

FORCE:

clean:
	-rm -f *.zo *.bin

