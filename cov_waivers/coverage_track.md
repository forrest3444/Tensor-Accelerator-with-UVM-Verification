# Coverage Tracking

## Run History

| Date | Build | Tests | Pass/Fail | Line% | Cond% | FSM% | Branch% | Toggle% | Assert% | Notes |
|------|-------|-------|-----------|-------|-------|------|---------|---------|---------|-------|
| 2026-07-03 (历史记录) | full_cov | 54 | 54/0 | 98.44 | 81.89 | 63.81 | 94.33 | 88.82 | 100 | 历史基线；早于 7 月 7 日 RTL 修改，非当前代码验证结果 |
| 2026-10-15 | review_20261015/full_cov | 54 | 54/0 | 98.44 | 82.79 | 63.81 | 94.86 | 88.89 | 100 | 当前 RTL 重新编译；COV=1 ASSERT=1；原始 DUT subtree 指标 |
| 2026-10-15 | review_20261015/full_cov + .el | 54 | 54/0 | 98.44 | 82.94 | 92.42 | 94.86 | 88.89 | 100 | 同轮数据，URG 应用 dve_waivers.el；未报告加载/校验错误 |

## Coverage Convergence

Latest DUT subtree metrics after applying the authoritative `.el` exclusions:

```
Line:     ████████████████████████████████████████████░  98.44%
Cond:     ███████████████████████████████░░░░░░░░░░░░░░  82.94%
FSM:      █████████████████████████████████████████░░░░  92.42%
Branch:   ██████████████████████████████████████████░░░  94.86%
Toggle:   ██████████████████████████████████████░░░░░░░  88.89%
```

## Latest Regression Evidence

- Source: current working-tree RTL, rebuilt with VCS O-2018.09-SP2 on 2026-10-15.
- Suite: all 25 directed tests, 20 exception/reset tests, and 3 random tests with seeds 1/2/3 and `+RAND_ITERS=5` (54 runs total).
- Settings: `COV=1 ASSERT=1 FSDB=0 RUN_TIME=60s BUILD_NAME=full_cov`.
- Result: `total=54 passed=54 failed=0 pass_rate=100.00%`; all 54 logs have `UVM_ERROR=0` and `UVM_FATAL=0`.
- Isolation: ran the existing `script/run_regression.sh` test list through a temporary wrapper replacing its hardcoded `sim/run/` paths with `sim/review_20261015/run/`; Make used `SIM=sim/review_20261015`. No old run databases were merged.
- Raw report: `sim/review_20261015/merged_cov_report/mod20.html` (DUT instance subtree).
- Excluded report: `sim/review_20261015/waived_cov_report/mod20.html` (same scope).
- Exclusion command: `urg -dir sim/review_20261015/merged_cov.vdb -elfile cov_waivers/dve_waivers.el -report sim/review_20261015/waived_cov_report`.
- URG completed successfully without exclusion-load/checksum diagnostics. State exclusions can also exclude associated transitions; waived FSM coverage is not raw stimulus coverage.
- YAML matches all 20 explicit `.el` state/transition selections; the scratchpad checksum/instance-only marker is recorded separately. No formal unreachability proof or waiver approval is implied.

## Coverage Holes

### Open

| ID | Scope | Type | Detail | Owner | Target |
|----|-------|------|--------|-------|--------|
| HOLE-FSM-001 | command_fsm | FSM | 7 explicit reset-only transitions → ST_IDLE (.el scope) | DV | WVR-CODE-FSM-001 |
| HOLE-FSM-003 | command_fsm | FSM | ST_PIPE_ADVANCE state excluded in .el | DV | WVR-CODE-FSM-003 |
| HOLE-FSM-004 | command_fsm | FSM | ST_WAIT_STORE_SLOT state excluded in .el; functional entry exists | DV | WVR-CODE-FSM-004 |
| HOLE-LOAD-001 | load_scheduler | FSM | LS_IDLE state excluded in .el; reachable and historically covered | DV | WVR-CODE-LOAD-001 |
| HOLE-DMAR-001 | axi_read_dma | FSM | S_AR → S_IDLE (reset-only) | DV | WVR-CODE-DMAR-001 |
| MARKER-SPAD-001 | scratchpad_ctrl | Instance | .el checksum/instance marker only; no explicit excluded objects | DV | WVR-CODE-SPAD-001 |
| HOLE-DMAW-001 | axi_write_dma | FSM | S_START/S_SPLIT/S_PLAN/S_AW/S_READ_REQ/S_READ_DATA/S_W/S_B/S_B_RESP → S_IDLE (reset-only) | DV | WVR-CODE-DMAW-001 |

### Closed

| ID | Scope | Type | Disposition | Date |
|----|-------|------|-------------|------|
| | | | | |

## Waiver Log

| Waiver ID | VTrack ID | Coverage Type | Module | Status | Date |
|-----------|-----------|---------------|--------|--------|------|
| WVR-CODE-FSM-001 | VTR-FSM-001 | FSM | command_fsm | proposed | 2026-07-02 |
| WVR-CODE-FSM-002 | VTR-FSM-002 | FSM | command_fsm | superseded (absent from .el) | 2026-10-15 |
| WVR-CODE-DMAW-001 | VTR-DMAW-001 | FSM | axi_write_dma | proposed | 2026-07-03 |
| WVR-CODE-FSM-003 | VTR-FSM-003 | FSM | command_fsm | proposed | 2026-10-15 |
| WVR-CODE-FSM-004 | VTR-FSM-004 | FSM | command_fsm | proposed | 2026-10-15 |
| WVR-CODE-LOAD-001 | VTR-LOAD-001 | FSM | load_scheduler | proposed | 2026-10-15 |
| WVR-CODE-DMAR-001 | VTR-DMAR-001 | FSM | axi_read_dma | proposed | 2026-10-15 |
| WVR-CODE-SPAD-001 | VTR-SPAD-001 | Instance marker | scratchpad_ctrl | proposed | 2026-10-15 |

## Review Log

| Date | Attendees | Decisions |
|------|-----------|-----------|
| 2026-10-15 | User / Codex | 按用户要求，以 dve_waivers.el 为排除项权威来源同步 YAML；未匹配的历史 default-arm 提案标记 superseded。 |
