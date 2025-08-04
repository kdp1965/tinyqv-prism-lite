# Makefile for building PRISM Chroma personalities

TOPDIR = $(shell pwd)
YOSYS := ../../yosys-prism/yosys
CFG := $(TOPDIR)/tinyqv.cfg

CHROMAS := $(basename $(notdir $(wildcard chroma*.v)))
$(info $(CHROMAS))

# Pattern rule to build .lst and .tab from .v
%.lst %.tab: %.v
	@echo "Building Chroma: $*"
	$(YOSYS) -q -p \
		'read_verilog $<; synth; synth_prism -cfg $(CFG) -top $* -list output/$*.lst -tab output/$*.tab -cfile output/$*.c'

# Default target
all: init $(foreach c,$(CHROMAS),$(c).lst $(c).tab)

init:
	@mkdir -p output

clean:
	rm -f *.lst *.tab
