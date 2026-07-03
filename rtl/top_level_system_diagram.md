# Tensor Accelerator Top-Level System Diagram

This document tracks the RTL module-level architecture and the expected change
points for a classic 2D systolic-array dataflow migration.

Current migration status:

```text
- wavefront_feeder is introduced as the compute boundary injector.
- systolic_array uses left-to-right A propagation and top-to-bottom B propagation.
- compute_fsm extends valid/done timing for fill/drain cycles.
- Load, store, software-visible registers, and external matrix contracts remain
  unchanged.
```

Legend:

```text
[KEEP] Basic structure is expected to remain unchanged
[MOD]  Module or interface needs modification
[NEW]  New module or boundary is expected
[RISK] High-risk timing, protocol, or validation point
```

## Plane View

```text
============================================================
Register / Software Plane
============================================================

External AXI-Lite
  -> [KEEP] axi_lite_slave
  -> [KEEP] reg_file
  -> [KEEP] cfg / status / irq

Notes:
  - No new software-visible mode is required for classic output-stationary
    2D systolic dataflow.
  - External A/B/C matrix contracts should remain unchanged.
  - start/done/irq software protocol should remain unchanged.


============================================================
Command / Tile Control Plane
============================================================

[KEEP] command_fsm
  -> [KEEP] tile_count_fsm
  -> [KEEP] buffer_manager_fsm
  -> [KEEP] load_scheduler
  -> [MOD][RISK] compute_fsm
  -> [KEEP] post_process_fsm
  -> [KEEP] store_fsm

2D systolic change points:
  - compute_fsm can no longer model compute as only K cycles plus a small fixed
    pipe latency.
  - compute needs fill / steady / drain timing.
  - compute_done must wait until the last valid PE accumulation is complete.
  - compute_valid should describe boundary injection activity, not all-PE MAC
    validity.
  - clear / launch / done alignment is high risk because a new tile must not
    clear data that is still draining through the array.


============================================================
Load / Staging Data Plane
============================================================

External AXI Read
  -> [KEEP] read desc fifo
  -> [KEEP] tensor_loader / axi_read_dma
  -> [KEEP] scratchpad_ctrl / scratchpad
  -> [MOD] panel register read path

Current staged data shape:
  - A panel: a_panel_q[buffer][m][k]
  - B panel: b_panel_q[k][n]
  - Bias:    bias_vec_q[n]

2D systolic change points:
  - The stored panel shape can remain unchanged.
  - The panel read schedule must change from global K broadcast to skewed
    boundary injection.
  - A is injected from the left boundary and then propagates right.
  - B is injected from the top boundary and then propagates down.
  - No additional scratchpad region should be required.


============================================================
Compute Plane
============================================================

[MOD] panel registers
  -> [NEW] wavefront_feeder
  -> [MOD][RISK] systolic_array
  -> [MOD] pe
  -> [MOD] accumulator load timing
  -> [KEEP] post_process

2D systolic change points:
  - Add a wavefront_feeder module instead of placing skew formulas directly in
    tensor_accel_top.
  - systolic_array changes from row/column broadcast to nearest-neighbor data
    propagation.
  - PE adds A/B pass-through registers and valid propagation.
  - MAC enable should be generated from aligned A-valid, B-valid, row-valid,
    and col-valid.
  - accumulator interface may remain tile-based, but load_i must align with
    the new array completion point.
  - post_process can remain unchanged if accumulator still presents a complete
    C tile.

High-risk validation areas:
  - Partial tiles and degenerate dimensions
  - INT8 / INT16 K indexing
  - overflow qualification during bubble cycles
  - soft reset and compute clear behavior
  - bias / relu / saturation timing relative to accumulator load


============================================================
Store / Writeback Data Plane
============================================================

[KEEP] post_process
  -> [KEEP] store_row_buffer
  -> [KEEP] store_fsm
  -> [KEEP] write desc fifo
  -> [KEEP] tensor_writer / axi_write_dma
  -> External AXI Write

Notes:
  - Classic 2D systolic keeps output-stationary C tile semantics.
  - C external raw-major layout should remain unchanged.
  - Existing row-based writeback and write descriptor FIFO can remain unchanged.
  - post_process_start timing must follow the modified compute_done timing.
```

## Module-Level Topology

```text
                         +----------------------+
                         | External AXI-Lite    |
                         +----------+-----------+
                                    |
                                    v
                         +----------------------+
                         | [KEEP] axi_lite_slave|
                         +----------+-----------+
                                    |
                                    v
                         +----------------------+
                         | [KEEP] reg_file      |
                         | cfg/status/irq       |
                         +----------+-----------+
                                    |
                                    v
+-----------------------------------------------------------------------+
|                         tensor_accel_top                              |
|                                                                       |
|  Register / Command Control                                           |
|  +-------------------+      +-------------------+                     |
|  | [KEEP]            |----->| [KEEP]            |                     |
|  | command_fsm       |      | tile_count_fsm    |                     |
|  +---------+---------+      +---------+---------+                     |
|            |                          |                               |
|            v                          v                               |
|  +-------------------+      +-------------------+                     |
|  | [KEEP]            |<---->| [KEEP]            |                     |
|  | buffer_manager_fsm|      | load_scheduler    |                     |
|  +---------+---------+      +---------+---------+                     |
|            |                          |                               |
|            |                          v                               |
|            |               +-------------------+                      |
|            |               | [KEEP]            |                      |
|            |               | read desc fifo    |                      |
|            |               +---------+---------+                      |
|            |                         |                                |
|            |                         v                                |
|            |               +-------------------+      AXI Read        |
|            |               | [KEEP]            |<-------------------> |
|            |               | tensor_loader     |                      |
|            |               | axi_read_dma      |                      |
|            |               +---------+---------+                      |
|            |                         |                                |
|            |                         v                                |
|            |               +-------------------+                      |
|            |               | [KEEP]            |                      |
|            |               | scratchpad_ctrl   |                      |
|            |               +---------+---------+                      |
|            |                         |                                |
|            |                         v                                |
|            |               +-------------------+                      |
|            |               | [KEEP]            |                      |
|            |               | scratchpad        |                      |
|            |               +---------+---------+                      |
|            |                         |                                |
|            v                         v                                |
|  +-------------------+      +-------------------+                     |
|  | [MOD][RISK]       |----->| [MOD]             |                     |
|  | compute_fsm       |      | panel registers   |                     |
|  +---------+---------+      | a_panel/b_panel   |                     |
|            |                +---------+---------+                     |
|            |                          |                               |
|            |                          v                               |
|            |                +-------------------+                     |
|            +--------------->| [NEW]             |                     |
|                             | wavefront_feeder  |                     |
|                             +---------+---------+                     |
|                                       |                               |
|                                       v                               |
|                  +--------------------------------------+             |
|                  | [MOD][RISK] systolic_array           |             |
|                  | A: left -> right                     |             |
|                  | B: top  -> down                      |             |
|                  | C: local PE accumulation             |             |
|                  +------------------+-------------------+             |
|                                     |                                 |
|                                     v                                 |
|                  +-------------------+                                |
|                  | [MOD]             |                                |
|                  | accumulator       |                                |
|                  | load timing       |                                |
|                  +---------+---------+                                |
|                            |                                          |
|                            v                                          |
|                  +-------------------+                                |
|                  | [KEEP]            |                                |
|                  | post_process      |                                |
|                  +---------+---------+                                |
|                            |                                          |
|                            v                                          |
|                  +-------------------+                                |
|                  | [KEEP]            |                                |
|                  | store_row_buffer  |                                |
|                  +---------+---------+                                |
|                            |                                          |
|                            v                                          |
|                  +-------------------+                                |
|                  | [KEEP]            |                                |
|                  | store_fsm         |                                |
|                  +---------+---------+                                |
|                            |                                          |
|                            v                                          |
|                  +-------------------+                                |
|                  | [KEEP]            |                                |
|                  | write desc fifo   |                                |
|                  +---------+---------+                                |
|                            |                                          |
|                            v                                          |
|                  +-------------------+       AXI Write                |
|                  | [KEEP]            |<-----------------------------> |
|                  | tensor_writer     |                                |
|                  | axi_write_dma     |                                |
|                  +-------------------+                                |
|                                                                       |
+-----------------------------------------------------------------------+
```

## Current Versus Classic 2D Systolic Compute Path

Current compute path:

```text
compute_fsm
  -> a_panel_q[m][k] / b_panel_q[k][n]
  -> a_vec[m] and b_vec[n] broadcast
  -> systolic_array PE[m][n]
  -> accumulator
  -> post_process
```

Classic 2D systolic compute path:

```text
compute_fsm [MOD]
  -> wavefront_feeder [NEW]
  -> left_a_in[m] / top_b_in[n]
  -> systolic_array [MOD]
       A propagates left-to-right
       B propagates top-to-bottom
       PE[m][n] locally accumulates C[m][n]
  -> accumulator [MOD timing only]
  -> post_process [KEEP]
```

## Expected RTL File Impact

```text
Expected new file:
  - rtl/compute/wavefront_feeder.sv

Expected modified files:
  - rtl/control/compute_fsm.sv
  - rtl/compute/systolic_array.sv
  - rtl/compute/pe.sv
  - rtl/top/tensor_accel_top.sv

Likely timing-only or integration impact:
  - rtl/compute/accumulator.sv
  - rtl/compute/post_process.sv

Expected unchanged core behavior:
  - rtl/bus/axi_lite_slave.sv
  - rtl/bus/reg_file.sv
  - rtl/control/command_fsm.sv
  - rtl/control/tile_count_fsm.sv
  - rtl/control/buffer_manager_fsm.sv
  - rtl/control/load_scheduler.sv
  - rtl/control/store_fsm.sv
  - rtl/dma/tensor_loader.sv
  - rtl/dma/tensor_writer.sv
  - rtl/dma/axi_read_dma.sv
  - rtl/dma/axi_write_dma.sv
  - rtl/memory/scratchpad.sv
  - rtl/memory/scratchpad_ctrl.sv
  - rtl/memory/store_row_buffer.sv
```
