CFLAGS := -Wall -Wextra -Werror -pedantic --std=gnu99 -g

all: m80em os/main.bin

# Rules to build the emulator
EM_OBJS := m80em.o z80.o ops.o

m80em: $(EM_OBJS)
	$(CC) $(LDFLAGS) -o $@ $(EM_OBJS)

m80em.o: z80.h ops.h

%.o: %.c %.h
	$(CC) $(CFLAGS) $(CPPFLAGS) -o $@ -c $<

# Rules to build target executables
os/main.bin: FORCE
	make -C os

FORCE:

clean:
	-rm -f m80em *.o
	make -C os clean
