# DUT Bug Log

## Naming Convention

```
BUG-YYYYMMDD-NNN-{MODULE}-WWH
     │         │    │        │
     │         │    │        └── Author: WWH
     │         │    └── Module: ACC / DMAW / DMAR / LOAD / FSM / REG / SPAD /
     │         │                STOR / CMPT / PP / TILE / TACC
     │         └── Sequence number (001-999)
     └── Discovery date
```

### Severity

| Level | Meaning |
|-------|---------|
| CRIT  | Functional dead-end: crash / hang / silent wrong output across all configs |
| MAJ   | Wrong output in specific config; workaround exists or partial impact |
| MIN   | Non-functional: perf counter / status / assertion-only / cosmetic |

### Module Abbreviations

| Code | Modules |
|------|---------|
| ACC  | mac_unit, pe, systolic_array, accumulator, post_process |
| DMAW | axi_write_dma, tensor_writer, dma_burst_splitter (write side) |
| DMAR | axi_read_dma, tensor_loader, dma_burst_splitter (read side) |
| LOAD | load_scheduler |
| FSM  | command_fsm |
| REG  | reg_file, region_checker |
| SPAD | scratchpad, scratchpad_ctrl |
| STOR | store_fsm |
| CMPT | compute_fsm |
| PP   | post_process_fsm |
| TILE | tile_count_fsm |
| BUFM | buffer_manager_fsm |
| TACC | tensor_accel_top (top-level integration / wiring) |
| TB   | UVM sequences and validation memory model integration |

---

## BUG-20260526-001-ACC-WWH: MAC accumulator truncated INT16 corner-data partial sums

### Status
Fixed

### Severity
MAJ

### Module
ACC

### First Found In
- Test case: `tensor_base_random_corner_data_test`
- Seed: `1` (also reproduced by seeds `2` and `3`)
- Simulation command: `make run TESTNAME=tensor_base_random_corner_data_test SEED=1 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=160s`
- Date: 2026-05-26

### Summary
Random corner-data testing exposed C mismatches for INT16 cases with large K and bias/ReLU enabled. The MAC path kept a 32-bit accumulator, so large INT16 corner values could wrap intermediate partial sums before post-processing.

### Expected Behavior
The DUT should accumulate all INT16 products across K without truncating partial sums to 32 bits before bias, ReLU, and final wrap/saturate processing.

### Actual Behavior
C values differed from the 64-bit reference model due to premature 32-bit truncation in the MAC accumulator.

### Root Cause
`mac_unit` accumulated products into a 32-bit register. INT16 products over large K can exceed the signed 32-bit range before final output conversion.

### Fix / Workaround
Widened internal accumulation path to 40 bits from MAC output through PE, systolic array, accumulator, top-level wiring, and post-process input. Final output remains 32 bits after bias/ReLU and wrap/saturate handling.

### Related Files
- RTL: `mac_unit.sv`, `pe.sv`, `systolic_array.sv`, `accumulator.sv`, `post_process.sv`, `tensor_accel_top.sv`
- Testbench: `tensor_base_random_corner_data_test.sv`
- Sequence: `tensor_random_corner_data_vseq.sv`, `tensor_random_legal_vseq.sv`

---

## BUG-20260526-002-TACC-WWH: Back-to-back and degenerate dimensions produce C mismatches

### Status
Fixed

### Severity
MAJ

### Module
ACC / TACC / TB

### First Found In
- Test case: `tensor_base_random_legal_test`
- Seed: `1`
- Simulation command: `make run TESTNAME=tensor_base_random_legal_test SEED=1 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=80s`
- Directed reproducer: `make run TESTNAME=tensor_base_degenerate_dims_test RUN_TIME=180s`
- Date: 2026-05-26

### Summary
Operations completed without DUT error status, but back-to-back operations and degenerate dimensions such as M=1, N<4, and narrow-column configurations produced C mismatches. After the RTL defects were fixed, some multi-case tests still failed because the validation memory retained bytes from the previous case.

### Expected Behavior
The DUT should match the reference for legal degenerate dimensions (e.g. M=1, N<4).

### Actual Behavior
C mismatches including `C[0,0] exp=15 act=0` (M=1,N=4,K=8 INT8), `C[0,0] exp=15 act=40` (M=1,N=8,K=8), and `C[0,0] exp=15 act=-2612` (M=1,N=1,K=8).

### Root Cause
Three independent issues contributed to the failures:

1. `accumulator.sv` ignored `clear_i` and `load_i`, so a new operation could reuse stale accumulation state.
2. The systolic array consumed registered row/column valid masks on the compute launch edge. The registers were updated on that same edge, so partial tiles could start with the preceding tile's masks.
3. The testbench repeatedly called SVT `write_num_byte` on the same A/B/C address ranges. In long multi-case sequences, shorter writes did not reliably replace all bytes observed by the slave memory model, creating false DUT mismatches from stale B data.

### Fix / Workaround
The accumulator now honors clear and load controls. The systolic launch cycle selects the current combinational row/column valid masks, then uses the registered masks for the remaining compute cycles. Test data preload, C poisoning, and C readback now use SVT `write_byte`/`read_byte` per byte so each reused address is deterministically overwritten. Temporary debug instrumentation was removed after diagnosis.

### Regression
- `tensor_base_rect_matrix_test`: passed 5/5 cases, `UVM_ERROR=0`, `UVM_FATAL=0`
- `tensor_base_degenerate_dims_test`: passed 31/31 cases, `UVM_ERROR=0`, `UVM_FATAL=0`
- `tensor_base_non_aligned_size_test`: passed 5/5 cases, `UVM_ERROR=0`, `UVM_FATAL=0`
- Build: `make -C tb/sim elab BUILD_NAME=mem_byte_fix`
- Run timeout: `RUN_TIME=180s`
- Date fixed: 2026-06-22

### Related Files
- RTL: `accumulator.sv`, `tensor_accel_top.sv`
- Testbench: `tensor_base_degenerate_dims_test.sv`
- Sequence: `tensor_degenerate_dims_vseq.sv`, `tensor_matmul_vseq.sv`

---

## BUG-20260520-001-DMAW-WWH: AXI write DMA rejected row-major C rows with 32-bit alignment

### Status
Fixed

### Severity
MAJ

### Module
DMAW

### First Found In
- Test case: `tensor_base_rect_matrix_test`
- Seed: `1`
- Simulation command: `make run BUILD_NAME=rect_matrix TESTNAME=tensor_base_rect_matrix_test RUN_TIME=120s`
- Date: 2026-05-20

### Summary
Row-major C storage places later rows at `C_BASE + 4 mod 8` when N is odd. `axi_write_dma` required 64-bit alignment and rejected these legal 32-bit aligned addresses.

### Expected Behavior
The DUT should write all C result rows correctly for legal 32-bit aligned C addresses.

### Actual Behavior
`ERR_AXI_WRITE_ERROR` on rectangular cases (M=13,N=7,K=9 and M=64,N=1,K=5).

### Root Cause
`axi_write_dma` assumed write start addresses were aligned to the AXI beat size. C rows are only 32-bit aligned because each element is 32 bits and row stride is `N * 4`.

### Fix / Workaround
`axi_write_dma.sv` now aligns AWADDR down to 8-byte boundary, tracks byte offset, fetches corresponding scratchpad words, and drives shifted `WSTRB` lanes.

### Related Files
- RTL: `axi_write_dma.sv`, `tensor_writer.sv`, `tensor_accel_top.sv`
- Testbench: `tensor_base_rect_matrix_test.sv`

---

## BUG-20260520-002-DMAR-LOAD-WWH: Aligned row reads overlapped scratchpad rows for narrow tiles

### Status
Fixed

### Severity
MAJ

### Module
DMAR / LOAD / TACC

### First Found In
- Test case: `tensor_base_rect_matrix_test`
- Seed: `1`
- Simulation command: `make run BUILD_NAME=rect_matrix TESTNAME=tensor_base_rect_matrix_test RUN_TIME=120s`
- Date: 2026-05-20

### Summary
After fixing C write alignment, rectangular cases still produced C mismatches. `tensor_loader` aligns external row reads down to 8-byte boundaries and extends `byte_len` by the leading offset. The scratchpad row stride did not reserve space for those extra alignment bytes, causing adjacent loaded rows to overlap.

### Expected Behavior
The loader should preserve each A/B tile row independently in scratchpad.

### Actual Behavior
C mismatches for non-multiple and skinny rectangular cases (M=13,N=7,K=9 and M=64,N=1,K=5).

### Root Cause
Scratchpad row stride used `ceil(row_bytes, 8)` without reserving space for leading alignment bytes introduced by `tensor_loader`.

### Fix / Workaround
Updated `load_scheduler.sv` and `tensor_accel_top.sv` to use `(row_bytes + 14) & 32'hffff_fff8`, equivalent to `row_bytes + 7` leading alignment bytes rounded up to 8-byte boundary.

### Related Files
- RTL: `load_scheduler.sv`, `tensor_accel_top.sv`, `tensor_loader.sv`, `axi_read_dma.sv`
- Testbench: `tensor_base_rect_matrix_test.sv`

---

## BUG-20260520-003-DMAW-WWH: AXI write DMA reported 4KB crossing on legal partial C tile writes

### Status
Fixed

### Severity
MAJ

### Module
DMAW

### First Found In
- Test case: `tensor_base_non_aligned_size_test`
- Seed: `1`
- Simulation command: `make run BUILD_NAME=non_aligned_size TESTNAME=tensor_base_non_aligned_size_test RUN_TIME=180s`
- Date: 2026-05-20

### Summary
Dense row-major C storage can place a tile-row write such that the aligned 64-bit AXI burst spans a 4KB boundary. `axi_write_dma` treated this as a hard error instead of splitting the write into page-contained bursts.

### Expected Behavior
The DUT should auto-split a legal word-aligned C write into multiple AXI bursts when the aligned transfer would cross a 4KB boundary.

### Actual Behavior
`ERR_BURST_CROSS_4KB` on the M=63,N=61,K=59 case after partial C writeback. First four smaller cases passed.

### Root Cause
`axi_write_dma` used the burst splitter with 4KB auto-splitting disabled and surfaced `cross_4kb_o` directly as a terminal error.

### Fix / Workaround
`axi_write_dma.sv` now enables 4KB-aware burst splitting, tracks segment address and remaining byte count, and issues additional AW/W/B segments after each page-limited burst.

### Related Files
- RTL: `axi_write_dma.sv`, `dma_burst_splitter.sv`, `tensor_writer.sv`
- Testbench: `tensor_base_non_aligned_size_test.sv`

---

## BUG-20260520-004-ACC-WWH: Bulk bias preload caused false partial-K mismatches

### Status
Fixed

### Severity
MAJ

### Module
TB

### First Found In
- Test case: `tensor_base_saturation_test` development stimulus with `M=2, N=4, K=2`
- Seed: `1`
- Simulation command: `make run BUILD_NAME=saturation_tests TESTNAME=tensor_base_saturation_test RUN_TIME=120s`
- Date: 2026-05-20

### Summary
Bias-enabled partial-K cases produced column-constant C mismatches and initially appeared to be an accumulator or post-process defect. The same signature later reproduced in `tensor_base_random_legal_test` seed 3 at `M=20, N=2, K=2`.

### Expected Behavior
For `POST_BIAS`, each C element should be `accumulate + bias`, independent of whether the K tile is full or partial.

### Actual Behavior
Observed C values matched bias-only results with no contribution from the A/B accumulation. Operation completed without error.

### Root Cause
Bias preload still used the SVT `write_num_byte` backdoor API after A/B/C preload had moved to deterministic byte writes. A controlled comparison using identical matrices and bias values failed with bulk bias preload and passed with per-byte preload. The RTL partial-K, bias, ReLU, and saturation paths were correct.

### Fix / Workaround
Bias preload now uses `write_byte` for every byte in directed bias, saturation, and random legal sequences. Added `tensor_base_partial_k_postop_isolation_test` covering single and multi-M-tile operation, partial/full K, all four post-op modes, and both saturation modes.

### Regression
- `tensor_base_partial_k_postop_isolation_test`: passed 10/10 cases
- `tensor_base_random_legal_test`, seed `3`, `RAND_ITERS=5`: passed 5/5 iterations
- All runs: `UVM_ERROR=0`, `UVM_FATAL=0`
- Date fixed: 2026-06-22

### Related Files
- Testbench: `tensor_base_partial_k_postop_isolation_test.sv`
- Sequences: `tensor_partial_k_postop_vseq.sv`, `tensor_bias_vseq.sv`, `tensor_saturation_vseq.sv`, `tensor_random_legal_vseq.sv`

---

## BUG-20260525-001-FSM-REG-WWH: IRQ_STATUS W1C could not clear IRQ while DUT remained in DONE

### Status
Fixed

### Severity
MAJ

### Module
FSM / REG

### First Found In
- Test case: `tensor_base_irq_test`
- Seed: `1`
- Simulation command: `make run TESTNAME=tensor_base_irq_test BUILD_NAME=irq_tests RUN_TIME=60s`
- Date: 2026-05-25

### Summary
Writing `IRQ_STATUS[0]=1` did not clear the IRQ condition after a completed operation. `STATUS.irq`, `IRQ_STATUS[0]`, and the external `irq` pin all remained asserted while the DUT stayed in `ST_DONE`.

### Expected Behavior
`IRQ_STATUS[0]` W1C should clear `STATUS.irq` and deassert `irq` without requiring `CTRL.clear_done`.

### Actual Behavior
`STATUS.irq` remained set after W1C write. `CTRL.clear_done` path worked correctly.

### Root Cause
`command_fsm` level-triggered IRQ assertion from terminal states. As long as the FSM stayed in `ST_DONE`, `irq_en_i` caused `status_q.irq` to be reasserted every cycle.

### Fix / Workaround
IRQ assertion changed to edge-triggered on terminal-state entry: `state_q != ST_DONE && state_d == ST_DONE`. Clear pulses have highest priority.

### Related Files
- RTL: `command_fsm.sv`, `reg_file.sv`, `tensor_accel_top.sv`
- Testbench: `tensor_base_irq_test.sv`, `tensor_err_irq_on_error_test.sv`

---

## BUG-20260525-002-REG-WWH: Region checker rejected legal word-aligned C writes

### Status
Fixed

### Severity
MAJ

### Module
REG / DMAW

### First Found In
- Test case: `tensor_base_write_unaligned_test`
- Seed: `1`
- Simulation command: `make run TESTNAME=tensor_base_write_unaligned_test BUILD_NAME=write_unaligned RUN_TIME=30s`
- Date: 2026-05-25

### Summary
`C_BASE=0x0003_0004` is 32-bit aligned but not 64-bit AXI-beat aligned. The write DMA supports this by aligning AWADDR down and driving shifted WSTRB, but `region_checker` still rejected `C_BASE % 8 != 0`.

### Expected Behavior
`C_BASE` should be allowed when aligned to the 32-bit C element size.

### Actual Behavior
Configuration rejected before the store path could exercise unaligned-lane logic.

### Root Cause
`region_checker` applied the read-DMA AXI-beat alignment requirement to `C_BASE`. C stores write 32-bit words and the write DMA supports offset WSTRB.

### Fix / Workaround
`region_checker.sv` now requires A, B, Bias base addresses to remain AXI-beat aligned, while `C_BASE` only needs 32-bit word alignment.

### Related Files
- RTL: `region_checker.sv`, `axi_write_dma.sv`
- Testbench: `tensor_base_write_unaligned_test.sv`

---

## BUG-20260514-001-TACC-WWH: Zero C output and AXI VIP X/Z errors (earliest bring-up)

### Status
Fixed

### Severity
CRIT

### Module
TACC / DMAR / DMAW / ACC

### First Found In
- Test case: `tensor_base_int8_4x4_test`, `tensor_base_int16_4x4_test`
- Date: 2026-05-14

### Summary
Initial bring-up: all-zero C output, AXI VIP X/Z on unused sideband and WDATA, and read DMA asserting done before the final scratchpad write completed.

### Root Cause
1. Compute operands `a_vec`, `b_vec`, `bias_vec` tied to zero in `tensor_accel_top.sv`
2. Post-process output not written into C scratchpad before store
3. `axi_read_dma` asserted done before final accepted read beat drained into scratchpad
4. Unused AXI sideband fields left floating causing VIP X/Z

### Fix / Workaround
1. Capture loaded A/B/bias words into local operand tiles; drive systolic array from tiles
2. Add post-process writeback phase before store
3. Delay read-DMA done until final scratchpad write completes
4. Tie off unused AXI sideband fields in `top_tb.sv`

### Related Files
- RTL: `tensor_accel_top.sv`, `axi_read_dma.sv`, `axi_write_dma.sv`
- Testbench: `top_tb.sv`

---

## BUG-20260622-001-DMAR-WWH: AXI read errors were missed on the direct receive path

### Status
Fixed

### Severity
MAJ

### Module
DMAR

### First Found In
- Test case: `tensor_err_axi_read_slverr_test`
- Seed: `1`
- Simulation command: `make -C tb/sim run TESTNAME=tensor_err_axi_read_slverr_test BUILD_NAME=fresh_regression RUN_TIME=180s`
- Date: 2026-06-22

### Summary
Injected SLVERR/DECERR responses on A and B reads were accepted by AXI, but the operation completed with `STATUS.done=1` instead of entering the error state.

### Root Cause
`axi_read_dma` checked `RRESP` only when an accepted R beat was pushed into the read FIFO. A beat consumed through the no-backpressure `rbuf_direct` path bypassed that condition, so its error response was lost.

### Fix / Workaround
Sample `RRESP` on every `RVALID && RREADY` handshake. This covers both direct and FIFO-buffered receive paths without changing the data buffering behavior.

### Regression
- `tensor_err_axi_read_slverr_test`: passed A SLVERR, B DECERR, and Bias SLVERR cases
- `tensor_err_axi_read_bias_error_test`: passed
- `tensor_base_int8_4x4_test`: passed normal read path
- All runs: `UVM_ERROR=0`, `UVM_FATAL=0`

### Related Files
- RTL: `axi_read_dma.sv`
- Testbench: `tensor_axi_read_error_vseq.sv`

---

## Open Bug Summary

| Bug ID | Severity | Module | Title |
|--------|----------|--------|-------|

## Closed Bug Summary

| Bug ID | Severity | Module | Title |
|--------|----------|--------|-------|
| BUG-20260520-004-ACC-WWH | MAJ | TB | Bulk bias preload caused false partial-K mismatches |
| BUG-20260622-001-DMAR-WWH | MAJ | DMAR | AXI read errors were missed on the direct receive path |
| BUG-20260526-002-TACC-WWH | MAJ | ACC/TACC/TB | Back-to-back and degenerate dimensions produce C mismatches |
| BUG-20260526-001-ACC-WWH | MAJ | ACC | MAC accumulator truncated INT16 corner-data partial sums |
| BUG-20260520-001-DMAW-WWH | MAJ | DMAW | AXI write DMA rejected 32-bit aligned C row addresses |
| BUG-20260520-002-DMAR-LOAD-WWH | MAJ | DMAR/LOAD/TACC | Aligned row reads overlapped scratchpad rows |
| BUG-20260520-003-DMAW-WWH | MAJ | DMAW | 4KB crossing reported as error on legal C writes |
| BUG-20260525-001-FSM-REG-WWH | MAJ | FSM/REG | IRQ W1C could not clear while DUT in DONE |
| BUG-20260525-002-REG-WWH | MAJ | REG/DMAW | Region checker rejected legal 32-bit C writes |
| BUG-20260514-001-TACC-WWH | CRIT | TACC/DMAR/DMAW/ACC | Zero C output and VIP X/Z (bring-up) |
