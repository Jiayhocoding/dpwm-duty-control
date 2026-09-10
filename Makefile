IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
GTKWAVE ?= gtkwave

.PHONY: test test-or test-and lint wave-or wave-and

test: test-or test-and

test-or: build/or.sim
	$(VVP) $<

test-and: build/and_reduce.sim
	$(VVP) $<

build:
	mkdir -p $@

build/or.sim: DPWM_modu_test.sv testbench.sv | build
	$(IVERILOG) -g2012 -s tb -o $@ $^

build/and_reduce.sim: DPWM_modu_test.sv testbench_and_reduce.sv | build
	$(IVERILOG) -g2012 -s tb_and_reduce -o $@ $^

lint:
	$(VERILATOR) --lint-only --top-module DPWM_modu_test -Wall -Wno-DECLFILENAME DPWM_modu_test.sv

wave-or: test-or
	$(GTKWAVE) wave.vcd wave_or.gtkw

wave-and: test-and
	$(GTKWAVE) wave_and_reduce.vcd wave_and_reduce.gtkw
