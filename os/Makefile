TARGET_AS := z80-unknown-coff-as
TARGET_ASFLAGS := -z80
TARGET_LD := z80-unknown-coff-ld
TARGET_LDFLAGS := -T ../m80.ld

TARGET_OBJS := init.zo spinlock.zo kprint.zo mem.zo

all: main.bin

# Rules to build target executables
main.bin: main.zo $(TARGET_OBJS) ../m80.ld
	$(TARGET_LD) -o $@ main.zo $(TARGET_LDFLAGS) $(TARGET_OBJS) -Map main.sym

mem.zo: errno.s

%.zo: %.s
	$(TARGET_AS) $(TARGET_ASFLAGS) $< -o $@

FORCE:

clean:
	-rm -f *.zo *.bin

