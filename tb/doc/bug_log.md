# DUT Bug Log

Source logs are under `tb/sim/sim/run/*/log/run.log`. All listed passing runs used seed `1`, VCS `O-2018.09-SP2_Full64`, UVM verbosity `UVM_MEDIUM`, coverage `line+cond+fsm+branch+tgl+assert`, FSDB enabled, and watchdog `5ms`.

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
