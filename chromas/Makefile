# Makefile for building PRISM Chroma personalities

TOPDIR = $(shell pwd)

YOSYS_DIR ?= ../../yosys-prism
YOSYS := $(YOSYS_DIR)/yosys
CFG := $(TOPDIR)/tinyqv.cfg

CHROMAS := $(basename $(notdir $(wildcard chroma*.v)))

# Pattern rule to build .lst and .tab from .v
%.lst %.tab: %.v
	@echo "Building Chroma: $*"
	$(YOSYS) -q -p \
		'read_verilog $<; synth; synth_prism -cfg $(CFG) -top $* -list output/$*.lst -tab output/$*.tab -cfile output/$*.c -py output/$*.py'

# Default target
all: init $(foreach c,$(CHROMAS),$(c).lst $(c).tab)

init:
	@mkdir -p output

clean:
	rm -f *.lst *.tab

yosys: yosys_fetch
	make -C $(YOSYS_DIR) -j8


yosys_fetch:
	@if [ ! -d $(YOSYS_DIR) ]; then \
	git clone --recursive https://github.com/kdp1965/yosys-prism $(YOSYS_DIR); fi

# vim: noet
