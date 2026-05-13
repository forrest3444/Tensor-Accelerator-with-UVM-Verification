# =========================================================
# Design RTL
# =========================================================
../../rtl/common/tensor_pkg.sv
../../rtl/common/fifo.sv
../../rtl/common/saturate.sv
../../rtl/common/mac_unit.sv

../../rtl/bus/reg_file.sv
../../rtl/bus/axi_lite_slave.sv

../../rtl/control/load_scheduler.sv
../../rtl/control/tile_scheduler.sv
../../rtl/control/command_fsm.sv

../../rtl/dma/dma_descriptor_fifo.sv
../../rtl/dma/dma_burst_splitter.sv
../../rtl/dma/axi_write_dma.sv
../../rtl/dma/tensor_writer.sv
../../rtl/dma/axi_read_dma.sv
../../rtl/dma/tensor_loader.sv

../../rtl/memory/region_checker.sv
../../rtl/memory/scratchpad.sv
../../rtl/memory/scratchpad_ctrl.sv

../../rtl/compute/accumulator.sv
../../rtl/compute/pe.sv
../../rtl/compute/systolic_array.sv
../../rtl/compute/post_process.sv

../../rtl/top/tensor_accel_top.sv

# =========================================================
# Verification Environment
# =========================================================
../tb/tensor_accel_dut_if.sv
../cfg/tensor_accel_tb_cfg_pkg.sv
../env/tensor_accel_env_pkg.sv
../seq_lib/tensor_accel_seq_lib_pkg.sv

# =========================================================
# TB Top
# =========================================================
../tb/top_tb.sv
