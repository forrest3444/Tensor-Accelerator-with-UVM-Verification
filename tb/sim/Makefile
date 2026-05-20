###############################################################################
# Project / Test Configuration
###############################################################################
TB_TOP    ?= top_tb
TESTNAME  ?= base_test
SEED      ?= 1
VERB      ?= UVM_MEDIUM
RUN_TIME  ?= 1s
BUILD_NAME ?= default
COV       ?= 0
FSDB      ?= 0
ASSERT    ?= 1
DEBUG     ?= 0

SIM       ?= sim
BUILD_DIR := $(SIM)/build/$(BUILD_NAME)
RUN_DIR   := $(SIM)/run/$(TESTNAME)_seed_$(SEED)
BUILD_LOG_DIR := $(BUILD_DIR)/log
RUN_LOG_DIR   := $(RUN_DIR)/log
WAVE_DIR      := $(RUN_DIR)/wave
COV_DIR       := $(RUN_DIR)/cov.vdb
SIMV_DIR      := $(BUILD_DIR)/simv
MERGED_COV_DIR ?= $(SIM)/merged_cov.vdb
MERGED_COV_REPORT_DIR ?= $(SIM)/merged_cov_report
REGRESSION_SCRIPT ?= ./run_regression.sh
REGRESSION_RUN_TIME ?= $(RUN_TIME)
SIMV_IMAGE := $(SIMV_DIR)/$(TB_TOP).simv
SIMV_VDB   := $(SIMV_DIR)/$(TB_TOP).simv.vdb

FILELIST  ?= ./filelist.f

###############################################################################
# SVT VIP / UVM Configuration
###############################################################################
VIP_ROOT ?= ../../../test_vip2018/test_vip2018
VIP_SRC_DIR := $(VIP_ROOT)/src
VIP_INC_DIR := $(VIP_ROOT)/include
SVT_AXI_PKG ?= $(VIP_INC_DIR)/sverilog/svt_axi.uvm.pkg

VCS_HOME ?= /home/wwh/vcs/vcs2018/vcs/O-2018.09-SP2
UVM_HOME ?= $(VCS_HOME)/etc/uvm-1.2

SVT_INC_DIRS = +incdir+$(VIP_SRC_DIR)/sverilog/vcs \
               +incdir+$(VIP_INC_DIR)/sverilog     \
               +incdir+$(VIP_SRC_DIR)/verilog/vcs   \
               +incdir+$(VIP_INC_DIR)/verilog

TB_INC_DIRS = +incdir+../..             \
              +incdir+../../rtl/common \
              +incdir+../cfg           \
              +incdir+../env           \
              +incdir+../seq_lib       \
              +incdir+../tests         \
              +incdir+../tb

UVM_OPTS = -CFLAGS -DVCS +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/dpi/uvm_dpi.cc

###############################################################################
# Tools
###############################################################################
VCS       ?= vcs
VERDI     ?= verdi
URG       ?= urg

###############################################################################
# Compile / Runtime Options
###############################################################################
TIMESCALE ?= 1ns/1ps

VCS_BASE_OPTS = -full64                 \
                -sverilog               \
                -timescale=$(TIMESCALE) \
                $(UVM_OPTS)             \
                +define+SVT_UVM_TECHNOLOGY \
                +define+SYNOPSYS_SV     \
                +define+UVM_PACKER_MAX_BYTES=1500000 \
                +define+UVM_DISABLE_AUTO_ITEM_RECORDING \
                -nc                     \
                $(SVT_INC_DIRS)         \
                $(TB_INC_DIRS)          \
                $(INC_DIR)

VCS_WAVE_OPTS  = -kdb                   \
                 -debug_access         \
                 -lca

VCS_DEBUG_OPTS = -debug_access+all

VCS_OPTS = $(VCS_BASE_OPTS)

###############################################################################
# Optional Feature Switches
###############################################################################
ifneq ($(ASSERT),0)
VCS_OPTS += +define+ASSERT_ON
endif

ifneq ($(DEBUG),0)
VCS_OPTS += $(VCS_DEBUG_OPTS) +define+DEBUG
endif

ifneq ($(FSDB),0)
VCS_OPTS += $(VCS_WAVE_OPTS)
endif

ifneq ($(COV),0)
VCS_OPTS += -cm line+cond+fsm+branch+tgl+assert
SIM_COV_OPTS = -cm line+cond+fsm+branch+tgl+assert -cm_dir $(COV_DIR)
endif

ifneq ($(FSDB),0)
SIM_WAVE_OPTS = +FSDB +FSDB_FILE=$(WAVE_DIR)/$(TESTNAME)_seed$(SEED).fsdb
endif

###############################################################################
# Runtime Options
###############################################################################
SIM_OPTS = +ntb_random_seed=$(SEED)  \
           +UVM_TESTNAME=$(TESTNAME) \
           +UVM_VERBOSITY=$(VERB)    \
           +validation_cfg_filename=env/axi_config.cfg \
           +vcs+watchdog+time=5ms

###############################################################################
# Targets
###############################################################################
.PHONY: all prepare_build prepare_run check_elab elab run sim regression verdi merge_cov \
        clean clean_all clean_build clean_run clean_cov clean_reports clean_misc help

all: sim

prepare_build:
	mkdir -p $(BUILD_LOG_DIR) $(SIMV_DIR)

prepare_run:
	mkdir -p $(RUN_LOG_DIR) $(WAVE_DIR) $(COV_DIR)

check_elab:
	@if [ ! -x "$(SIMV_IMAGE)" ]; then \
	  echo "Elaboration output not found: $(SIMV_IMAGE)"; \
	  echo "Run 'make elab BUILD_NAME=$(BUILD_NAME)' first."; \
	  exit 1; \
	fi

elab: prepare_build
	$(VCS) $(VCS_OPTS)                  \
	      $(SVT_AXI_PKG)                \
	      -f $(FILELIST)                \
	      $(VFILES)                     \
	      -top $(TB_TOP)                \
	      -o $(SIMV_IMAGE)              \
	      -l $(BUILD_LOG_DIR)/compile.log

run: check_elab prepare_run
	@echo "Running $(TESTNAME) with build '$(BUILD_NAME)'"
	timeout $(RUN_TIME) $(SIMV_IMAGE)   \
	      $(SIM_OPTS)                   \
	      $(SIM_COV_OPTS)               \
	      $(SIM_WAVE_OPTS)              \
	      -l $(RUN_LOG_DIR)/run.log

sim: elab run

regression:
	SEED=$(SEED)                     \
	RUN_TIME=$(REGRESSION_RUN_TIME) \
	VERB=$(VERB)                    \
	TB_TOP=$(TB_TOP)                \
	FILELIST=$(FILELIST)            \
	BUILD_NAME=$(BUILD_NAME)        \
	$(REGRESSION_SCRIPT)

verdi:
	$(VERDI) -sv                        \
	         $(SVT_AXI_PKG)             \
	         -f $(FILELIST)             \
	         $(VFILES)                  \
	         -top $(TB_TOP)             \
	         -ssf $(WAVE_DIR)/$(TESTNAME)_seed$(SEED).fsdb &

merge_cov:
	@if [ ! -d "$(SIMV_VDB)" ]; then \
	  echo "Design coverage database not found: $(SIMV_VDB)"; \
	  echo "Run 'make elab BUILD_NAME=$(BUILD_NAME)' first."; \
	  exit 1; \
	fi
	@mkdir -p "$(MERGED_COV_REPORT_DIR)"
	@test_cov_dirs=$$(find $(SIM)/run -maxdepth 2 -type d -name 'cov.vdb' | sort); \
	if [ -z "$$test_cov_dirs" ]; then \
	  echo "No test coverage databases found under $(SIM)/run"; \
	  exit 1; \
	fi; \
	urg_args="-dir $(SIMV_VDB)"; \
	for cov_dir in $$test_cov_dirs; do \
	  urg_args="$$urg_args -dir $$cov_dir"; \
	done; \
	echo "Merging coverage into $(MERGED_COV_DIR)"; \
	$(URG) $$urg_args -dbname $(MERGED_COV_DIR) -report $(MERGED_COV_REPORT_DIR)

clean: clean_run clean_cov clean_reports

clean_build:
	rm -rf $(SIM)/build csrc *.daidir vc_hdrs.h

clean_run:
	rm -rf $(SIM)/run

clean_cov:
	rm -rf $(MERGED_COV_DIR) $(MERGED_COV_REPORT_DIR)

clean_reports:
	rm -rf urgReport

clean_misc:
	rm -rf $(SIM)/DVEfiles $(SIM)/verdiLog $(SIM)/novas.* csrc *.daidir vc_hdrs.h ucli.key DVEfiles verdiLog novas* inter.vpd *.vpd *.fsdb *.vdb *.log

clean_all: clean clean_build clean_misc

help:
	@echo "Usage examples:"
	@echo "  make sim TESTNAME=base_test SEED=1"
	@echo "  make sim TESTNAME=base_test VIP_ROOT=../../../test_vip2018/test_vip2018"
	@echo "  make elab BUILD_NAME=regression"
	@echo "  make run TESTNAME=base_test SEED=1 BUILD_NAME=regression"
	@echo "  make regression BUILD_NAME=regression REGRESSION_RUN_TIME=10s"
	@echo "  make merge_cov MERGED_COV_DIR=sim/merged_cov.vdb"
	@echo "  make sim TESTNAME=base_test SEED=1 DEBUG=1"
	@echo ""
	@echo "Targets:"
	@echo "  elab         Compile and elaborate into sim/build/<BUILD_NAME>"
	@echo "  run          Run existing simv for TESTNAME after checking elab output"
	@echo "  sim/all      Build and run"
	@echo "  regression   Run the full regression suite via run_regression.sh"
	@echo "  verdi        Open waveform in Verdi"
	@echo "  merge_cov    Merge sim/run/*/cov.vdb using $(SIMV_VDB) into MERGED_COV_DIR and write HTML to MERGED_COV_REPORT_DIR"
	@echo "  clean        Remove run outputs, merged coverage, and reports"
	@echo "  clean_build  Remove shared build outputs"
	@echo "  clean_run    Remove per-test run directories"
	@echo "  clean_cov    Remove merged coverage output"
	@echo "  clean_reports Remove generated coverage reports"
	@echo "  clean_all    Remove all generated artifacts"
	@echo ""
	@echo "Defaults:"
	@echo "  COV=0 FSDB=0 ASSERT=1 DEBUG=0"
	@echo "  VIP_ROOT=$(VIP_ROOT)"
