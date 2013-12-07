AS := z80-unknown-coff-as
ASFLAGS := -z80
LD := z80-unknown-coff-ld
LDFLAGS := -T m80.ld

all: locktest.bin

%.bin: %.o $(OBJS) m80.ld
	$(LD) -o $@ $< $(LDFLAGS) $(OBJS)

%.o: %.asm
	$(AS) $(ASFLAGS) $< -o $@

FORCE:

clean:
	-rm -f *.o *.bin

