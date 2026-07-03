# Tensor Accelerator Verification Plan

## 1. Document Overview

### 1.1 Document Purpose

This document defines the full verification plan for `tensor_accel_top`. It is derived from the current RTL implementation and the RTL SPEC, and it is intended to be the verification source of truth for directed tests, constrained-random tests, coverage closure, assertions, regression, bug tracking, and sign-off.

### 1.2 Scope

| Scope | Description |
| ----- | ----------- |
| DUT | `tensor_accel_top` plus integrated RTL submodules |
| Verification Level | Block/subsystem-level RTL simulation |
| Verification Type | Functional verification, coverage-driven verification, error injection, regression |
| Testbench Language | SystemVerilog / UVM |
| Primary Methodology | Directed + constrained-random + scoreboard + coverage |

**In Scope:**

- AXI-Lite register programming and status behavior.
- AXI4 read/write DMA behavior through the integrated memory model/VIP.
- INT4, INT8, and INT16 matrix multiply datapaths.
- Bias, ReLU, wrap, saturation, overflow tracking, and IRQ behavior.
- A ping-pong buffering, single B stripe reuse, fixed Bias window, and internal SPAD layout.
- Read descriptor FIFO, write descriptor FIFO, read 4KB split option, and write 4KB error reporting.
- Load/compute overlap and post/store/writeback behavior.
- Fixed `C_STORE_NBLOCK=2` C store coalescing while preserving external row-major C layout.
- Reset, soft reset, command conflict, legal random configuration, and directed error injection.
- Functional and code coverage closure with documented waivers.

**Out of Scope unless explicitly requested:**

- Formal verification.
- STA and gate-level timing simulation.
- Power, DFT, CDC sign-off, FPGA prototype validation, and firmware co-simulation.

### 1.3 Reference Documents

| Ref | Document | Description |
| --- | -------- | ----------- |
| R1 | `rtl/SPEC_EN.md` | Current RTL design specification and ABI facts |
| R2 | `rtl/SPEC_CN.md` | Chinese RTL design specification |
| R3 | `rtl/top_level_system_diagram.md` | Text architecture diagram and subsystem split |
| R4 | `rtl/performance_optimization_plan.md` | Performance optimization plan and implementation notes |
| R5 | `tb/doc/bug_log.md` | Bug tracking log |
| R6 | `script/filelist.f` | RTL/TB compilation file list |
| R7 | `Makefile` | Regression, elaboration, run, coverage, and merge targets |

## 2. DUT Overview

### 2.1 DUT Function Overview

`tensor_accel_top` is a single-clock integer matrix multiplication accelerator. Software programs matrix dimensions, precision, post-processing mode, base addresses, and DMA burst length through AXI-Lite. The DUT loads A/B/Bias through AXI4 read DMA, computes tiled GEMM with a 4x4 systolic array, applies post-processing, and writes row-major INT32 C results through AXI4 write DMA.

**Primary Functions:**

- AXI-Lite register interface for configuration, status, IRQ, overflow, and error code access.
- AXI4 master read/write DMA with internal descriptor FIFOs.
- Fixed internal SPAD region planning for A0/A1/B/Bias.
- Tiled compute over `M/N`, full `K` per tile, no K-tile partial accumulation.
- Signed INT4/INT8/INT16 input handling with 40-bit accumulation and INT32 output.
- C store coalescing with fixed `C_STORE_NBLOCK=2`.

**Key Characteristics:**

| Item | Value |
| ---- | ----- |
| Clock Domain | Single `clk` |
| Reset | Active-low asynchronous `rst_n`; software `soft_reset` pulse |
| AXI-Lite | 32-bit data, 16-bit address |
| AXI4 Master | 64-bit data, 32-bit address, fixed ID 0, INCR bursts |
| Default Array | 4x4 |
| Maximum Dimension | `MAX_DIM=64` |
| Output Format | INT32 row-major C |
| B Layout | Software pre-transposed/pre-packed output-column stripes |
| C Writeback | Row-mode multi-row write; N-block coalesced by two adjacent N tiles |

### 2.2 DUT Block Diagram

```text
+--------------------------------------------------------------------------+
|                             tensor_accel_top                              |
|                                                                          |
| AXI-Lite -> axi_lite_slave -> reg_file -> cfg_active/status/error/irq     |
|                                                                          |
| command_fsm -> tile_count_fsm -> buffer_manager_fsm                       |
|      |             |                 |                                    |
|      |             |                 +-> fixed SPAD bases A0/A1/B/Bias    |
|      |             |                                                      |
|      +-> load_scheduler -> read_desc_fifo -> tensor_loader -> axi_read_dma |
|      |                                      |                             |
|      |                                      v                             |
|      |                          scratchpad_ctrl -> scratchpad             |
|      |                                      |                             |
|      +-> compute_fsm -> wavefront_feeder -> systolic_array -> accumulator |
|      |                                      |                             |
|      +-> post_process_fsm -> post_process -> c_store_coalescer            |
|                                             |                             |
|                                             v                             |
|      +-> store_fsm -> write_desc_fifo -> tensor_writer -> axi_write_dma   |
|                                                                          |
+--------------------------------------------------------------------------+
```

**Block Description:**

| Block | Function |
| ----- | -------- |
| `axi_lite_slave` | AXI-Lite handshaking and register access conversion |
| `reg_file` | Register map, pulses, IRQ enable, status readback, configuration storage |
| `region_checker` | Matrix size, precision, and base address alignment checks |
| `command_fsm` | Top-level command sequencing, status, IRQ, timeout, and error latch |
| `tile_count_fsm` | `tile_m/tile_n`, row/column valid masks, C external offset |
| `buffer_manager_fsm` | A ping-pong selection, B/Bias fixed bases, prefetch hazard checks |
| `load_scheduler` | A/B/Bias descriptor generation and pending read-drain tracking |
| `dma_descriptor_fifo` | In-order read and write descriptor buffering |
| `tensor_loader` | Row-mode read scheduling, alignment adjustment, SPAD writes |
| `tensor_writer` | Row-mode write scheduling, row-ready gating, SPAD/coalescer reads |
| `axi_read_dma` | AXI AR/R burst engine with optional read 4KB split |
| `axi_write_dma` | AXI AW/W/B burst engine with write error and 4KB crossing reporting |
| `wavefront_feeder` | Skewed A/B feed for the systolic array |
| `systolic_array` | PE array with signed MAC and propagation |
| `accumulator` | Captures systolic results for post-processing |
| `post_process` | Bias, ReLU, wrap/saturate, overflow generation |
| `c_store_coalescer` | C row cache indexed by M tile and N-block slot |

### 2.3 DUT Interface List

| Interface | Direction | Width | Description |
| --------- | --------- | ----: | ----------- |
| `clk` | input | 1 | Single clock |
| `rst_n` | input | 1 | Active-low asynchronous reset |
| `s_axil_*` | mixed | 32-bit data / 16-bit addr | AXI-Lite register interface |
| `m_axi_ar*`, `m_axi_r*` | mixed | 64-bit data / 32-bit addr | AXI4 read master |
| `m_axi_aw*`, `m_axi_w*`, `m_axi_b*` | mixed | 64-bit data / 32-bit addr | AXI4 write master |
| `irq` | output | 1 | Level-style completion/error interrupt |

Simulation-only ports under `ifndef SYNTHESIS` are used for command FSM error-arc injection and are not part of the synthesizable interface contract.

## 3. Verification Objectives

### 3.1 Functional Correctness

| ID | Objective | Description |
| -- | --------- | ----------- |
| FC-01 | CSR behavior | Verify reset values, RW/RO/W1C/pulse semantics, byte strobes, and no exposed SPAD offset/size registers. |
| FC-02 | Matrix datapath | Verify INT4/INT8/INT16 GEMM for square, rectangular, tail, and degenerate legal dimensions. |
| FC-03 | Post-processing | Verify bias, ReLU, bias+ReLU, wrap, saturation, overflow_seen, and OVF_COUNT. |
| FC-04 | External data layout | Verify A row-major packed layout, B pre-transposed stripe layout, Bias vector layout, and row-major C output. |
| FC-05 | C store coalescing | Verify `C_STORE_NBLOCK=2` caching, N-block tail handling, row_bytes calculation, and row-major correctness. |
| FC-06 | Buffer management | Verify A ping-pong, B/Bias reuse at `tile_m==0`, and no load/compute/store hazards. |
| FC-07 | DMA descriptors | Verify descriptor FIFO ordering, row-mode descriptors, split/read behavior, and write descriptor generation. |
| FC-08 | Error behavior | Verify all defined error codes, latching, clear behavior, and recovery where supported. |
| FC-09 | IRQ/status | Verify done/error IRQ assert, hold, clear, and IRQ enable behavior. |
| FC-10 | Reset | Verify cold reset, soft reset, and reset during active load/compute/store. |

### 3.2 Protocol Correctness

| ID | Objective | Description |
| -- | --------- | ----------- |
| PC-01 | AXI-Lite | Verify AW/W/B and AR/R handshakes, read latency, byte strobe merge, and response stability. |
| PC-02 | AXI read | Verify AR/R ordering, RLAST handling, RRESP error detection, and no data loss under backpressure. |
| PC-03 | AXI write | Verify AW/W/B ordering, WSTRB correctness, WLAST, BRESP error detection, and row-mode sequencing. |
| PC-04 | Internal valid/ready | Verify descriptor FIFO push/pop, loader/writer busy/done/error, and store row-ready/read safety. |
| PC-05 | In-order execution | Verify command, descriptor, tile, and C writeback ordering remain strictly in-order. |

### 3.3 Boundary Conditions

| ID | Objective | Description |
| -- | --------- | ----------- |
| BC-01 | Minimum legal dimensions | `M/N/K=1` and thin rectangular shapes. |
| BC-02 | Maximum legal dimensions | `M/N/K=64`, including random legal max-stress seeds. |
| BC-03 | Tile tails | Non-multiple `M/N` sizes and N-block tail coalescing. |
| BC-04 | Precision packing | INT4 odd/even K nibble packing, INT8 byte packing, INT16 lane strobes. |
| BC-05 | Burst boundaries | Burst length min/max/zero/exceed cases and read/write 4KB boundary behavior. |
| BC-06 | FIFO boundaries | Read/write descriptor FIFO empty/full protection and ordering. |
| BC-07 | Status boundaries | start while busy/done/error, clear_done, clear_error, clear_irq, soft_reset. |

### 3.4 Robustness

| ID | Objective | Description |
| -- | --------- | ----------- |
| RB-01 | Back-to-back commands | Verify repeated commands do not leak state. |
| RB-02 | Precision switch | Verify sequential commands switching INT4/INT8/INT16. |
| RB-03 | Random legal configurations | Verify randomized legal matrix shapes and modes across seeds. |
| RB-04 | AXI error injection | Inject read and write errors at targeted phases. |
| RB-05 | Command FSM error arcs | Use simulation-only force ports for otherwise difficult error arcs. |
| RB-06 | Reset during operation | Reset during load, compute, store, and idle. |
| RB-07 | Long run stability | Full regression across directed, exception, and random tests with coverage enabled. |

## 4. Verification Scope

### 4.1 In Scope

| ID | Scope Item | Description |
| -- | ---------- | ----------- |
| IS-01 | Directed base tests | Basic INT4/INT8/INT16, 8x8 path, rectangular, non-aligned, degenerate, bias, ReLU, saturation. |
| IS-02 | Exception tests | Illegal size/precision/base, AXI read/write errors, command conflict, timeout, IRQ on error. |
| IS-03 | Random tests | Legal random, corner-data random, max-stress random. |
| IS-04 | Coverage closure | Functional, branch, line, condition, toggle, FSM, and assertion coverage with waivers. |
| IS-05 | Register verification | CSR read/write/reset/RO/W1C/pulse behavior. |
| IS-06 | Data integrity | End-to-end scoreboard comparison against software reference. |
| IS-07 | Performance observation | TB-side performance monitor for latency/stall/throughput observation. |
| IS-08 | Assertions | Synthesizable RTL assertions under `ASSERT_ON` plus TB/protocol checks. |

### 4.2 Out of Scope

| ID | Scope Item | Rationale |
| -- | ---------- | --------- |
| OS-01 | Formal verification | Run only when explicitly requested. |
| OS-02 | STA / gate-level timing | Physical timing closure is outside this RTL simulation plan. |
| OS-03 | Software driver co-simulation | Software behavior is modeled as register and memory transactions. |
| OS-04 | Tile-major C ABI | Current SPEC requires row-major C. |
| OS-05 | Full B on-chip transpose engine | Current B ABI is software pre-transposed/pre-packed. |
| OS-06 | Arbitrary array-size parameter sign-off | Default verification is for the current 4x4 build; 8x8 upgrade is a later project phase. |

## 5. Verification Strategy

### 5.1 Verification Levels

| Level | Scope | Method | Objective |
| ----- | ----- | ------ | --------- |
| L1 Module | Leaf and controller modules in integrated TB context | Directed tests + assertions | Check protocol and basic behavior exposed through top-level tests. |
| L2 Subsystem | Load/compute/store/DMA/register subsystems | Directed + error injection | Validate subsystem sequencing and recovery. |
| L3 End-to-End | Full `tensor_accel_top` | Scoreboard + directed/random | Validate matrix results and observable status. |
| L4 Closure | Full regression | Multi-seed random + coverage merge + waiver review | Close coverage and stabilize regression. |

### 5.2 Verification Methods

| Method | Applied At | Notes |
| ------ | ---------- | ----- |
| Directed tests | L2/L3 | Primary tool for targeted features and regressions. |
| Constrained-random tests | L3/L4 | Legal matrix/mode randomization with scoreboard checking. |
| Error injection | L2/L3 | AXI response errors, illegal config, command conflict, timeout, internal force hooks. |
| Scoreboard | L3/L4 | Matrix reference model compares external C memory content. |
| Functional coverage | L3/L4 | Covergroups in `tb/env/tensor_accel_coverage.sv`. |
| Code coverage | L4 | VCS line/cond/fsm/branch/tgl/assert with `cov_waivers`. |
| Assertions | All | RTL `ASSERT_ON` and TB protocol checks. |
| Performance monitor | L3/L4 | TB monitor only; performance counters are not retained in RTL main path. |

### 5.3 Verification Environment File Organization

```text
tb/
├── tb/
│   ├── top_tb.sv
│   ├── tensor_accel_dut_if.sv
│   └── tensor_accel_uvm_pkg.sv
├── env/
│   ├── tensor_accel_env.sv
│   ├── tensor_accel_ref_model.sv
│   ├── tensor_accel_scoreboard.sv
│   ├── tensor_accel_coverage.sv
│   └── tensor_perf_monitor.sv
├── reg_model/
│   └── tensor_accel_reg_pkg.sv
├── seq_lib/
│   ├── tensor_common_vseqs.sv
│   ├── directed_tests/
│   ├── exception_tests/
│   └── random_tests/
└── tests/
    ├── base_test.sv
    ├── directed_tests/
    ├── exception_tests/
    └── random_tests/
```

### 5.4 Check Mechanisms

| Mechanism | What It Checks | Failure Response |
| --------- | -------------- | ---------------- |
| Scoreboard | External C memory result against reference model | `uvm_error` / test fail |
| Register model/sequences | CSR access, clear behavior, status/error | `uvm_error` |
| AXI VIP / monitors | AXI protocol, response, and memory behavior | VIP error or TB error |
| RTL assertions | FIFO bounds, store context, SPAD windows, coalescer bounds | `$fatal` when `ASSERT_ON` |
| Coverage model | Feature and transition coverage | Coverage gap triage |
| Performance monitor | Latency/stall/throughput observation | Report and trend, not sign-off blocker unless threshold is defined |

## 6. Verification Environment Description

### 6.1 Verification Environment Architecture

```text
+------------------------------------------------------------------------+
| top_tb                                                                 |
|  +--------------------+       +--------------------------------------+ |
|  | tensor_accel_dut_if|<----->| tensor_accel_top                     | |
|  +--------------------+       +--------------------------------------+ |
|        ^                                  ^                            |
|        |                                  | AXI4/AXI-Lite              |
|  +--------------------+       +--------------------------------------+ |
|  | tensor_accel_env   |<----->| Synopsys SVT AXI system environment  | |
|  |  ref_model         |       +--------------------------------------+ |
|  |  scoreboard        |                                              |
|  |  coverage          |                                              |
|  |  perf_monitor      |                                              |
|  +--------------------+                                              |
+------------------------------------------------------------------------+
```

**VIP Information:**

| VIP | Version | Vendor | Interface | Notes |
| --- | ------- | ------ | --------- | ----- |
| SVT AXI System VIP | 2018.09 | Synopsys | AXI-Lite and AXI4 memory system | Used for register and memory transactions |

### 6.2 Agent Partitioning

| Agent/Component | Type | Function |
| --------------- | ---- | -------- |
| AXI system sequencer | Active VIP | Drives register, memory, and slave response sequences. |
| `tensor_accel_env` | UVM env | Owns reference model, scoreboard, coverage, and perf monitor. |
| `tensor_accel_ref_model` | Predictor | Computes expected C matrix for configured operation. |
| `tensor_accel_scoreboard` | Comparator | Compares expected and observed memory/result behavior. |
| `tensor_accel_coverage` | Subscriber | Samples functional coverage. |
| `tensor_perf_monitor` | Monitor | Tracks performance events outside RTL. |

### 6.3 Reference Model

| Attribute | Description |
| --------- | ----------- |
| Implementation Language | SystemVerilog |
| Accuracy | Transaction-level functional model |
| Supported Features | INT4/INT8/INT16, row-major A, pre-transposed B stripes, Bias/ReLU/saturation/wrap, row-major C |
| Input Source | Programmed test configuration and memory initialization |
| Output Destination | Scoreboard expected matrix |
| Configuration Awareness | Uses the same register configuration as DUT tests |

### 6.4 Scoreboard

| Attribute | Description |
| --------- | ----------- |
| Comparison Granularity | Per matrix element / per test transaction |
| Input Sources | Expected matrix from reference model; actual C memory content after DUT completion |
| Ordering | In-order command completion |
| Mismatch Behavior | `uvm_error` with mismatch details |
| Timeout Handling | Test timeout/watchdog fails the test |
| Drop/Duplicate Detection | Covered by full matrix content comparison and completion status |

## 7. Feature List / Verification Items

### 7.1 Priority Definition

| Priority | Meaning |
| -------- | ------- |
| P0 | Must pass for any usable release. |
| P1 | Must pass for verification closure. |
| P2 | Important stress/coverage item, may be waived with review. |
| P3 | Optional exploratory item. |

### 7.2 Verification Item Table

| Feature ID | Feature Description | Objective | Priority | Method | Coverage Point | Tests |
| ---------- | ------------------- | --------- | -------- | ------ | -------------- | ----- |
| F-REG | CSR map and semantics | Reset/RW/RO/W1C/pulse/IRQ enable | P0 | Directed + RAL | CSR bins | reg, irq, ro protection |
| F-INT8 | INT8 datapath | Correct GEMM and C writeback | P0 | Directed + random | precision bins | 4x4, 8x8, random |
| F-INT16 | INT16 datapath | Correct sign extension and accumulation | P0 | Directed | precision bins | int16, max stress |
| F-INT4 | INT4 datapath | Correct nibble unpack, sign extension, result | P0 | Directed + random | precision bins | int4, precision switch |
| F-POST | Post-process | Bias/ReLU/saturation/wrap/overflow | P0 | Directed | post_op/sat bins | bias, relu, saturation |
| F-SHAPE | Matrix shapes | Rectangular, tails, degenerate legal dims | P0 | Directed + random | shape bins | rect, non-aligned, degenerate |
| F-BLAYOUT | B pre-transposed ABI | B stripe read and reuse across M | P0 | Scoreboard | B reuse bins | base/random |
| F-CSTORE | C row-major writeback | N-block coalescer and row-mode writes | P0 | Directed + coverage | store/coalescer bins | 8x8, rect, random |
| F-DMA-R | Read DMA | Descriptor FIFO, row-mode, error, optional 4KB split | P1 | Directed/error | read DMA bins | read slverr, burst |
| F-DMA-W | Write DMA | Row-mode, WSTRB, BRESP error, 4KB crossing error | P1 | Directed/error | write DMA bins | write slverr, unaligned |
| F-FSM | Command FSM | Normal, pipe, done, error arcs | P1 | Directed + error injection | FSM coverage | command error arc |
| F-BUF | Buffer manager | A ping-pong, B/Bias reuse, hazards | P1 | Directed/random | buffer bins | base/random/back-to-back |
| F-RESET | Reset behavior | Cold reset, soft reset, active reset | P1 | Directed | reset-state cross | reset tests |
| F-IRQ | IRQ/status | Done/error IRQ, clear, status bits | P1 | Directed | IRQ bins | base_irq, irq_on_error |
| F-RAND | Random legal stress | Legal randomized configurations | P2 | Random | config crosses | random legal/corner/max |
| F-COV | Coverage closure | Coverage merge and waiver review | P1 | Regression | code/functional coverage | full regression |

## 8. Test Case List

### 8.1 Test Type Legend

| Type | Description |
| ---- | ----------- |
| Directed | Hand-crafted single-purpose test. |
| Constrained-Random | Random legal/corner/stress configuration. |
| Error Injection | Illegal config, AXI error, command conflict, force hooks. |
| Stress | Multi-seed or max-size stability/performance-oriented test. |

### 8.2 Test Case Table

| Test Case ID | Test Name | Type | Target Features | Pass/Fail Criteria |
| ------------ | --------- | ---- | --------------- | ------------------ |
| TC-BASE-8X8 | `tensor_base_8x8_test` | Directed | F-INT8, F-CSTORE, F-BUF | Test completes, `UVM_ERROR=0`, C matches reference. |
| TC-INT4 | `tensor_base_int4_4x4_test` | Directed | F-INT4 | C matches reference for INT4 packed data. |
| TC-INT8 | `tensor_base_int8_4x4_test` | Directed | F-INT8 | C matches reference. |
| TC-INT16 | `tensor_base_int16_4x4_test` | Directed | F-INT16 | C matches reference. |
| TC-BURST | `tensor_base_burst_len_test` | Directed | F-DMA-R, F-DMA-W | Burst configuration variants pass without mismatch. |
| TC-B2B | `tensor_base_back_to_back_test` | Directed | F-BUF, F-FSM | Multiple commands pass with no stale state. |
| TC-PREC-SW | `tensor_base_bb_precision_switch_test` | Directed | F-INT4, F-INT8, F-INT16 | Sequential precision switching passes. |
| TC-IRQ | `tensor_base_irq_test` | Directed | F-IRQ, F-REG | IRQ asserts/clears per SPEC. |
| TC-RECT | `tensor_base_rect_matrix_test` | Directed | F-SHAPE, F-CSTORE | Rectangular output matches reference. |
| TC-NONALIGNED | `tensor_base_non_aligned_size_test` | Directed | F-SHAPE, F-CSTORE | Tail M/N handling passes. |
| TC-DEGEN | `tensor_base_degenerate_dims_test` | Directed | F-SHAPE | Legal thin shapes pass. |
| TC-BIAS | `tensor_base_bias_test` | Directed | F-POST | Bias applied correctly. |
| TC-RELU | `tensor_base_relu_test` | Directed | F-POST | ReLU applied correctly. |
| TC-BIAS-RELU | `tensor_base_bias_relu_order_test` | Directed | F-POST | Bias before ReLU ordering passes. |
| TC-SAT | `tensor_base_saturation_test` | Directed | F-POST | Saturation/wrap behavior matches model. |
| TC-OVERFLOW | `tensor_base_overflow_status_test` | Directed | F-POST, F-IRQ | Overflow status/count match expected behavior. |
| TC-AXI-READY | `tensor_base_axi_ready_delay_test` | Directed | F-DMA-R, F-DMA-W | Backpressure does not corrupt data. |
| TC-RO | `tensor_base_ro_reg_protection_test` | Directed | F-REG | RO fields do not change on writes. |
| TC-WR-UNALIGN | `tensor_base_write_unaligned_test` | Directed | F-DMA-W | Supported C alignment behavior matches SPEC. |
| TC-ERR-SIZE | `tensor_err_illegal_matrix_size_test` | Error Injection | F-REG, F-FSM | `ERR_ILLEGAL_MATRIX_SIZE` reported. |
| TC-ERR-PREC | `tensor_err_illegal_precision_test` | Error Injection | F-REG, F-FSM | `ERR_ILLEGAL_PRECISION` reported. |
| TC-ERR-BASE | `tensor_err_unaligned_base_test` | Error Injection | F-REG, F-FSM | `ERR_UNALIGNED_BASE_ADDR` reported. |
| TC-ERR-RD | `tensor_err_axi_read_slverr_test` | Error Injection | F-DMA-R | `ERR_AXI_READ_ERROR` reported and recoverable. |
| TC-ERR-WR | `tensor_err_axi_write_slverr_test` | Error Injection | F-DMA-W | `ERR_AXI_WRITE_ERROR` reported and recoverable. |
| TC-ERR-CMD | `tensor_err_command_while_busy_test` | Error Injection | F-FSM | `ERR_COMMAND_WHILE_BUSY` reported. |
| TC-ERR-DONE | `tensor_err_start_while_done_test` | Error Injection | F-FSM | Start while done/error path handled. |
| TC-ERR-BURST | `tensor_err_burst_len_zero_test`, `tensor_err_burst_len_exceed_test` | Error Injection | F-DMA-R/W | Invalid burst behavior matches SPEC/test intent. |
| TC-ERR-TIMEOUT | `tensor_err_internal_timeout_test` | Error Injection | F-FSM | Timeout error reported. |
| TC-ERR-ARC | `tensor_err_command_fsm_error_arc_test` | Error Injection | F-FSM | Remaining reachable error arcs are hit. |
| TC-RST-LOAD | `tensor_reset_during_load_test` | Directed | F-RESET | Reset during load recovers. |
| TC-RST-COMP | `tensor_reset_during_compute_test` | Directed | F-RESET | Reset during compute recovers. |
| TC-RST-STORE | `tensor_reset_during_store_test` | Directed | F-RESET | Reset during store recovers. |
| TC-SOFT-RST | `tensor_soft_reset_test`, `tensor_soft_reset_during_idle_test` | Directed | F-RESET | Soft reset behavior matches SPEC. |
| TC-RAND-LEGAL | `tensor_base_random_legal_test` | Constrained-Random | F-RAND | All seeds pass scoreboard and assertions. |
| TC-RAND-CORNER | `tensor_base_random_corner_data_test` | Constrained-Random | F-RAND, F-POST | Corner data patterns pass. |
| TC-RAND-STRESS | `tensor_base_random_max_stress_test` | Stress | F-RAND, F-BUF, F-CSTORE | Max legal random stress passes. |

## 9. Coverage Plan

### 9.1 Functional Coverage

| Covergroup / Area | Description | Sampled On | Target |
| ----------------- | ----------- | ---------- | -----: |
| CSR coverage | Register access, reset, clear, error/status fields | Register transactions | 100% P0/P1 |
| Precision coverage | INT4/INT8/INT16 | Test config / completion | 100% |
| Shape coverage | Square, rectangular, tail, degenerate, max | Test config | 100% P0/P1 |
| Post-op coverage | none/bias/ReLU/bias+ReLU × wrap/saturate | Test config / result | 100% |
| DMA coverage | Read/write descriptors, row mode, burst len, errors | DMA monitor/status | 100% P0/P1 |
| C store coverage | `C_STORE_NBLOCK=2`, slot 0 cache, slot 1 write, N-tail partial block | Store/coalescer events | 100% |
| Buffer coverage | A bank selection, N transition, B/Bias reuse | Internal/TB monitor | 100% |
| FSM coverage | Command FSM states and reachable transitions | VCS FSM coverage | 100% reachable |
| Error coverage | Each error code and recovery path | Status/error monitor | 100% P0/P1 |
| Reset coverage | Reset during idle/load/compute/store/done/error | Reset tests | 100% P1 |

### 9.2 Cross Coverage

| Cross | Variables | Target |
| ----- | --------- | -----: |
| Precision x Post-op | `precision` x `post_op` x `sat_mode` | 100% meaningful legal combinations |
| Shape x Precision | matrix shape class x precision | 100% P0/P1 |
| C store x Shape | N-block slot/tail x tile_cols class | 100% |
| Error x FSM state | error source x command state | 100% reachable, waiver unreachable |
| Reset x FSM state | reset type x active stage | 100% directed states |
| Burst x DMA path | burst_len bucket x read/write x row_mode | 100% P1 |

### 9.3 Code Coverage

| Type | Target | Notes |
| ---- | -----: | ----- |
| Line | >= 95% | Reviewed waivers allowed. |
| Condition | >= 90% | Unreachable combinations documented. |
| FSM state | 100% reachable states | Reset-only/unreachable arcs reviewed. |
| FSM transition | 100% reachable functional arcs | Error arcs covered or waived. |
| Branch | >= 90% | Defaults reviewed. |
| Toggle | >= 90% | Tied-off/test-only/VIP/interface waivers allowed. |
| Assertion | 100% pass | No unreviewed assertion failure. |

Coverage exclusions are stored under `cov_waivers/`. Known filtered scopes include `axi_if`, `dut_if`, and `uvm_custom_install_verdi_recording`.

## 10. Assertion Plan

### 10.1 Severity Level Definition

| Severity | Meaning |
| -------- | ------- |
| S0 Fatal | Data corruption, illegal FIFO access, protocol break, unrecoverable state. |
| S1 Error | Functional correctness or error handling violation. |
| S2 Warning | Suspicious condition requiring review. |
| S3 Info | Debug/coverage-only observation. |

### 10.2 Assertion List

| ID | Check Content | Severity | Scope |
| -- | ------------- | -------- | ----- |
| AS-FIFO-01 | Descriptor FIFO push while full is illegal | S0 | Read/write descriptor FIFO |
| AS-FIFO-02 | Descriptor FIFO pop while empty is illegal | S0 | Read/write descriptor FIFO |
| AS-SPAD-01 | Fixed SPAD windows do not overlap and fit implemented capacity | S0 | Buffer manager / region checker |
| AS-SPAD-02 | Maximum A/B/Bias tile fits each fixed window | S0 | Region checker |
| AS-ST-01 | Store descriptor push requires active store context | S0 | Top/store FSM |
| AS-ST-02 | Store descriptor row count is nonzero | S0 | Top/store FSM |
| AS-ST-03 | Store FSM must not accept overlapping store start | S0 | Store FSM |
| AS-CSTORE-01 | Coalescer write M tile, row, and N-block slot are in range | S0 | C store coalescer |
| AS-CSTORE-02 | Coalescer read M tile and row are in range | S0 | C store coalescer |
| AS-DMA-01 | Burst splitter emits valid nonzero burst only for legal input | S1 | DMA burst splitter |
| AS-DMA-02 | Read auto split does not issue crossing AR when enabled | S1 | AXI read DMA |
| AS-FSM-01 | Command FSM state remains legal | S0 | Command FSM / coverage review |
| AS-AXI-01 | AXI error response latches into expected error code | S1 | Read/write DMA + command FSM |

## 11. Regression Test Plan

### 11.1 Smoke Regression

| Attribute | Description |
| --------- | ----------- |
| Purpose | Fast confidence check after RTL/TB edits. |
| Trigger | Local change or pre-regression check. |
| Scope | Core P0 directed tests. |
| Max Runtime | 180s per minimal path test unless otherwise configured. |
| Pass Criteria | 100% pass, no UVM error/fatal, no assertion failure. |

Smoke tests: `tensor_base_8x8_test`, INT4/INT8/INT16 4x4 tests, IRQ, rectangular, non-aligned, degenerate, saturation.

### 11.2 Base Regression

| Attribute | Description |
| --------- | ----------- |
| Purpose | Daily functional stability. |
| Scope | P0/P1 directed + exception tests. |
| Pass Criteria | All P0 pass, no untriaged P1 failure, no unreviewed assertion failure. |
| Failure Response | Diagnose, classify RTL/TB/SPEC/infrastructure, update `bug_log.md`. |

### 11.3 Full Regression

| Attribute | Description |
| --------- | ----------- |
| Purpose | Coverage-closure and release-quality check. |
| Scope | All directed, exception, random, stress, coverage enabled. |
| Pass Criteria | 100% tests pass or documented waivers; coverage targets met or waived. |
| Failure Response | Blocks coverage sign-off until fixed or reviewed. |

### 11.4 Performance / Stress Regression

| Metric | Measurement Method | Threshold |
| ------ | ------------------ | --------- |
| Load/compute overlap | TB performance monitor | Trend only unless a target is published. |
| Store progress | Writer/store monitor | No deadlock; row-ready respected. |
| Back-to-back stability | Directed B2B and random tests | No stale state or mismatch. |
| Random max stress | Multi-seed random max test | No hang/mismatch/assertion failure. |

## 12. Pass/Fail Criteria

### 12.1 Individual Test Pass/Fail Criteria

| Result | Definition |
| ------ | ---------- |
| PASS | Test completes, scoreboard has zero mismatches, `UVM_ERROR=0`, `UVM_FATAL=0`, and assertions are clean. |
| FAIL | Any mismatch, UVM error/fatal, assertion failure, timeout, simulator crash, or unexpected status/error. |
| SKIP | Test not applicable to the current build and reports a documented skip reason. |

### 12.2 Regression Pass/Fail Criteria

| Regression | Criteria |
| ---------- | -------- |
| Smoke | 100% pass. |
| Base | All P0/P1 expected tests pass or have documented active bugs. |
| Full | All tests pass, coverage merged, waivers reviewed. |
| Coverage closure | P0/P1 functional coverage closed; code coverage gaps reviewed and waived/fixed. |

## 13. Sign-Off

### 13.1 Sign-Off Checklist

| ID | Check Item | Owner | Criteria | Status |
| -- | ---------- | ----- | -------- | ------ |
| SF-01 | RTL elaboration clean | RTL/DV | `make elab` passes with selected options | Open |
| SF-02 | Smoke regression clean | DV | P0 smoke all pass | Open |
| SF-03 | Full regression clean | DV | Directed/exception/random/stress all pass | Open |
| SF-04 | Functional coverage closed | DV | P0/P1 100%, reviewed P2 gaps | Open |
| SF-05 | Code coverage reviewed | DV + RTL | Targets met or waivers recorded | Open |
| SF-06 | Assertion failures resolved | RTL/DV | Zero unreviewed failures | Open |
| SF-07 | Bug log reviewed | RTL/DV | No open P0/P1; P2 disposition documented | Open |
| SF-08 | SPEC alignment checked | RTL/DV | Plan and tests match current SPEC | Open |
| SF-09 | Waiver file reviewed | RTL/DV | Waivers are scoped, justified, and reproducible | Open |

### 13.2 Coverage Convergence Tracking

Coverage convergence is tracked in `cov_waivers/` and related coverage reports. Each closure iteration must record:

- Regression command/build options.
- Passing/failing test list.
- Coverage deltas.
- New exclusions and justification.
- Remaining uncovered branches/FSM transitions and owner.

## 14. Bug Management

### 14.1 Bug Severity

| Severity | Meaning | Examples |
| -------- | ------- | -------- |
| P0 | Blocks basic operation or corrupts data | Wrong C output, deadlock, broken reset |
| P1 | Blocks feature closure | Missing error code, IRQ issue, coverage-critical reachable arc |
| P2 | Important but not release blocking with waiver | Rare stress gap, low-risk coverage hole |
| P3 | Cleanup/documentation | Message clarity, nonblocking doc issue |

### 14.2 Bug Lifecycle

1. Reproduce with exact test, seed, build, and options.
2. Classify as RTL, TB, SPEC, coverage waiver, or infrastructure.
3. Record in `tb/doc/bug_log.md`.
4. Fix and rerun the failing test.
5. Rerun affected smoke/base tests.
6. Close only after evidence is recorded.

### 14.3 Bug Record Fields

| Field | Description |
| ----- | ----------- |
| ID | Stable bug ID |
| Date | Discovery date |
| Test/seed | Reproducer |
| Module | Suspected RTL/TB module |
| Symptom | Observable failure |
| Root cause | Confirmed cause |
| Fix | RTL/TB/SPEC change |
| Verification | Tests rerun |
| Status | Open / Fixed / Waived / Duplicate |

## 15. Risks and Limitations

### 15.1 Risks

| Risk | Impact | Mitigation |
| ---- | ------ | ---------- |
| INT4 datapath packing/sign extension | Data corruption | Directed INT4 and random corner-data tests. |
| C store coalescer tail handling | Row-major C mismatch | Directed N-tail and rectangular tests. |
| FSM error arcs | Coverage holes or unreachable definitions | Directed error injection and waiver review. |
| Write 4KB crossing | Real system integration constraint | Directed error tests and SPEC documentation. |
| B pre-transposed ABI | Software/DV mismatch | SPEC and reference model alignment. |
| Random seed escapes | Latent corner bugs | Multi-seed legal/corner/max random regression. |

### 15.2 Limitations

- Current plan is RTL simulation focused.
- Formal and STA are explicitly excluded unless requested.
- Performance metrics are observed in TB but are not sign-off thresholds unless later defined.
- Default closure targets the current 4x4 RTL configuration; 8x8 upgrade requires a new targeted closure pass.
- Software driver behavior is modeled by UVM sequences, not by a real CPU/driver stack.

## 16. Deliverables

| Deliverable | Path / Owner |
| ----------- | ------------ |
| RTL SPEC | `rtl/SPEC_EN.md`, `rtl/SPEC_CN.md` |
| Verification plan | `tb/doc/VERIFICATION_PLAN_V1.md` |
| Bug log | `tb/doc/bug_log.md` |
| Coverage waivers | `cov_waivers/` |
| Regression commands/results | `sim/run/*/log/run.log`, coverage reports |
| Testbench source | `tb/` |
| File list and Make targets | `script/filelist.f`, `Makefile` |

This plan is complete for the current RTL facts and should be updated whenever the RTL SPEC changes.
