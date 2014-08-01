CFLAGS := -Wall -Wextra -Werror -pedantic --std=gnu99 -g

all: pegasus os/main.bin

# Rules to build the emulator
EM_OBJS := pegasus.o z80.o ops.o

pegasus: $(EM_OBJS)
	$(CC) $(LDFLAGS) -o $@ $(EM_OBJS)

pegasus.o: z80.h ops.h

%.o: %.c %.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ -c $<

# Rules to build target executables
os/main.bin: FORCE
	make -C os

FORCE:

clean:
	-rm -f pegasus *.o
	make -C os clean
