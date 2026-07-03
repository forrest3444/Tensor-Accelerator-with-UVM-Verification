**English** | [中文](SPEC_CN.md)

# Tensor Accelerator IP Specification

## 1. Module Overview

### Module Name

`tensor_accel_top`

### Purpose

`tensor_accel_top` is a lightweight integer matrix-multiply accelerator IP. Software programs matrix dimensions, external matrix base addresses, precision, and post-processing mode through AXI-Lite. The hardware uses AXI4 master DMA to load A/B/Bias from external memory, performs tiled GEMM, post-processes the result, and writes the C matrix back.

### Role in System

This IP is a system-level compute peripheral containing:

* AXI-Lite configuration registers
* AXI4 read/write DMA
* Fixed internal scratchpad address planning
* Tile counting and buffer management
* Load/compute/post-process/store control path
* 4x4 systolic array compute core
* Status, error, and interrupt reporting

---

## 2. Requirement Source

### User-Provided Requirements

* Support INT4/INT8/INT16 matrix multiplication with maximum matrix dimension 64.
* Use a tiled dataflow while preserving the external row-major C matrix contract.
* B is pre-transposed by software and loaded as reusable B stripes.
* SPAD base addresses and sizes are fixed internally and are not exposed as software offset/size registers.
* A uses ping-pong buffering. B stripes are reused and do not need two B banks.
* Store supports multi-row writeback and uses a fixed `C_STORE_NBLOCK=2` C store coalescer to merge adjacent N tiles before writing external row-major C.
* Read DMA has a descriptor FIFO and parameterized 4KB automatic split support.
* Performance counter logic is not kept in the synthesizable main path at this stage.
* Key safety properties should be suitable for formal verification.

### Agent-Inferred Requirements

| ID | Inferred decision | Reason |
| -- | ----------------- | ------ |
| 1 | Software provides external matrix base addresses only and does not manage internal SPAD layout | `reg_file` exposes no SPAD offset/size registers; `buffer_manager_fsm` fixes A/B/Bias windows |
| 2 | External C remains row-major | `tensor_writer` row mode uses `cfg_active.n_size * OUT_BYTES` as external row stride |
| 3 | External B is not original row-major B. It is software pre-transposed/pre-packed as stripes | `load_scheduler` uses `b_base + col_base * align8(packed_row_bytes(K, precision))` |
| 4 | Read 4KB auto split is not enabled by default at the top level | `tensor_accel_top.READ_AUTO_SPLIT_4KB` defaults to `1'b0` |
| 5 | Write DMA still reports 4KB crossing as an error | `command_fsm` enters error on `write_cross_4kb_i` |

### Open Questions

| ID | Question | Impact | Current default |
| -- | -------- | ------ | --------------- |
| Q1 | Should top-level `READ_AUTO_SPLIT_4KB` default to 1 | Affects software constraints and error-code semantics | Current RTL: default 0, parameter can enable it |
| Q2 | Should the software pre-transposed B format be frozen as ABI | Affects driver, tests, and integration | Current RTL: pre-transposed/pre-packed B is required |
| Q3 | Should write DMA also support 4KB automatic split | Affects robust C writeback for larger matrices | Current RTL: unsupported, crossing is an error |
| Q4 | Whether K tiling iteration is supported | Current compute uses full K and does not perform K-tile partial accumulation | Current RTL: unsupported; K is computed in one pass, 1..64 |

---

## 3. Scope

### Supported Features

* AXI-Lite slave configuration and status access.
* AXI4 master read/write with 64-bit data and 32-bit address.
* `M/N/K` range 1..64.
* Signed INT4, INT8, and INT16 inputs.
* 40-bit systolic accumulator and INT32 post-processed output.
* Bias, ReLU, and saturation/wrap modes.
* A ping-pong buffer, single reusable B bank, and fixed Bias window.
* Read descriptor FIFO and write descriptor FIFO.
* Parameterized read DMA 4KB split.
* C store coalescer for caching post-processed C rows and triggering wider row-mode writeback at the end of an N-block or at the matrix N tail.
* done/error/irq/overflow status reporting.

### Unsupported Features

* FP16/BF16/FP32.
* Sparse matrices.
* Cache coherency.
* Multiple AXI IDs or out-of-order responses.
* Software-configurable SPAD region offset/size.
* Software-submitted descriptor queues.
* External tile-major C layout.
* Write DMA 4KB automatic split.

### Explicit Non-Goals

* No training path, gradient, or weight update.
* No general-purpose matrix format conversion engine.
* No claim of peak throughput in this revision.
* No synthesizable performance-counter main path.

---

## 4. Parameters

| Parameter | Default | Legal range | Description |
| --------- | ------: | ----------- | ----------- |
| `TILE_M` | `ARRAY_M=4` | Recommended `>=1`, current verification focuses on 4 | Tile rows and array rows |
| `TILE_N` | `ARRAY_N=4` | Recommended `>=1`, current verification focuses on 4 | Tile columns and array columns |
| `OUT_BYTES` | 4 | Currently fixed at 4 | C output element bytes, INT32 |
| `BIAS_BYTES` | 4 | Currently fixed at 4 | Bias element bytes, INT32 |
| `COMPUTE_PIPE_LATENCY` | 3 | `>=0` | Compute FSM drain latency |
| `MAX_BURST_BEATS` | 16 | 1..256 | Maximum AXI beats per burst |
| `READ_DESC_FIFO_DEPTH` | 4 | `>=1` | Read descriptor FIFO depth |
| `WRITE_DESC_FIFO_DEPTH` | 2 | `>=1` | Write descriptor FIFO depth |
| `C_STORE_NBLOCK` | 2 | Currently verified as fixed 2 | Number of adjacent N tiles coalesced on the C store side; not exposed through registers |
| `SPAD_BUFFER_BYTES` | 1024 | Must fit the largest A/B/Bias tile | Fixed SPAD window size |
| `READ_AUTO_SPLIT_4KB` | `1'b0` | 0/1 | Enables read DMA automatic 4KB boundary splitting |

Related package defaults:

| Constant | Default | Description |
| -------- | ------: | ----------- |
| `AXIL_ADDR_WIDTH` | 16 | AXI-Lite address width |
| `AXIL_DATA_WIDTH` | 32 | AXI-Lite data width |
| `AXI_ADDR_WIDTH` | 32 | AXI master address width |
| `AXI_DATA_WIDTH` | 64 | AXI master data width |
| `SPAD_ADDR_WIDTH` | 16 | Scratchpad address width |
| `SPAD_DATA_WIDTH` | 32 | Scratchpad data width |
| `SPAD_BYTES` | 64 KiB | Package address-space limit; the top level currently instantiates `4 * SPAD_BUFFER_BYTES` |
| `MAX_DIM` | 64 | Maximum matrix dimension |

### Parameter Notes

* `TILE_M/TILE_N` affect array ports, the C store coalescer, store FSM, buffer manager, and verification scale.
* `SPAD_BUFFER_BYTES` must keep fixed windows non-overlapping and large enough for the maximum tile. The default 1024B is 2x the 512B theoretical A/B tile upper bound for the current 4x4 array and `MAX_DIM=64`. RTL contains `ASSERT_ON` static assertions for this.
* With `C_STORE_NBLOCK=2`, the store side may combine up to two adjacent N tiles under the same M tile into one row-mode descriptor. This parameter is not software-configurable in the current RTL.
* With `READ_AUTO_SPLIT_4KB=1`, the read burst splitter truncates a crossing read to the 4KB boundary and subsequent bursts continue the remaining bytes.
* The write path has no corresponding auto-split parameter.

---

## 5. Clock and Reset

| Signal | Direction | Description |
| ------ | --------: | ----------- |
| `clk` | input | Single main clock |
| `rst_n` | input | Active-low asynchronous reset |

### Reset Requirements

After reset:

* AXI-Lite and AXI master valid outputs are safe.
* Command FSM returns to idle.
* status, error, irq, and overflow count are cleared.
* Descriptor FIFOs are empty.
* Buffer states are free.
* Compute/post/store state is cleared.
* Internal A/B/Bias panels and the C store coalescer are ready for a new command.

### Reset Assumptions

* All RTL is in one clock domain.
* `rst_n` may be asserted during an active operation and should return the IP to a safe idle state.
* Software may use `CTRL.soft_reset` to synchronously clear the current task context.

---

## 6. Interface Contract

### Top-Level Port Summary

| Group | Direction | Width | Description |
| ----- | --------: | ----: | ----------- |
| `s_axil_aw*`, `s_axil_w*`, `s_axil_b*`, `s_axil_ar*`, `s_axil_r*` | mixed | AXI-Lite 32-bit data, 16-bit addr | Software configuration and status |
| `m_axi_ar*`, `m_axi_r*` | mixed | AXI4 read, 64-bit data | External A/B/Bias reads |
| `m_axi_aw*`, `m_axi_w*`, `m_axi_b*` | mixed | AXI4 write, 64-bit data | External C writeback |
| `irq` | output | 1 | Completion or error interrupt |

Simulation/verification builds expose additional `ifndef SYNTHESIS` ports: `tb_cmd_force_start_i`, `tb_cmd_force_read_error_i`, `tb_cmd_force_write_error_i`, and `tb_cmd_force_load_done_i`. They are directed error-arc injection hooks and are not part of the synthesizable interface contract.

### Interface Groups

* Configuration interface: AXI-Lite slave.
* Read data interface: AXI4 read master, fixed `ARID=0`, `ARBURST=INCR`.
* Write data interface: AXI4 write master, fixed `AWID=0`, `AWBURST=INCR`.
* Internal storage interface: 32-bit scratchpad, not exposed at top level.
* Interrupt interface: `irq` is a level-style status output cleared by `IRQ_STATUS` or `CTRL` clear bits.

### Interface Rules

* AXI-Lite writes are registered for one cycle before updating configuration or generating pulses.
* AXI-Lite reads return registered data one cycle after decode.
* AXI master uses no multiple IDs and does not support out-of-order completion.
* Burst size is fixed to 64-bit beats.
* External base alignment is checked by `region_checker`:
  * `A_BASE`, `B_BASE`, and enabled `BIAS_BASE` must be 8-byte aligned.
  * `C_BASE` must be 4-byte aligned.
* Read/write DMA errors are latched into the command FSM error state.

---

## 7. Handshake and Flow Control

### Transfer Rule

AXI transfers follow standard valid/ready:

```systemverilog
transfer = valid && ready;
```

Internal descriptor FIFO:

```systemverilog
push_accept = push_i && !full_o;
pop_accept  = pop_i  && !empty_o;
```

### Input Flow Control

* `load_scheduler` emits load descriptors only when the read descriptor FIFO is ready.
* `store_fsm` emits store descriptors only when the write descriptor FIFO is ready and row-ready conditions are satisfied.
* `tensor_loader` and `tensor_writer` are sequenced through `busy/done/error`.

### Output Flow Control

* Read DMA accepts R beats when `m_axi_rready` is high and its internal read buffer is not full.
* Write DMA advances W beats when `m_axi_wready` is high.
* The C store coalescer caches each post-processed row into the corresponding N-block slot, and the writer reads the coalesced contiguous C block row by row.

### Combinational Dependency Policy

| Path | Allowed | Reason |
| ---- | ------- | ------ |
| Downstream ready -> upstream valid | Partially | AXI and descriptor issue paths gate valid with ready. This is a timing point |
| Downstream ready -> upstream ready | Yes | Standard backpressure propagation |
| Input valid -> input ready | Not a system-level requirement | Mainly determined by AXI slave/DMA submodules |

---

## 8. Functional Behavior

### High-Level Behavior

1. Software writes configuration registers: `M/N/K`, precision, post-op, sat-mode, external A/B/C/Bias base, and DMA burst length.
2. Software writes `CTRL.start=1`.
3. `region_checker` checks matrix size, precision, and base address alignment.
4. `command_fsm` initializes tile counters.
5. `load_scheduler` emits A/B/Bias read descriptors.
6. The read descriptor FIFO drives `tensor_loader`, which DMA-loads external data and writes internal scratchpad/panels.
7. `compute_fsm` starts the wavefront feeder and systolic array.
8. The accumulator captures array results.
9. Post-processing applies bias, ReLU, and saturation/wrap.
10. The C store coalescer receives C tile rows and stores them by M tile and N-block slot.
11. `store_fsm` and `tensor_writer` use row-mode multi-row writes at an N-block end or matrix N tail to place the coalesced C block into external row-major C.
12. When all tiles complete, the IP enters done and optionally asserts irq.

### Cycle-Level Behavior

| Event | Condition | Behavior |
| ----- | --------- | -------- |
| start accepted | `start_pulse && idle && !done && !error` | Latch `cfg` into `cfg_active` |
| start while non-idle | `start_i && state != ST_IDLE` | Enter error, `ERR_COMMAND_WHILE_BUSY` |
| invalid config | `ST_CHECK_CONFIG && !cfg_valid` | Enter error and record checker error |
| load descriptor push | `load_a_start/load_b_start/load_bias_start` | Push read descriptor FIFO |
| read DMA done | One descriptor completed | Loader emits done and scheduler updates pending count |
| compute launch | command emits `compute_start` | Clear systolic array and latch tile metadata |
| post row done | post-process FSM completes one row | C store coalescer writes the corresponding M tile/N-block slot, and store FSM marks the row ready |
| store descriptor push | Required N-block rows are available and the write descriptor FIFO is ready | Push write descriptor FIFO |
| final done | Last tile store completes | Set status.done |

### State and Data Update Rules

* `cfg_active` is latched only when a valid start is accepted.
* Tile counters update on `sched_init/sched_advance`.
* A panel has two banks selected by `buffer_manager_fsm` using `tile_m/tile_n/tile_m_count` for ping-ponging.
* B panel has one bank and is reloaded at `tile_m==0`, then reused across the M direction.
* Bias is loaded only when bias is enabled and `tile_m==0`.
* C is not persisted in scratchpad. Post-process results enter the C store coalescer.
* `compute_tile_m/tile_n/col_base/C offset/tile shape` are latched at compute launch and used by post/store, so later tile-counter advances do not corrupt the active writeback context.

---

## 9. Latency, Throughput, and Ordering

### Latency

* Latency is variable and depends on matrix size, AXI backpressure, burst length, and post/store progress.
* For one tile, `compute_fsm` valid time is related to `K + ARRAY_M + ARRAY_N + COMPUTE_PIPE_LATENCY`.
* `region_checker` output is registered relative to configuration input.

### Throughput

* Default array size is 4x4.
* Load and compute have partial pipelining: next tile load may be prefetched during current tile compute, constrained by buffer hazards and store state.
* Store may start row-mode writeback after post-processing produces rows, without waiting for the whole task.
* With `C_STORE_NBLOCK=2`, the first N tile in a block is post-processed and cached without starting writeback. The second N tile, or the matrix N tail, triggers coalesced writeback with up to `2 * TILE_N * OUT_BYTES` bytes per row.
* B and Bias are reused across the M direction to reduce repeated loads.

### Ordering

* Tile order advances along M first, then to the next N stripe.
* N-block coalescing does not change the external row-major C contract; it only widens the contiguous column span covered by one row-mode descriptor.
* External C remains row-major.
* AXI transaction reordering is unsupported.
* Descriptor FIFOs preserve strict FIFO order.

---

## 10. State Machine and Control

### FSM Summary

| FSM | Purpose | Reset state |
| --- | ------- | ----------- |
| `command_fsm` | Top-level task phase, errors, and status | `ST_IDLE` |
| `tile_count_fsm` | tile_m/tile_n counting and row/col valid generation | 0 |
| `buffer_manager_fsm` | A ping-pong selection, fixed B/Bias windows, hazard checks | free |
| `load_scheduler` | A/B/Bias read descriptor generation and DMA drain wait | `LS_IDLE` |
| `compute_fsm` | systolic launch/valid/done timing | idle |
| `post_process_fsm` | post-process row-done marking | idle |
| `c_store_coalescer` | Cache post-processed C rows and coalesce adjacent N tile results for writer reads | zeroed after clear |
| `store_fsm` | row-ready store descriptor generation and active M tile context tracking | idle |
| `tensor_loader` | row-mode read DMA scheduling | idle |
| `tensor_writer` | row-mode write DMA scheduling | idle |
| `axi_read_dma` | AXI AR/R and SPAD writes | `S_IDLE` |
| `axi_write_dma` | AXI AW/W/B and SPAD reads | idle |

### command_fsm State List

| State | Meaning | Exit condition |
| ----- | ------- | -------------- |
| `ST_IDLE` | Wait for start | `start_i` |
| `ST_CHECK_CONFIG` | Check configuration | valid or error |
| `ST_PREPARE_TILE` | Initialize tile counters | next cycle |
| `ST_LOAD_TILE` | Load first tile | load done or error |
| `ST_COMPUTE_TILE` | Compute current tile and possibly prefetch | compute done or pipe load |
| `ST_PIPE_LOAD` | Load/compute overlap | both load and compute done |
| `ST_PIPE_WAIT_LOAD` | Compute is done, waiting for load | load done |
| `ST_PIPE_WAIT_COMPUTE` | Load is done, waiting for compute | compute done |
| `ST_POST_PROCESS_TILE` | Post-process and possibly start store | post/store conditions |
| `ST_WAIT_STORE_SLOT` | Wait for free store slot | store can start |
| `ST_STORE_TILE` | Wait for current store | write done |
| `ST_WAIT_FINAL_STORE` | Wait for final store | write done |
| `ST_DONE` | Task complete | clear done |
| `ST_ERROR` | Error latched | clear error |

### Illegal State Behavior

* Main FSMs return to idle in default branches.
* command FSM enters error on illegal/busy start, DMA error, 4KB crossing, or timeout.
* `compute_done_i` is qualified by `compute_issued_q` before it is treated as the current tile completion, preventing stale done from the previous tile from advancing the FSM.
* Tiles with `store_required_i=0` only run post-processing and coalescer writes; they do not start a write descriptor.
* Under `ASSERT_ON`, RTL checks FIFO overflow/underflow, store descriptor context, and fixed SPAD window overlap.

---

## 11. Data Format and Arithmetic

### Data Format

| Data | Format | Signed | Width | Notes |
| ---- | ------ | ------ | ----: | ----- |
| A INT4 | signed integer | Yes | 4 | Two elements are packed per byte. Even K uses the low nibble and is sign-extended to 16 |
| B INT4 | signed integer | Yes | 4 | Software pre-transposed stripe layout. Two K elements are packed per byte and sign-extended to 16 |
| A INT8 | signed integer | Yes | 8 | Extracted from 64-bit AXI beat and sign-extended to 16 |
| B INT8 | signed integer | Yes | 8 | Software pre-transposed layout and sign-extended to 16 |
| A/B INT16 | signed integer | Yes | 16 | Requires complete 2-byte lane strobe |
| MAC product | signed integer | Yes | 32 | Internal `mac_unit` multiply |
| accumulator | signed integer | Yes | 40 | systolic array output |
| Bias | signed integer | Yes | 32 | One bias per N column |
| C output | signed integer | Yes | 32 | row-major writeback |

### Arithmetic Rules

* INT4, INT8, and INT16 are processed as signed multiplication.
* MAC product is 32-bit signed. Accumulator is 40-bit signed.
* Post-processing order is bias, ReLU, then saturation/wrap.
* `SAT_WRAP` truncates to 32-bit output.
* `SAT_SATURATE` clamps to int32 range.
* Overflow sets `status.overflow_seen` and increments `OVF_COUNT`.

---

## 12. Storage and Buffering

| Storage | Type | Depth/capacity | Width | Purpose |
| ------- | ---- | -------------: | ----: | ------- |
| `scratchpad` | SRAM-like | default 4 KiB | 32 | Unified storage interface for DMA-loaded A/B/Bias |
| A panel bank 0/1 | Register array | `TILE_M * MAX_DIM` each | 16 | A ping-pong compute panel |
| B panel | Register array | `MAX_DIM * TILE_N` | 16 | Reused B stripe panel |
| Bias vector | Register array | `TILE_N` | 32 | Bias stripe |
| read descriptor FIFO | FIFO | default 4 | `dma_desc_t` 117 bits | A/B/Bias read descriptors |
| write descriptor FIFO | FIFO | default 2 | `dma_desc_t` 117 bits | C row-mode write descriptors |
| read DMA buffer | FIFO | 2 | 65 | R channel buffering |
| C store coalescer | M-tile indexed row buffer | `MTILE_SLOTS * TILE_M * TILE_N * C_STORE_NBLOCK` | 32 | Coalesces C rows for adjacent N tiles under the same M tile |

### Fixed SPAD Address Plan

| Window | Base | Size | Purpose |
| ------ | ---- | ---- | ------- |
| A bank 0 | `0x0000` | `SPAD_BUFFER_BYTES` | A tile buffer 0 |
| A bank 1 | `SPAD_BUFFER_BYTES`, default `0x0400` | `SPAD_BUFFER_BYTES` | A tile buffer 1 |
| B bank | `2 * SPAD_BUFFER_BYTES`, default `0x0800` | `SPAD_BUFFER_BYTES` | B stripe buffer |
| Bias bank | `3 * SPAD_BUFFER_BYTES`, default `0x0c00` | `SPAD_BUFFER_BYTES` | Bias stripe buffer |

### Buffer Behavior

* A buffer ping-pongs to reduce load/compute hazards. The current selection formula is `tile_m[0] ^ (tile_n[0] & tile_m_count[0])`, which avoids selecting the same A buffer across some N-stripe transitions.
* B/Bias are loaded only when `tile_m==0` and reused along the M direction.
* The C store coalescer writes each row as soon as post-processing completes it. Store FSM uses a row-ready bitmap to control row-by-row writer reads.
* Illegal FIFO full push or empty pop is asserted under `ASSERT_ON`.

---

## 13. Register Map

All registers are 32-bit. AXI-Lite addresses are byte addresses.

| Address | Name | R/W | Description |
| ------- | ---- | --- | ----------- |
| `0x0000` | `CTRL` | RW/Pulse | bit0 start, bit1 soft_reset, bit2 irq_en, bit3 clear_done, bit4 clear_error |
| `0x0004` | `STATUS` | RO | bit0 busy, bit1 done, bit2 error, bit3 irq, bit4 overflow_seen |
| `0x0008` | `M_SIZE` | RW | M dimension |
| `0x000c` | `N_SIZE` | RW | N dimension |
| `0x0010` | `K_SIZE` | RW | K dimension |
| `0x0014` | `PRECISION` | RW | 0: INT8, 1: INT16, 2: INT4 |
| `0x0018` | `POST_OP` | RW | 0: none, 1: bias, 2: ReLU, 3: bias+ReLU |
| `0x001c` | `SAT_MODE` | RW | 0: wrap, 1: saturate |
| `0x0020` | `A_BASE` | RW | external A base |
| `0x0024` | `B_BASE` | RW | external pre-transposed B base |
| `0x0028` | `C_BASE` | RW | external row-major C base |
| `0x002c` | `BIAS_BASE` | RW | external bias base |
| `0x0050` | `DMA_CFG` | RW | bit[7:0] burst length, reset value 16 |
| `0x0054` | `IRQ_STATUS` | RO/W1C | bit0 irq, writing bit0 clears irq |
| `0x0058` | `OVF_COUNT` | RO | overflow event count |
| `0x005c` | `ERROR_CODE` | RO | latched error code |

### Register Notes

* `CTRL.start`, `soft_reset`, `clear_done`, `clear_error`, and `IRQ_STATUS[0]` are pulse/W1C style controls.
* Configuration registers support byte strobe merging.
* There are no software-visible SPAD offset/size registers.
* Software should start a new task only when `busy=0` and no uncleared `done/error` is present.

---

## 14. External Data Layout

### A Layout

A is row-major with padded row stride:

```text
A_addr(row) = A_BASE + row * align8(packed_row_bytes(K, precision))
```

Each tile reads `tile_rows` rows and each row has `align8(packed_row_bytes(K, precision))` bytes. In INT4 mode, each byte stores two signed 4-bit elements: even K in the low nibble and odd K in the high nibble. For odd K, the final high nibble is unused.

### B Layout

B is pre-transposed/pre-packed by software as output-column stripes:

```text
B_addr(col) = B_BASE + col * align8(packed_row_bytes(K, precision))
```

Each N tile reads `tile_cols` stripes. Each stripe has `align8(packed_row_bytes(K, precision))` bytes. Hardware interprets the external stripe as `B[k][col]`. INT4 uses the same nibble packing order as A.

### Bias Layout

Bias is an INT32 vector:

```text
Bias_addr(col) = BIAS_BASE + col * 4
```

### C Layout

External C remains row-major INT32:

```text
C_addr(row, col) = C_BASE + (row * N + col) * 4
```

Store generates row-mode descriptors per N-block. With `C_STORE_NBLOCK=2`, if the current tile is N-block slot 0 and is not the N tail, it is cached only. If the current tile is slot 1 or the N tail, the writer stores a contiguous column block starting from the N-block base column:

```text
slot = tile_n % C_STORE_NBLOCK
block_col_base = col_base - slot * TILE_N
base = C_BASE + ((row_base * N + block_col_base) * 4)
row_bytes = (slot * TILE_N + tile_cols) * 4
ext_row_stride = N * 4
row_count = tile_rows
spad_row_stride = C_STORE_NBLOCK * TILE_N * 4
```

This widens each row-mode writeback but preserves the external row-major C ABI.

---

## 15. Error and Corner Cases

### Error Behavior

| Condition | Expected behavior | Recovery |
| --------- | ----------------- | -------- |
| `M/N/K` outside 1..64 | `ERR_ILLEGAL_MATRIX_SIZE` | Write `CTRL.clear_error` or soft reset |
| precision not 0/1/2 | `ERR_ILLEGAL_PRECISION` | Clear error and reconfigure |
| base address alignment violation | `ERR_UNALIGNED_BASE_ADDR` | Clear error and reconfigure |
| start while non-idle | `ERR_COMMAND_WHILE_BUSY` | Clear error |
| AXI read `RRESP[1]` | `ERR_AXI_READ_ERROR` | Clear error |
| AXI write `BRESP[1]` | `ERR_AXI_WRITE_ERROR` | Clear error |
| 4KB crossing without split | `ERR_BURST_CROSS_4KB` | Adjust address/length or enable read split |
| watchdog timeout | `ERR_INTERNAL_TIMEOUT` | Soft reset or clear error |

### Corner Cases

* Non-multiple `M/N` dimensions are handled by row/column valid masks.
* `K` maximum is 64. Current compute handles full K in one pass.
* Bias is read only when post-op enables bias.
* `read row_count_i==0` or `write row_count_i==0` is treated as one row by loader/writer.
* If N is not an integer multiple of `C_STORE_NBLOCK * TILE_N`, the N-tail tile triggers a partial N-block writeback. `row_bytes` covers from the N-block base column through the valid tail column.
* `burst_len=0` makes the burst splitter invalid and may lead to DMA error.

---

## 16. CDC and Timing Assumptions

### CDC

This IP is a single-clock design and has no CDC crossing.

### Timing-Awareness

Potential timing-sensitive logic:

* Multiplication and align8 computation in the load address pipeline.
* C offset calculation: `row_base * N + col_base`.
* Multi-dimensional panel selection in the wavefront feeder.
* Systolic array MAC chain and accumulator.
* AXI DMA burst splitter 4KB and length comparisons.
* C store coalescer read address decode.

### Timing Mitigation

* `load_scheduler` splits address computation into multiple registered stages.
* A/B/C address planning avoids software-programmed SPAD offset/size logic.
* C is not persisted in scratchpad. The C store coalescer caches only a bounded N-block rather than the full C matrix, reducing on-chip storage pressure.
* Read DMA has a small internal FIFO on the R channel.

---

## 17. Required Assertions

RTL or formal checks should cover:

* Fixed SPAD windows do not overlap and do not exceed `SPAD_BYTES`.
* Maximum A/B/Bias tiles fit in their fixed windows.
* Descriptor FIFOs do not push while full or pop while empty.
* Store descriptor push must have active store context.
* Store descriptor row count is nonzero.
* `c_store_coalescer` write M tile, write row, N-block slot, and read row indices are in range.
* `dma_burst_splitter` does not emit bursts beyond `MAX_BURST_BEATS` or across 4KB when not allowed.
* `axi_read_dma` does not emit crossing AR bursts when `AUTO_SPLIT_4KB=1`.
* AXI read/write error responses are latched.
* `wavefront_feeder` outputs match skewed A/B panel indexing.
* `systolic_array` clears accumulators and overflow after reset/clear.
* `region_checker` error priority and output latency match implementation.

---

## 18. Minimum Verification Requirements

### Required Dynamic Tests

* INT8 4x4 base path.
* INT16 4x4 base path.
* INT4 4x4 base path.
* Rectangular matrix.
* Non-aligned dimensions.
* bias, ReLU, and saturation.
* back-to-back command.
* precision switch covering INT4/INT8/INT16.
* IRQ clear and done/error clear.
* AXI read SLVERR.
* Legal random matrix configuration.
* Row-mode C writeback checking.

### Required Formal Targets

The current formal directory should at least cover:

* Phase 1: `dma_burst_splitter`, `dma_descriptor_fifo`, `axi_read_dma`
* Phase 2: `buffer_manager_fsm`, `store_fsm`, `c_store_coalescer`/store row ready-read safety
* Phase 3: `compute_fsm`, `wavefront_feeder`, `systolic_array`
* Phase 4: `region_checker`

### Required Review Evidence

* RTL compilation passes.
* Basic dynamic simulation passes.
* Formal/STA evidence is requested separately by project phase; it is not a completion requirement for every SPEC update during the current dynamic coverage-closure phase.
* Known parameter defaults and software ABI are recorded in this SPEC.

---

## 19. Final SPEC Summary

### Confirmed Design Decisions

* The top-level IP is a single-clock matrix accelerator with AXI-Lite configuration and AXI4 master DMA.
* Default array size is 4x4 and maximum matrix dimension is 64.
* A uses ping-pong buffering. B uses one bank and is reused along the M direction.
* SPAD address space is planned by hardware and no offset/size registers are exposed.
* External C remains row-major. Store uses multi-row writes and fixed `C_STORE_NBLOCK=2` N-block coalescing to widen writeback granularity.
* External B requires software pre-transpose/pre-pack.
* Read DMA has parameterized 4KB auto split support, but it is disabled by default at the top level.

### Human Review Required

| ID | Item | Why it matters |
| -- | ---- | -------------- |
| HR1 | Whether to default `READ_AUTO_SPLIT_4KB` to 1 | Affects whether software must avoid read 4KB crossing |
| HR2 | Whether to add write DMA 4KB auto split | Current C row writes can still hit 4KB crossing errors |
| HR3 | Whether to freeze the B pre-transposed ABI | Affects driver, test generation, and integration docs |
| HR4 | Whether to remove or redefine the currently unused K tiling semantics | Affects future strong weight-stationary or K-blocked redesign |

### SPEC Status

Status: pending review. This document is based on the current RTL implementation and can be used as the baseline for verification, driver, and system integration work.
