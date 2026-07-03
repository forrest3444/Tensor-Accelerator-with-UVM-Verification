# =========================================================
# Design RTL
# =========================================================
rtl/common/tensor_pkg.sv
rtl/common/fifo.sv
rtl/common/saturate.sv
rtl/common/mac_unit.sv

rtl/bus/reg_file.sv
rtl/bus/axi_lite_slave.sv

rtl/control/command_fsm.sv
rtl/control/load_scheduler.sv
rtl/control/tile_count_fsm.sv
rtl/control/buffer_manager_fsm.sv
rtl/control/compute_fsm.sv
rtl/control/post_process_fsm.sv
rtl/control/store_fsm.sv

rtl/dma/dma_descriptor_fifo.sv
rtl/dma/dma_burst_splitter.sv
rtl/dma/axi_write_dma.sv
rtl/dma/tensor_writer.sv
rtl/dma/axi_read_dma.sv
rtl/dma/tensor_loader.sv

rtl/memory/region_checker.sv
rtl/memory/scratchpad.sv
rtl/memory/scratchpad_ctrl.sv
rtl/memory/store_row_buffer.sv
rtl/memory/c_store_coalescer.sv

rtl/compute/accumulator.sv
rtl/compute/pe.sv
rtl/compute/wavefront_feeder.sv
rtl/compute/systolic_array.sv
rtl/compute/post_process.sv

rtl/top/tensor_accel_top.sv

# =========================================================
# Verification Environment
# =========================================================
+incdir+tb
+incdir+tb/cfg
+incdir+tb/env
+incdir+tb/seq_lib
+incdir+tb/reg_model
+incdir+tb/tests

tb/tb/tensor_accel_dut_if.sv
tb/cfg/tensor_accel_tb_cfg_pkg.sv
tb/reg_model/tensor_accel_reg_pkg.sv
tb/env/tensor_accel_env_pkg.sv
tb/tb/tensor_accel_uvm_pkg.sv

# =========================================================
# TB Top
# =========================================================
tb/tb/top_tb.sv
