#
# Makefile for the SGI specific kernel interface routines
# under Linux.
#

obj-y	+= ip22-mc.o ip22-hpc.o ip22-int.o ip22-irq.o ip22-berr.o \
	   ip22-time.o ip22-rtc.o ip22-nvram.o ip22-reset.o \
	   ip22-setup.o ip22-ksyms.o

obj-$(CONFIG_EISA)	+= ip22-eisa.o

EXTRA_AFLAGS := $(CFLAGS)
