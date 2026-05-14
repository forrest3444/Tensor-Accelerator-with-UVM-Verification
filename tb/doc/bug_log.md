# DUT Bug Log

Source logs are under `tb/sim/sim/run/*/log/run.log`. All listed runs used seed `1`, VCS `O-2018.09-SP2_Full64`, UVM verbosity `UVM_MEDIUM`, coverage `line+cond+fsm+branch+tgl+assert`, FSDB enabled, and watchdog `5ms`.

## Summary

| Test | Result | Run completion time | Simulation time | CPU time | UVM errors | DUT abnormal behavior |
| --- | --- | --- | --- | --- | ---: | --- |
| `tensor_base_reg_rw_test` | PASS | 2026-05-14 16:04:26 +0800 | 1,025,000 ps | 2.130 s | 0 | None observed. Register reset, write/readback, and reserved-bit checks passed. |
| `tensor_base_int8_4x4_test` | FAIL | 2026-05-14 19:44:08 +0800 | 3,845,000 ps | 2.520 s | 84 | AXI address/data signals contain X/Z during valid transfers. Output matrix C reads back as zero instead of expected nonzero values. |
| `tensor_base_int16_4x4_test` | FAIL | 2026-05-14 19:51:26 +0800 | 2,185,000 ps | 2.330 s | 42 | AXI address/data signals contain X/Z during valid transfers. Output matrix C reads back as zero instead of expected nonzero values. |
| `base_test` | BLOCKED | 2026-05-13 20:23:51 +0800 | 0 ps | 0.880 s | 1 error, 1 fatal | Not a DUT failure. Simulation stopped at time 0 because SVT VIP licensing failed to initialize. |

## Failure Details

### `tensor_base_int8_4x4_test`

- Test reports `tensor_base_int8_4x4_test FAILED` at 3,845,000 ps.
- AXI VIP reports X/Z checks on `ARID`, `ARLOCK`, `ARCACHE`, `ARPROT`, `AWID`, `AWLOCK`, `AWCACHE`, `AWPROT`, and `WDATA` while the corresponding valid signal is high.
- AXI VIP also reports failed casts for `observed_arlock`, `observed_arprot`, `observed_awlock`, and `observed_awprot`.
- Matrix C comparison fails for both tested burst lengths:
  - `burst_len=1`: all 16 C elements mismatch at 1,835,000 ps.
  - `burst_len=4`: all 16 C elements mismatch at 3,725,000 ps.
- In every C mismatch, `act=0`; expected values include positive and negative nonzero results. This indicates the DUT does not write the computed output data back correctly, or the read path returns zeroed data after compute.

### `tensor_base_int16_4x4_test`

- Test reports `tensor_base_int16_4x4_test FAILED` at 2,185,000 ps.
- AXI VIP reports X/Z checks on `ARID`, `ARLOCK`, `ARCACHE`, `ARPROT`, `AWID`, `AWLOCK`, `AWCACHE`, `AWPROT`, and `WDATA` while the corresponding valid signal is high.
- AXI VIP also reports failed casts for `observed_arlock`, `observed_arprot`, `observed_awlock`, and `observed_awprot`.
- Matrix C comparison fails for all 16 C elements at 2,075,000 ps.
- In every C mismatch, `act=0`; expected values include large signed products and accumulations. This points to the same output-write/readback failure seen in the int8 test.

## Notes

- `tensor_base_reg_rw_test` is a passing baseline for AXI-Lite register access. The observed failures are exposed by compute/data-movement tests, not by basic register access.
- The scoreboard reports `compare_count=0 mismatch_count=0` in the failing matrix tests. The failures are raised directly by the test checks, so scoreboard coverage should be reviewed separately.
- The X/Z AXI VIP errors are protocol-level issues and should be debugged before relying on matrix result comparisons alone.
- The earlier `base_test` run is excluded from DUT bug classification because the failure is an external SVT VIP licensing issue.
