.PHONY: all phase1 phase2 phase3 phase4 clean \
	dma_burst_splitter dma_descriptor_fifo axi_read_dma \
	buffer_manager_fsm store_fsm store_row_buffer \
	compute_fsm wavefront_feeder systolic_array region_checker

SBY ?= sby

PHASE1_TARGETS := dma_burst_splitter dma_descriptor_fifo axi_read_dma
PHASE2_TARGETS := buffer_manager_fsm store_fsm store_row_buffer
PHASE3_TARGETS := compute_fsm wavefront_feeder systolic_array
PHASE4_TARGETS := region_checker

TARGETS := $(PHASE1_TARGETS) $(PHASE2_TARGETS) $(PHASE3_TARGETS) $(PHASE4_TARGETS)

all: $(TARGETS)

phase1: $(PHASE1_TARGETS)
phase2: $(PHASE2_TARGETS)
phase3: $(PHASE3_TARGETS)
phase4: $(PHASE4_TARGETS)

$(TARGETS):
	$(SBY) -f $@.sby

clean:
	rm -rf $(TARGETS)
