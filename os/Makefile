TARGET_AS := z80-unknown-coff-as
TARGET_ASFLAGS := -z80
TARGET_LD := z80-unknown-coff-ld
TARGET_LDFLAGS := -T ../m80.ld

TARGET_OBJS := main.zo init.zo spinlock.zo

all: main.bin

# Rules to build target executables
%.bin: %.zo $(TARGET_OBJS) ../m80.ld
	$(TARGET_LD) -o $@ $(TARGET_LDFLAGS) $(TARGET_OBJS)

%.zo: %.s
	$(TARGET_AS) $(TARGET_ASFLAGS) $< -o $@

os:
	make -C os

FORCE:

clean:
	-rm -f *.zo *.bin

