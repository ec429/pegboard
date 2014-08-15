CFLAGS := -Wall -Wextra -Werror -pedantic --std=gnu99 -g

all: pegasus pegbox

# Rules to build the emulator
EM_OBJS := pegasus.o z80.o ops.o

pegasus: $(EM_OBJS)
	$(CC) $(LDFLAGS) -o $@ $(EM_OBJS)

pegasus.o: z80.h ops.h

%.o: %.c %.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ -c $<

# Rules to build target executables
pegbox: FORCE
	make -C pegbox

FORCE:

clean:
	-rm -f pegasus *.o
	make -C pegbox clean
