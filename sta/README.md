# STA

Initial static timing analysis collateral for `mac_unit`.

Run:

```sh
make -C sta
```

Useful overrides:

```sh
make -C sta CLK_NS=4.0
make -C sta PATH_COUNT=200
make -C sta LIB=/path/to/pdk.lib
```

Run `axi_write_dma`:

```sh
make -C sta TOP=axi_write_dma RTL="../rtl/dma/dma_burst_splitter.sv ../rtl/dma/axi_write_dma.sv"
```

Run DMA modules into separated DMA output directories:

```sh
make -C sta TOP=dma_descriptor_fifo RTL="../rtl/common/fifo.sv rtl/dma_descriptor_fifo_sta.sv" BUILD_DIR=build/dma/dma_descriptor_fifo REPORT_DIR=reports/dma/dma_descriptor_fifo
make -C sta TOP=dma_burst_splitter RTL="../rtl/dma/dma_burst_splitter.sv" BUILD_DIR=build/dma/dma_burst_splitter REPORT_DIR=reports/dma/dma_burst_splitter
make -C sta TOP=axi_read_dma RTL="../rtl/dma/dma_burst_splitter.sv ../rtl/dma/axi_read_dma.sv" BUILD_DIR=build/dma/axi_read_dma REPORT_DIR=reports/dma/axi_read_dma
make -C sta TOP=tensor_loader RTL="../rtl/dma/dma_burst_splitter.sv ../rtl/dma/axi_read_dma.sv ../rtl/dma/tensor_loader.sv" BUILD_DIR=build/dma/tensor_loader REPORT_DIR=reports/dma/tensor_loader
make -C sta TOP=tensor_writer RTL="../rtl/dma/dma_burst_splitter.sv ../rtl/dma/axi_write_dma.sv ../rtl/dma/tensor_writer.sv" BUILD_DIR=build/dma/tensor_writer REPORT_DIR=reports/dma/tensor_writer
```

Run bus modules into separated bus output directories:

```sh
make -C sta TOP=reg_file RTL="rtl/reg_file_sta.sv" BUILD_DIR=build/bus/reg_file REPORT_DIR=reports/bus/reg_file
make -C sta TOP=axi_lite_slave RTL="../rtl/bus/axi_lite_slave.sv" BUILD_DIR=build/bus/axi_lite_slave REPORT_DIR=reports/bus/axi_lite_slave
```

Run common modules into separated common output directories:

```sh
make -C sta TOP=fifo RTL="../rtl/common/fifo.sv" BUILD_DIR=build/common/fifo REPORT_DIR=reports/common/fifo
make -C sta TOP=mac_unit RTL="../rtl/common/mac_unit.sv" BUILD_DIR=build/common/mac_unit REPORT_DIR=reports/common/mac_unit
make -C sta TOP=saturate RTL="../rtl/common/saturate.sv" BUILD_DIR=build/common/saturate REPORT_DIR=reports/common/saturate
```

Run compute modules into separated compute output directories:

```sh
make -C sta TOP=accumulator RTL="rtl/accumulator_sta.sv" BUILD_DIR=build/compute/accumulator REPORT_DIR=reports/compute/accumulator
make -C sta TOP=pe RTL="../rtl/common/mac_unit.sv ../rtl/compute/pe.sv" BUILD_DIR=build/compute/pe REPORT_DIR=reports/compute/pe
make -C sta TOP=post_process RTL="../rtl/common/saturate.sv rtl/post_process_sta.sv" BUILD_DIR=build/compute/post_process REPORT_DIR=reports/compute/post_process
make -C sta TOP=systolic_array RTL="../rtl/common/mac_unit.sv ../rtl/compute/pe.sv rtl/systolic_array_sta.sv" BUILD_DIR=build/compute/systolic_array REPORT_DIR=reports/compute/systolic_array
```

Run control modules into separated control output directories:

```sh
make -C sta TOP=command_fsm RTL="rtl/command_fsm_sta.sv" BUILD_DIR=build/control/command_fsm REPORT_DIR=reports/control/command_fsm
make -C sta TOP=load_scheduler RTL="rtl/load_scheduler_sta.sv" BUILD_DIR=build/control/load_scheduler REPORT_DIR=reports/control/load_scheduler
make -C sta TOP=tile_scheduler RTL="rtl/tile_scheduler_sta.sv" BUILD_DIR=build/control/tile_scheduler REPORT_DIR=reports/control/tile_scheduler
```

The default library is the Nangate45 typical Liberty file from:

```text
/home/wwh/OpenROAD-flow-scripts/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib
```
