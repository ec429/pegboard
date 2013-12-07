TARGET_AS := z80-unknown-coff-as
TARGET_ASFLAGS := -z80
TARGET_LD := z80-unknown-coff-ld
TARGET_LDFLAGS := -T m80.ld

CFLAGS := -Wall -Wextra -Werror -pedantic --std=gnu99 -g

all: locktest.bin m80em

# Rules to build the emulator
EM_OBJS := m80em.o z80.o ops.o

m80em: $(EM_OBJS)
	$(CC) $(LDFLAGS) -o $@ $(EM_OBJS)

m80em.o: z80.h ops.h

%.o: %.c %.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ -c $<

# Rules to build target executables
%.bin: %.zo $(TARGET_OBJS) m80.ld
	$(TARGET_LD) -o $@ $< $(TARGET_LDFLAGS) $(TARGET_OBJS)

%.zo: %.s
	$(TARGET_AS) $(TARGET_ASFLAGS) $< -o $@

FORCE:

clean:
	-rm -f *.zo *.bin

