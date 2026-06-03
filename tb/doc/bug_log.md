# DUT Bug Log

## BUG-20260526-001: MAC accumulator truncated INT16 corner-data partial sums

### Status
Fixed

### Severity
Major

### First Found In
- Test case: `tensor_base_random_corner_data_test`
- Seed: `1` (also reproduced by seeds `2` and `3`)
- Simulation command: `make run TESTNAME=tensor_base_random_corner_data_test SEED=1 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=160s`
- Git commit: Uncommitted working tree
- Date: 2026-05-26

### Summary
Random corner-data testing exposed C mismatches for INT16 cases with large K and bias/ReLU enabled. The test reference uses wide accumulation and truncates only after final post-processing, which matches the intended MAC behavior.

### Expected Behavior
The DUT should accumulate all INT16 products across K without truncating partial sums to 32 bits before bias, ReLU, and final wrap/saturate processing.

### Actual Behavior
The MAC path kept a 32-bit accumulator, so large INT16 corner values could wrap intermediate partial sums before post-processing. The final C values then differed from the 64-bit reference model.

### Reproduction Steps
1. Build the simulation with `make elab`.
2. Run `make run TESTNAME=tensor_base_random_corner_data_test SEED=1 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=160s`.
3. Observe C mismatches before the accumulator-width fix on INT16 corner-data cases with large K and bias/ReLU.

### Failure Evidence
- Log message: C mismatch reports from `tensor_random_corner_data_vseq` before the fix.
- Assertion failure: None.
- Scoreboard mismatch: Matrix checks are performed directly in the sequence; scoreboard reported `compare_count=0 mismatch_count=0`.
- Waveform path: Not captured for this debug pass.
- Relevant signal observations: `mac_unit.acc_o` and downstream accumulator/post-process ports were 32 bits while the reference accumulated in a wider integer type.

### Initial Suspected Root Cause
The corner-data reference model had already been corrected to use wide accumulation, leaving the DUT MAC accumulator width as the likely source of the INT16 large-K mismatch.

### Debug Process
- Step 1:
  - Action: Inspected `tensor_random_corner_data_vseq` and the parent random legal reference model.
  - Observation: The corner-data sequence reuses the parent golden calculation, which performs wide accumulation and only wraps/clamps after bias/ReLU.
  - Conclusion: The golden model behavior is consistent with the intended hardware MAC behavior.
- Step 2:
  - Action: Traced the RTL accumulation path through `mac_unit`, `pe`, `systolic_array`, `accumulator`, `post_process`, and `tensor_accel_top`.
  - Observation: The MAC accumulator and post-process input were 32 bits, truncating partial sums before final output processing.
  - Conclusion: The mismatch was a DUT accumulator-width bug.
- Step 3:
  - Action: Widened the internal accumulation path to 40 bits and kept final output conversion in `post_process`.
  - Observation: The previously failing corner-data seeds pass.
  - Conclusion: The widened accumulation path fixes the confirmed DUT issue.

### Root Cause
`mac_unit` accumulated products into a 32-bit register and propagated that truncated value through the PE array and post-process path. INT16 products over large K can exceed the signed 32-bit range before final output conversion.

### Fix / Workaround
The internal accumulator path is now 40 bits from MAC output through PE, systolic array, accumulator, top-level wiring, and post-process input. The final output remains 32 bits after bias/ReLU and wrap/saturate handling.

### Regression Result
After the fix, the following commands passed with 0 UVM errors and 0 UVM fatals:

* `make elab`
* `make run TESTNAME=tensor_base_random_corner_data_test SEED=1 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=160s`
* `make run TESTNAME=tensor_base_random_corner_data_test SEED=2 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=160s`
* `make run TESTNAME=tensor_base_random_corner_data_test SEED=3 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=160s`

### Related Files

* RTL: `rtl/common/mac_unit.sv`, `rtl/compute/pe.sv`, `rtl/compute/systolic_array.sv`, `rtl/compute/accumulator.sv`, `rtl/compute/post_process.sv`, `rtl/top/tensor_accel_top.sv`
* Testbench: `tb/tests/random_tests/tensor_base_random_corner_data_test.sv`
* Sequence: `tb/seq_lib/random_tests/tensor_random_corner_data_vseq.sv`, `tb/seq_lib/random_tests/tensor_random_legal_vseq.sv`
* Scoreboard: `tb/env/tensor_accel_scoreboard.sv`
* Assertion: None.
* Coverage: Not collected; default `COV=0`.
* Waveform: Not generated; default `FSDB=0`.
* Log: `tb/sim/sim/run/tensor_base_random_corner_data_test_seed_1/log/run.log`

### Notes

This fix does not change the architectural 32-bit C output format. It only prevents premature internal truncation before final post-processing.

## BUG-20260526-002: Degenerate M/N dimensions produce C mismatches

### Status
Open

### Severity
Major

### First Found In
- Test case: `tensor_base_random_legal_test`
- Seed: `1`
- Simulation command: `make run TESTNAME=tensor_base_random_legal_test SEED=1 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=80s`
- Directed reproducer: `make run TESTNAME=tensor_base_degenerate_dims_test RUN_TIME=180s`
- Git commit: Uncommitted working tree
- Date: 2026-05-26

### Summary
While verifying the randomization-constraint change, `tensor_base_random_legal_test` seed 1 reached a deterministic data mismatch on iteration 3. A directed degenerate-dimension test now reproduces broader failures for single-row and narrow-column configurations, including POST_NONE cases.

### Expected Behavior
The DUT should match the sequence reference model for legal degenerate dimensions such as `M=1` and `N<4`, independent of precision and post-op.

### Actual Behavior
The operations complete without DUT error status, but C elements mismatch the sequence reference. The directed reproducer reports 170 UVM errors after the timeout floor was raised to avoid premature polling failures.

### Reproduction Steps
1. Build the simulation with `make elab`.
2. Run `make run TESTNAME=tensor_base_random_legal_test SEED=1 USER_SIM_OPTS=+RAND_ITERS=3 RUN_TIME=80s`.
3. Observe iteration 3 mismatch for `M=1 N=13 K=8 precision=0 post_op=3 sat=0`.
4. Run `make run TESTNAME=tensor_base_degenerate_dims_test RUN_TIME=180s`.
5. Observe directed mismatches on degenerate cases such as `M=1 N=4 K=8`, `M=1 N=13 K=8`, `M=4 N=1 K=4`, and `M=1 N=1 K=8`.

### Failure Evidence
- Log message: `Random legal case M=1 N=13 K=8 precision=0 post_op=3 sat=0 burst_len=4 A=0x000ac000 B=0x000dc000 C=0x000d4000 Bias=0x0002c000`
- Assertion failure: None.
- Scoreboard mismatch: Matrix checks are performed directly in the sequence; scoreboard reported `compare_count=0 mismatch_count=0`.
- Waveform path: Not captured for this debug pass.
- Relevant signal observations: The random run reported C mismatches including `C[0,0] exp=21377 act=3924`, `C[0,1] exp=4609 act=0`, and `C[0,10] exp=0 act=1093`. The directed run reported mismatches including `M=1 N=4 K=8 C[0,0] exp=15 act=0`, `M=1 N=13 K=8 C[0,0] exp=15 act=40`, and `M=1 N=1 K=8 C[0,0] exp=15 act=-10182`.

### Initial Suspected Root Cause
Under debug. The failure appears separate from the randomization solver issue and from the INT16 accumulator-width issue fixed in `BUG-20260526-001`.

### Debug Process
- Step 1:
  - Action: Rebuilt after simplifying the K constraint and widening the MAC accumulator path.
  - Observation: `make elab` passed.
  - Conclusion: The mismatch is not an elaboration or stale-binary issue.
- Step 2:
  - Action: Re-ran `tensor_base_random_legal_test` seed 1 with `RAND_ITERS=3`.
  - Observation: Iterations 1 and 2 completed, then iteration 3 failed with the same INT8 `M=1 N=13 K=8` bias/ReLU mismatch.
  - Conclusion: This is a reproducible datapath/reference mismatch exposed by the random legal test.
- Step 3:
  - Action: Added `tensor_base_degenerate_dims_test` and `tensor_degenerate_dims_vseq` to sweep fixed `M=1`, `N<4`, and extreme degenerate dimensions.
  - Observation: The directed test reproduced mismatches without randomization, including POST_NONE cases.
  - Conclusion: The issue is a DUT degenerate-dimension datapath defect, not a random test framework or post-op-only issue.

### Root Cause
Under debug.

### Fix / Workaround
No DUT fix has been applied yet. This issue should be debugged separately from the randomization-constraint change.

### Regression Result
Open. The random reproducer still fails with 9 UVM errors after the accumulator-width fix. The directed reproducer fails with 170 UVM errors.

### Related Files

* RTL: `rtl/top/tensor_accel_top.sv`, `rtl/compute/accumulator.sv`, `rtl/compute/post_process.sv`, `rtl/dma/tensor_loader.sv`
* Testbench: `tb/tests/random_tests/tensor_base_random_legal_test.sv`, `tb/tests/directed_tests/tensor_base_degenerate_dims_test.sv`
* Sequence: `tb/seq_lib/random_tests/tensor_random_legal_vseq.sv`, `tb/seq_lib/directed_tests/tensor_degenerate_dims_vseq.sv`
* Scoreboard: `tb/env/tensor_accel_scoreboard.sv`
* Assertion: None.
* Coverage: Not collected; default `COV=0`.
* Waveform: Not generated; default `FSDB=0`.
* Log: `tb/sim/sim/run/tensor_base_random_legal_test_seed_1/log/run.log`, `tb/sim/sim/run/tensor_base_degenerate_dims_test_seed_1/log/run.log`

### Notes

This failure is not a randomization failure. The directed reproducer removes randomization from the failing dimensions.

## BUG-20260520-001: AXI write DMA rejected row-major C rows with 32-bit alignment

### Status
Fixed

### Severity
Major

### First Found In
- Test case: `tensor_base_rect_matrix_test`
- Seed: `1`
- Simulation command: `make run BUILD_NAME=rect_matrix TESTNAME=tensor_base_rect_matrix_test RUN_TIME=120s`
- Git commit: Uncommitted working tree
- Date: 2026-05-20

### Summary
The rectangular matrix test exposed AXI write failures when C row starts were 32-bit aligned but not 64-bit aligned. Row-major C storage uses 32-bit result words, so matrices with odd `N` can place later rows at `C_BASE + 4 mod 8`.

### Expected Behavior
The DUT should write all C result rows correctly for legal 32-bit aligned C addresses, including row-major matrices where `N` is not even.

### Actual Behavior
The DUT reported `ERR_AXI_WRITE_ERROR` and left portions of C memory unwritten or mismatched for rectangular cases such as `M=13, N=7, K=9` and `M=64, N=1, K=5`.

### Reproduction Steps
1. Build the simulation with `make elab BUILD_NAME=rect_matrix`.
2. Run `make run BUILD_NAME=rect_matrix TESTNAME=tensor_base_rect_matrix_test RUN_TIME=120s`.
3. Observe `ERR_AXI_WRITE_ERROR` and C matrix mismatches before the fix.

### Failure Evidence
- Log message: `Expected done completion, got status=0x00000004 error=ERR_AXI_WRITE_ERROR`
- Assertion failure: None.
- Scoreboard mismatch: Matrix checks are performed directly in the test; scoreboard reported `compare_count=0 mismatch_count=0`.
- Waveform path: Not captured for this debug pass.
- Relevant signal observations: C row write addresses can be 32-bit aligned but not 64-bit aligned when `N` is odd.

### Initial Suspected Root Cause
`axi_write_dma` required the AXI write address to be aligned to the 64-bit AXI data beat width and did not generate shifted `WSTRB`/`WDATA` for 32-bit row starts.

### Debug Process
- Step 1:
  - Action: Added `tensor_base_rect_matrix_test` with independent M/N/K cases.
  - Observation: The first two even-row-stride cases passed; failures started with odd `N` and skinny matrix boundary cases.
  - Conclusion: The issue was related to row-major C addressing and tile-row writeback, not the basic square datapath.
- Step 2:
  - Action: Inspected `tensor_accel_top.sv`, `tensor_writer.sv`, and `axi_write_dma.sv`.
  - Observation: C writeback is issued one C row at a time, but `axi_write_dma` passed `addr_i` directly to the burst splitter, which requires 64-bit alignment.
  - Conclusion: Legal 32-bit C row addresses were rejected or mishandled by the write DMA.
- Step 3:
  - Action: Updated `axi_write_dma` to align AWADDR down to the 64-bit beat and generate active byte strobes from the original 32-bit row address.
  - Observation: `ERR_AXI_WRITE_ERROR` no longer appeared in `tensor_base_rect_matrix_test`.
  - Conclusion: The write transport alignment defect was fixed.

### Root Cause
`axi_write_dma` assumed write start addresses were aligned to the AXI beat size. C result rows are only guaranteed 32-bit alignment because each C element is 32 bits and row-major row stride is `N * 4`.

### Fix / Workaround
`axi_write_dma.sv` now aligns the AXI write address down to an 8-byte boundary, tracks the original byte offset, fetches the corresponding scratchpad words, and drives shifted `WSTRB` lanes for partial/offset beats.

### Regression Result
After this fix and the related read-row stride fix in `BUG-20260520-002`, `tensor_base_rect_matrix_test` passed with 0 UVM errors. `tensor_base_32x32_test` also passed as a square regression check.

### Related Files

* RTL: `rtl/dma/axi_write_dma.sv`, `rtl/dma/tensor_writer.sv`, `rtl/top/tensor_accel_top.sv`
* Testbench: `tb/tests/tensor_base_rect_matrix_test.sv`, `tb/tests/tensor_accel_tests.svh`
* Sequence: `tb/seq_lib/tensor_common_vseqs.sv`
* Scoreboard: `tb/env/tensor_accel_scoreboard.sv`
* Assertion: None.
* Coverage: Not collected; default `COV=0`.
* Waveform: Not generated; default `FSDB=0`.
* Log: `tb/sim/sim/run/tensor_base_rect_matrix_test_seed_1/log/run.log`

### Notes

This fix supports word-aligned C writes on a 64-bit AXI data bus. Byte- or halfword-aligned C writes remain illegal for 32-bit C elements.

## BUG-20260520-002: Aligned row reads overlapped scratchpad rows for narrow rectangular tiles

### Status
Fixed

### Severity
Major

### First Found In
- Test case: `tensor_base_rect_matrix_test`
- Seed: `1`
- Simulation command: `make run BUILD_NAME=rect_matrix TESTNAME=tensor_base_rect_matrix_test RUN_TIME=120s`
- Git commit: Uncommitted working tree
- Date: 2026-05-20

### Summary
After the C write alignment issue was fixed, rectangular cases still produced C mismatches without AXI write errors. The remaining failures came from aligned row reads overwriting adjacent scratchpad row slots when the external row start was not 64-bit aligned.

### Expected Behavior
The loader should preserve each A/B tile row independently in scratchpad, including rows whose external row start address is not aligned to an 8-byte AXI beat.

### Actual Behavior
For non-multiple and skinny rectangular cases such as `M=13, N=7, K=9` and `M=64, N=1, K=5`, C results mismatched the row-major reference even though the operation completed without AXI errors.

### Reproduction Steps
1. Apply only the `axi_write_dma` C write alignment fix.
2. Build with `make elab BUILD_NAME=rect_matrix`.
3. Run `make run BUILD_NAME=rect_matrix TESTNAME=tensor_base_rect_matrix_test RUN_TIME=120s`.
4. Observe remaining C mismatches with no `ERR_AXI_WRITE_ERROR`.

### Failure Evidence
- Log message: C mismatch messages such as `case[2] M=13 N=7 K=9 C[0,1] mismatch`.
- Assertion failure: None.
- Scoreboard mismatch: Matrix checks are performed directly in the test; scoreboard reported `compare_count=0 mismatch_count=0`.
- Waveform path: Not captured for this debug pass.
- Relevant signal observations: `tensor_loader` aligns external row reads down to 8-byte boundaries and extends `byte_len` by the leading alignment offset.

### Initial Suspected Root Cause
The row-mode loader scratchpad stride was only `ceil(row_bytes, 8)`, which is too small when an aligned external read includes leading bytes from the previous AXI beat.

### Debug Process
- Step 1:
  - Action: Re-ran `tensor_base_rect_matrix_test` after fixing C write alignment.
  - Observation: AXI write errors disappeared, but C data mismatches remained.
  - Conclusion: The remaining defect was upstream of C writeback.
- Step 2:
  - Action: Inspected `tensor_loader.sv`, `axi_read_dma.sv`, `load_scheduler.sv`, and the duplicate top-level row stride calculations.
  - Observation: Row-mode reads use `dma_addr = row_ext_addr - row_align_bytes` and `dma_byte_len = row_bytes + row_align_bytes`.
  - Conclusion: A row starting at byte offset 7 with `row_bytes=4` can consume 11 bytes, requiring two AXI beats and more scratchpad spacing than `ceil(row_bytes, 8)`.
- Step 3:
  - Action: Increased A/B scratchpad row stride calculations to cover worst-case leading alignment: `ceil(row_bytes + 7, 8)`.
  - Observation: `tensor_base_rect_matrix_test` passed all five requested cases with 0 UVM errors.
  - Conclusion: Scratchpad row overlap was the confirmed source of the remaining mismatches.

### Root Cause
The scratchpad row stride for aligned row reads did not include the possible leading alignment bytes introduced by `tensor_loader`. Adjacent loaded rows could overlap in scratchpad for narrow or unaligned row-major tiles.

### Fix / Workaround
Updated both `load_scheduler.sv` and `tensor_accel_top.sv` to calculate A/B scratchpad row stride as `(row_bytes + 14) & 32'hffff_fff8`, equivalent to reserving enough space for `row_bytes + 7` leading-alignment bytes rounded up to an 8-byte boundary.

### Regression Result
`tensor_base_rect_matrix_test` passed with 0 UVM errors after the stride fix. `tensor_base_32x32_test` also passed as a regression check for the existing square-tile path.

### Related Files

* RTL: `rtl/control/load_scheduler.sv`, `rtl/top/tensor_accel_top.sv`, `rtl/dma/tensor_loader.sv`, `rtl/dma/axi_read_dma.sv`
* Testbench: `tb/tests/tensor_base_rect_matrix_test.sv`, `tb/tests/tensor_accel_tests.svh`
* Sequence: `tb/seq_lib/tensor_common_vseqs.sv`
* Scoreboard: `tb/env/tensor_accel_scoreboard.sv`
* Assertion: None.
* Coverage: Not collected; default `COV=0`.
* Waveform: Not generated; default `FSDB=0`.
* Log: `tb/sim/sim/run/tensor_base_rect_matrix_test_seed_1/log/run.log`

### Notes

This issue specifically affects rectangular and partial-tile row-major accesses. Square matrix tests with naturally aligned 4-wide rows did not expose it.

## BUG-20260520-003: AXI write DMA reported 4KB crossing on legal partial C tile writes

### Status
Fixed

### Severity
Major

### First Found In
- Test case: `tensor_base_non_aligned_size_test`
- Seed: `1`
- Simulation command: `make run BUILD_NAME=non_aligned_size TESTNAME=tensor_base_non_aligned_size_test RUN_TIME=180s`
- Git commit: Uncommitted working tree
- Date: 2026-05-20

### Summary
The non-aligned size test exposed a C writeback failure on the large `M=63, N=61, K=59` case. Dense row-major C storage can place a 4-element tile-row write such that the aligned 64-bit AXI burst spans a 4KB boundary.

### Expected Behavior
The DUT should split a legal word-aligned C write into multiple AXI bursts when the aligned AXI transfer would otherwise cross a 4KB boundary.

### Actual Behavior
The DUT reported `ERR_BURST_CROSS_4KB` and left the remaining C matrix entries poisoned. The first four smaller non-aligned cases passed; the large case failed after partial C writeback.

### Reproduction Steps
1. Build the simulation with `make elab BUILD_NAME=non_aligned_size`.
2. Run `make run BUILD_NAME=non_aligned_size TESTNAME=tensor_base_non_aligned_size_test RUN_TIME=180s`.
3. Observe `ERR_BURST_CROSS_4KB` and C mismatches in the `M=63, N=61, K=59` case before the fix.

### Failure Evidence
- Log message: `Expected done completion, got status=0x00000004 error=ERR_BURST_CROSS_4KB`
- Assertion failure: None.
- Scoreboard mismatch: Matrix checks are performed directly in the test; scoreboard reported `compare_count=0 mismatch_count=0`.
- Waveform path: Not captured for this debug pass.
- Relevant signal observations: A 32-bit aligned C tile-row write can start near the end of a 4KB page while `axi_write_dma` aligns AWADDR down to the 64-bit AXI beat.

### Initial Suspected Root Cause
`axi_write_dma` treated any aligned AXI write crossing a 4KB boundary as an error instead of splitting the write into legal page-contained bursts.

### Debug Process
- Step 1:
  - Action: Added `tensor_base_non_aligned_size_test` with non-multiple M/N/K dimensions and poisoned input/C guard regions.
  - Observation: Cases `1x1x1`, `3x5x7`, `5x4x6`, and `4x5x6` passed; `63x61x59` failed with `ERR_BURST_CROSS_4KB`.
  - Conclusion: The failure required a larger dense C footprint that crossed multiple 4KB pages.
- Step 2:
  - Action: Inspected `dma_burst_splitter.sv`, `tensor_writer.sv`, and `axi_write_dma.sv`.
  - Observation: `axi_write_dma` used the burst splitter with 4KB auto-splitting disabled and surfaced `cross_4kb_o` directly to the command FSM.
  - Conclusion: Legal C writebacks were being converted into terminal DUT errors at 4KB page edges.
- Step 3:
  - Action: Updated `axi_write_dma` to keep current address, remaining byte count, and scratchpad offset, then issue another AW/W/B segment after a page-limited burst completes.
  - Observation: `tensor_base_non_aligned_size_test` passed with 0 UVM errors.
  - Conclusion: Write-side 4KB burst splitting fixed the large non-aligned C writeback failure.

### Root Cause
The write DMA did not support splitting a single logical C writeback across AXI's 4KB burst boundary. This was exposed by dense row-major matrices whose tile-row writes can start at offsets near the end of a 4KB page.

### Fix / Workaround
`axi_write_dma.sv` now enables 4KB-aware burst splitting, tracks the active segment address and remaining byte count, advances the scratchpad offset after each completed segment, and only reports transport errors for invalid alignment or write responses.

### Regression Result
`tensor_base_non_aligned_size_test` passed with 0 UVM errors after the fix. `tensor_base_rect_matrix_test` and `tensor_base_32x32_test` also passed as focused regressions.

### Related Files

* RTL: `rtl/dma/axi_write_dma.sv`, `rtl/dma/dma_burst_splitter.sv`, `rtl/dma/tensor_writer.sv`
* Testbench: `tb/tests/tensor_base_non_aligned_size_test.sv`, `tb/tests/tensor_accel_tests.svh`
* Sequence: `tb/seq_lib/tensor_common_vseqs.sv`
* Scoreboard: `tb/env/tensor_accel_scoreboard.sv`
* Assertion: None.
* Coverage: Not collected; default `COV=0`.
* Waveform: Not generated; default `FSDB=0`.
* Log: `tb/sim/sim/run/tensor_base_non_aligned_size_test_seed_1/log/run.log`

### Notes

The read DMA still reports 4KB crossings as errors. This bug covered the writeback path exercised by dense C tile-row stores.

## BUG-20260520-004: POST_BIAS partial-K tile produced bias-only results

### Status
Open

### Severity
Major

### First Found In
- Test case: `tensor_base_saturation_test` development stimulus with `M=2, N=4, K=2`
- Seed: `1`
- Simulation command: `make run BUILD_NAME=saturation_tests TESTNAME=tensor_base_saturation_test RUN_TIME=120s`
- Git commit: Uncommitted working tree
- Date: 2026-05-20

### Summary
While developing saturation coverage, a directed `POST_BIAS` case with a partial K tile (`K=2`) produced C values equal to the programmed bias values instead of `accumulate + bias`. The final committed saturation test uses a full `4x4x4` tile to isolate saturation behavior, but the partial-K biased behavior remains a suspected DUT defect.

### Expected Behavior
For `POST_BIAS`, the DUT should compute each C element as the matrix accumulation result plus the column bias, independent of whether the K tile is full or partial.

### Actual Behavior
For the `M=2, N=4, K=2` directed case, the observed C values matched the bias column values with no contribution from the A/B accumulation. The operation completed without a fatal error.

### Reproduction Steps
1. Use the saturation stimulus with dimensions `M=2, N=4, K=2`, `POST_OP=POST_BIAS`, and both `SAT_SATURATE` and `SAT_WRAP` modes.
2. Build with `make elab BUILD_NAME=saturation_tests`.
3. Run `make run BUILD_NAME=saturation_tests TESTNAME=tensor_base_saturation_test RUN_TIME=120s`.
4. Observe C mismatches where the actual values equal the bias-only result.

### Failure Evidence
- Log message: mismatches such as `case[0] M=2 N=4 K=2 C[0,2] mismatch exp=12 act=10` and `case[1] M=2 N=4 K=2 C[1,3] mismatch exp=-12 act=-10`.
- Assertion failure: None.
- Scoreboard mismatch: Matrix checks are performed directly in the test; scoreboard reported `compare_count=0 mismatch_count=0`.
- Waveform path: Not captured for this debug pass.
- Relevant signal observations: Not yet inspected.

### Initial Suspected Root Cause
The compute/accumulator path may not preserve the partial-K accumulation result before `POST_BIAS` post-processing for small K tiles.

### Debug Process
- Step 1:
  - Action: Added a saturation test using `M=2, N=4, K=2` with small dot products and extreme biases.
  - Observation: Result mismatches were bias-only, including non-overflowing columns.
  - Conclusion: The failure was not a saturation clamp/wrap issue.
- Step 2:
  - Action: Switched the saturation stimulus to a full `M=4, N=4, K=4` tile while keeping the same small accumulations and extreme biases.
  - Observation: Both saturation and overflow-status tests passed with 0 UVM errors.
  - Conclusion: The suspected issue is specific to the partial-K biased tile case and should be debugged separately.

### Root Cause
Under debug.

### Fix / Workaround
No DUT fix has been applied. The committed `tensor_base_saturation_test` uses a full tile so it verifies saturation and wrap behavior without masking those objectives behind the partial-K issue.

### Regression Result
Open. The final committed `tensor_base_saturation_test` and `tensor_base_overflow_status_test` pass with the full-tile stimulus.

### Related Files

* RTL: `rtl/top/tensor_accel_top.sv`, `rtl/compute/accumulator.sv`, `rtl/compute/post_process.sv`
* Testbench: `tb/tests/tensor_base_saturation_test.sv`, `tb/tests/tensor_base_overflow_status_test.sv`, `tb/tests/tensor_accel_tests.svh`
* Sequence: `tb/seq_lib/tensor_common_vseqs.sv`
* Scoreboard: `tb/env/tensor_accel_scoreboard.sv`
* Assertion: None.
* Coverage: Not collected; default `COV=0`.
* Waveform: Not generated; default `FSDB=0`.
* Log: Development run output; final run log was overwritten by the passing full-tile stimulus in `tb/sim/sim/run/tensor_base_saturation_test_seed_1/log/run.log`.

### Notes

This issue was discovered during saturation test development but is outside the final scope of the committed saturation/overflow-status tests.

## BUG-20260525-001: IRQ_STATUS W1C could not clear IRQ while DUT remained in DONE

### Status
Fixed

### Severity
Major

### First Found In
- Test case: `tensor_base_irq_test`
- Seed: `1`
- Simulation command: `make run TESTNAME=tensor_base_irq_test BUILD_NAME=irq_tests RUN_TIME=60s`
- Git commit: Uncommitted working tree
- Date: 2026-05-25

### Summary
The legal IRQ directed test exposed that writing `IRQ_STATUS[0]=1` did not clear the IRQ condition after a completed operation. `STATUS.irq`, `IRQ_STATUS[0]`, and the external `irq` pin all remained asserted while the DUT stayed in `ST_DONE`.

### Expected Behavior
After a legal matmul completes with `IRQ_EN=1`, the DUT should assert `irq`, `STATUS.irq`, and `IRQ_STATUS[0]`. A write-one-to-clear write to `IRQ_STATUS[0]` should clear `STATUS.irq` and deassert the external `irq` pin without requiring `CTRL.clear_done`. `CTRL.clear_done` should also clear the IRQ condition.

### Actual Behavior
The operation completed and asserted IRQ correctly, but `IRQ_STATUS` W1C did not clear it. The first failing run reported:

- `IRQ_STATUS W1C clear: STATUS.irq was not cleared, STATUS=0x0000000a`
- `IRQ_STATUS W1C clear: IRQ_STATUS[0] was not cleared, IRQ_STATUS=0x00000001`
- `IRQ_STATUS W1C clear: external irq pin was not deasserted`

The IRQ-on-error scenario already passed, and the legal scenario's later `CTRL.clear_done` path behaved correctly.

### Reproduction Steps
1. Build with `make elab TESTNAME=tensor_base_irq_test BUILD_NAME=irq_tests`.
2. Run `make run TESTNAME=tensor_base_irq_test BUILD_NAME=irq_tests RUN_TIME=60s`.
3. Observe the W1C clear failures before the fix.

### Failure Evidence
- Log message: the three `IRQ_STATUS W1C clear` UVM errors listed above.
- Assertion failure: None.
- Scoreboard mismatch: None; this is a control/status/IRQ behavior check.
- Waveform path: Not captured for this debug pass.
- Relevant signal observations: `STATUS=0x0000000a` indicates DONE and IRQ were still set after the W1C write.

### Initial Suspected Root Cause
The first suspicion was that IRQ clear priority in `command_fsm` was lower than terminal-state IRQ assertion, causing a clear pulse to lose to the DONE-state IRQ set condition.

### Debug Process
- Step 1:
  - Action: Added `tensor_base_irq_test` and `tensor_irq_vseq` to run a legal `8x8x8` INT8 matmul with `IRQ_EN=1`, then check both `IRQ_STATUS` W1C and `CTRL.clear_done` clear paths.
  - Observation: The test failed only on `IRQ_STATUS` W1C; the IRQ-on-error test passed and the done-clear subcase did not report errors.
  - Conclusion: The IRQ generation path worked, but the standalone IRQ clear behavior was defective.
- Step 2:
  - Action: Updated `command_fsm.sv` to give `clear_irq_i`, `clear_done_i`, and `clear_error_i` priority over terminal IRQ assertion.
  - Observation: The legal IRQ test still failed on `IRQ_STATUS` W1C after rebuilding the correct `tb/sim` build image.
  - Conclusion: Priority alone was insufficient; the FSM was reasserting IRQ every cycle while it remained in `ST_DONE`.
- Step 3:
  - Action: Inspected `reg_file.sv`, `tensor_accel_top.sv`, and `command_fsm.sv` connections for `IRQ_STATUS`, `clear_irq_pulse`, and `irq_en`.
  - Observation: `reg_file` generated `clear_irq_pulse_o` from `IRQ_STATUS` writes, and the pulse was connected into `command_fsm`. The issue was in the FSM expression: `status_q.irq` asserted whenever `state_d == ST_DONE` or `state_d == ST_ERROR`, not only when entering those terminal states.
  - Conclusion: While DONE remained uncleared, a W1C pulse could clear IRQ for the cycle but the terminal-state condition immediately set it again.
- Step 4:
  - Action: Changed IRQ assertion to occur only on terminal-state entry: non-DONE to DONE or non-ERROR to ERROR. Kept clear pulses as highest priority.
  - Observation: `tensor_base_irq_test` and `tensor_err_irq_on_error_test` both passed with 0 UVM errors and 0 UVM fatals.
  - Conclusion: Terminal-entry IRQ generation fixed standalone W1C clear semantics without breaking DONE/ERROR IRQ generation.

### Root Cause
`command_fsm` level-triggered IRQ assertion from the terminal states. As long as the FSM stayed in `ST_DONE` or `ST_ERROR`, `irq_en_i` caused `status_q.irq` to be set again, so `IRQ_STATUS` W1C could not keep IRQ cleared unless the terminal status was also cleared.

### Fix / Workaround
`command_fsm.sv` now asserts IRQ only when entering `ST_DONE` or `ST_ERROR`, and clear pulses have priority:

- `clear_irq_i`, `clear_done_i`, and `clear_error_i` clear `status_q.irq`.
- DONE IRQ assertion occurs only on `state_q != ST_DONE && state_d == ST_DONE`.
- ERROR IRQ assertion occurs only on `state_q != ST_ERROR && state_d == ST_ERROR`.

### Regression Result
After the fix:

- `make elab TESTNAME=tensor_base_irq_test BUILD_NAME=irq_tests` completed successfully.
- `make run TESTNAME=tensor_base_irq_test BUILD_NAME=irq_tests RUN_TIME=60s` passed with `UVM_ERROR : 0` and `UVM_FATAL : 0`.
- `make run TESTNAME=tensor_err_irq_on_error_test BUILD_NAME=irq_tests RUN_TIME=60s` passed with `UVM_ERROR : 0` and `UVM_FATAL : 0`.

### Related Files

* RTL: `rtl/control/command_fsm.sv`, `rtl/bus/reg_file.sv`, `rtl/top/tensor_accel_top.sv`
* Testbench: `tb/tests/directed_tests/tensor_base_irq_test.sv`, `tb/tests/exception_tests/tensor_err_irq_on_error_test.sv`
* Sequence: `tb/seq_lib/directed_tests/tensor_irq_vseq.sv`, `tb/seq_lib/exception_tests/tensor_irq_on_error_vseq.sv`, `tb/seq_lib/directed_tests/tensor_matmul_vseq.sv`
* Scoreboard: Not used for IRQ checks.
* Assertion: None.
* Coverage: Not collected for this focused debug run.
* Waveform: Not generated for this focused debug run.
* Log: `tb/sim/sim/run/tensor_base_irq_test_seed_1/log/run.log`, `tb/sim/sim/run/tensor_err_irq_on_error_test_seed_1/log/run.log`

### Notes

The test intentionally checks two clear paths: `IRQ_STATUS[0]` W1C while DONE remains set, and `CTRL.clear_done`. This prevents the implementation from relying on DONE clear as the only way to deassert IRQ.

Source logs are under `tb/sim/sim/run/*/log/run.log`. All listed passing runs used seed `1`, VCS `O-2018.09-SP2_Full64`, UVM verbosity `UVM_MEDIUM`, coverage `line+cond+fsm+branch+tgl+assert`, FSDB enabled, and watchdog `5ms`.

## BUG-20260525-002: Region checker rejected legal word-aligned unaligned C writes

### Status
Fixed

### Severity
Major

### First Found In
- Test case: `tensor_base_write_unaligned_test`
- Seed: `1`
- Simulation command: `make run TESTNAME=tensor_base_write_unaligned_test BUILD_NAME=write_unaligned RUN_TIME=30s`
- Git commit: Uncommitted working tree
- Date: 2026-05-25

### Summary
The directed unaligned write scenario requires `C_BASE=0x0003_0004`, which is 32-bit aligned but not 64-bit AXI-beat aligned. The write DMA already supports this by aligning `AWADDR` down and driving shifted `WSTRB`, but `region_checker` still rejected `C_BASE % 8 != 0` as `ERR_UNALIGNED_BASE_ADDR`.

### Expected Behavior
`C_BASE` should be allowed when it is aligned to the 32-bit C element size. For a 16-byte store starting at `0x0003_0004`, the DUT should issue an aligned AXI write at `0x0003_0000` with `WSTRB` lanes `8'hf0`, `8'hff`, and `8'h0f`, complete with DONE, and write C data at the requested byte addresses.

### Actual Behavior
Before the fix, the configuration validator would classify this scenario as an unaligned base address before the store path could exercise the write DMA unaligned-lane logic.

### Reproduction Steps
1. Build with `make elab TESTNAME=tensor_base_write_unaligned_test BUILD_NAME=write_unaligned`.
2. Run `make run TESTNAME=tensor_base_write_unaligned_test BUILD_NAME=write_unaligned RUN_TIME=30s`.
3. Before the validator fix, observe configuration rejection for a 32-bit aligned but non-64-bit-aligned `C_BASE`.

### Failure Evidence
- Log message: Not captured as a standalone failing run in this debug pass; the issue was identified by static inspection while adding the directed test.
- Assertion failure: None.
- Scoreboard mismatch: None.
- Waveform path: Not captured for this debug pass.
- Relevant signal observations: `axi_write_dma` computes `aligned_addr`, `addr_byte_offset`, and `active_wstrb`, proving that C writes are intentionally supported at 32-bit alignment.

### Initial Suspected Root Cause
The suspected root cause was a mismatch between the write DMA's supported C-address alignment and the global base-address validation policy.

### Debug Process
- Step 1:
  - Action: Inspected `axi_write_dma.sv` while defining the expected `WSTRB` behavior for `C_BASE=0x0003_0004`.
  - Observation: The write DMA aligns `AWADDR` down to the 8-byte beat and generates byte strobes from `addr_byte_offset`.
  - Conclusion: The write datapath supports this scenario.
- Step 2:
  - Action: Inspected `region_checker.sv`.
  - Observation: `align_ok` required A, B, C, and Bias base addresses to be aligned to `AXI_DATA_WIDTH/8`.
  - Conclusion: The validator would reject the legal C write scenario before the write DMA could run.
- Step 3:
  - Action: Relaxed only the `C_BASE` check to 32-bit alignment and kept A, B, and Bias aligned to the AXI beat.
  - Observation: `tensor_base_write_unaligned_test` elaborated and passed, observing the expected shifted write strobes and matching C memory contents.
  - Conclusion: The validator policy now matches the write DMA capability while preserving read-DMA alignment requirements.

### Root Cause
`region_checker` applied the read-DMA AXI-beat alignment requirement to `C_BASE`. C stores write 32-bit result words, and the write DMA supports 32-bit-aligned addresses by shifting `WSTRB` lanes.

### Fix / Workaround
`region_checker.sv` now requires A, B, and Bias base addresses to remain AXI-beat aligned, while `C_BASE` only needs 32-bit word alignment.

### Regression Result
After the fix:

- `make elab TESTNAME=tensor_base_write_unaligned_test BUILD_NAME=write_unaligned` completed successfully.
- `make run TESTNAME=tensor_base_write_unaligned_test BUILD_NAME=write_unaligned RUN_TIME=30s` passed with `UVM_ERROR : 0` and `UVM_FATAL : 0`.

### Related Files

* RTL: `rtl/memory/region_checker.sv`, `rtl/dma/axi_write_dma.sv`
* Testbench: `tb/tests/directed_tests/tensor_base_write_unaligned_test.sv`
* Sequence: `tb/seq_lib/directed_tests/tensor_write_unaligned_vseq.sv`, `tb/seq_lib/directed_tests/tensor_matmul_vseq.sv`
* Scoreboard: Not used for this check; C comparison is performed in the vseq.
* Assertion: None.
* Coverage: Not collected for this focused debug run.
* Waveform: Not generated for this focused debug run.
* Log: `tb/sim/sim/run/tensor_base_write_unaligned_test_seed_1/log/run.log`

### Notes

Byte- or halfword-aligned `C_BASE` values remain illegal because C elements are 32-bit words.

## Summary

| Test | Result | Run completion time | Simulation time | CPU time | UVM errors | DUT abnormal behavior |
| --- | --- | --- | --- | --- | ---: | --- |
| `tensor_base_reg_rw_test` | PASS | 2026-05-14 21:13:24 +0800 | 1,025,000 ps | 2.230 s | 0 | None observed. Register reset, write/readback, and reserved-bit checks passed. |
| `tensor_base_int16_4x4_test` | PASS | 2026-05-14 21:32:27 +0800 | 2,425,000 ps | 2.410 s | 0 | Resolved. No AXI VIP X/Z failures or C matrix mismatches remain. |
| `tensor_base_int8_4x4_test` | PASS | 2026-05-14 21:32:28 +0800 | 4,535,000 ps | 2.710 s | 0 | Resolved. Both `burst_len=1` and `burst_len=4` complete without C matrix mismatches. |
| `base_test` | BLOCKED | 2026-05-13 20:23:51 +0800 | 0 ps | 0.880 s | 1 error, 1 fatal | Not a DUT failure. Simulation stopped at time 0 because SVT VIP licensing failed to initialize. |

## Failure Details

### AXI X/Z VIP errors

- Initial AXI VIP failures reported X/Z on unused AXI sideband fields and on `WDATA` while valid was high.
- Unused sideband fields were tied off in `top_tb.sv`, keeping X/Z detection enabled for active protocol signals.
- The remaining `WDATA` X came from `axi_write_dma` sampling synchronous scratchpad read data in the same cycle as the read request. The writer now separates scratchpad read request and read data capture.

### Zero C matrix output

- After the X/Z fixes, the remaining abnormal behavior was all-zero C output against nonzero expected matrices.
- Root causes:
  - Compute operands `a_vec`, `b_vec`, and `bias_vec` were tied to zero in `tensor_accel_top.sv`.
  - Post-process output was not written into the C scratchpad before store.
  - `axi_read_dma` asserted done before the final accepted read beat finished draining into scratchpad.
- Fixes:
  - Capture loaded A/B/bias words into local operand tiles and drive the systolic array from those tiles.
  - Add a post-process writeback phase before store.
  - Delay read-DMA done until the final scratchpad write from the last AXI read beat completes.

## Notes

- `tensor_base_reg_rw_test` remains a passing baseline for AXI-Lite register access.
- The 4x4 compute tests now pass for both int8 and int16 directed data paths.
- The scoreboard still reports `compare_count=0 mismatch_count=0`; matrix result checks are performed directly in the tests.
- The earlier `base_test` run is excluded from DUT bug classification because the failure is an external SVT VIP licensing issue.
