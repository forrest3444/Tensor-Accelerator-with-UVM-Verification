SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

TOP      ?= mac_unit
CLK_NS   ?= 4.0
RTL      ?= ../rtl/common/mac_unit.sv
SDC      ?= constraints/$(TOP).sdc
LIB      ?= /home/wwh/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
ABC_OPTS ?= -fast
PATH_COUNT ?= 100

BUILD_DIR  := build/$(TOP)
REPORT_DIR := reports/$(TOP)
NETLIST    := $(BUILD_DIR)/$(TOP).gate.v

.PHONY: all synth sta clean

all: sta

synth:
	mkdir -p $(BUILD_DIR) $(REPORT_DIR)
	yosys -q -l $(REPORT_DIR)/yosys.log \
	      -p "read_verilog -sv $(RTL)" \
	      -p "hierarchy -check -top $(TOP)" \
	      -p "script scripts/synth_mac_unit.ys" \
	      -p "dfflibmap -liberty $(LIB)" \
	      -p "abc $(ABC_OPTS) -liberty $(LIB)" \
	      -p "clean" \
	      -p "stat -liberty $(LIB)" \
	      -p "write_verilog -noattr -noexpr -nohex -nodec -simple-lhs $(NETLIST)"

sta: synth
	TOP=$(TOP) CLK_NS=$(CLK_NS) LIB=$(LIB) NETLIST=$(NETLIST) REPORT_DIR=$(REPORT_DIR) SDC=$(SDC) PATH_COUNT=$(PATH_COUNT) \
	    sta -no_splash -exit scripts/run_sta.tcl \
	    | tee $(REPORT_DIR)/opensta.log

clean:
	rm -rf build reports
