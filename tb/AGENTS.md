# AGENTS.md

## Scope

This file applies to the entire `tb/` directory and all verification-related work under this directory.

All agents working in this directory must follow the rules below when running simulations, debugging failures, modifying testbench code, or analyzing DUT behavior.

---

## Core Rule: Maintain DUT Bug Log

Whenever a test case is run and the result exposes a DUT defect, suspected DUT defect, protocol violation, functional mismatch, timing issue, assertion failure, or unexplained waveform anomaly, the agent must record the issue in:

```text
tb/doc/bug_log.md
```

If `tb/doc/bug_log.md` does not exist, create it.

The bug log must be updated during the same task in which the issue is discovered or debugged. Do not rely on memory or leave the record for a later task.

---

## What Must Be Logged

The agent must add a new bug-log entry when any of the following occurs:

1. A test case fails because DUT output differs from the reference model or scoreboard expectation.
2. AXI / AHB / APB / SPI / custom protocol behavior violates the specification.
3. An assertion fails and the root cause points to the DUT or is not yet proven to be TB-related.
4. The waveform shows abnormal DUT behavior, such as:

   * wrong response
   * missing valid/ready handshake
   * early or late last signal
   * incorrect address update
   * incorrect burst behavior
   * incorrect data alignment
   * incorrect interrupt/status behavior
   * unexpected FSM transition
5. A test passes only because the testbench masks, ignores, or works around suspicious DUT behavior.
6. The issue is later proven to be a testbench bug, but it was initially suspected to be a DUT bug.

---

## What Should Not Be Logged as a DUT Bug

Do not classify the following as DUT bugs unless waveform or protocol evidence supports it:

1. Pure compile errors caused by missing packages, wrong file order, or tool setup.
2. UVM factory registration errors.
3. Null virtual interface or config_db setup mistakes.
4. Syntax errors in testbench code.
5. Sequence constraint errors unrelated to DUT behavior.
6. Scoreboard false failures that are clearly caused by an incorrect reference model.

However, if such an issue was originally suspected to be a DUT bug, it may be recorded as a “False Alarm / TB Issue” entry.

---

## Bug Log File Format

The bug log must be written in Markdown.

Each bug entry must use the following format exactly:

````markdown
## BUG-YYYYMMDD-NNN: <short bug title>

### Status
Open / Under Debug / Fixed / Cannot Reproduce / False Alarm / Won't Fix

### Severity
Critical / Major / Minor / Trivial

### First Found In
- Test case:
- Seed:
- Simulation command:
- Git commit:
- Date:

### Summary
Briefly describe the observed failure.

### Expected Behavior
Describe the behavior expected from the design specification or protocol.

### Actual Behavior
Describe what the DUT actually did.

### Reproduction Steps
1. 
2. 
3. 

### Failure Evidence
- Log message:
- Assertion failure:
- Scoreboard mismatch:
- Waveform path:
- Relevant signal observations:

### Initial Suspected Root Cause
Describe the first suspected DUT module, FSM, counter, handshake logic, datapath logic, or control condition.

### Debug Process
Record the debug process chronologically.

Example format:

- Step 1:
  - Action:
  - Observation:
  - Conclusion:
- Step 2:
  - Action:
  - Observation:
  - Conclusion:

### Root Cause
Describe the confirmed root cause.

If not confirmed yet, write:

```text
Not confirmed yet.
```

### Fix / Workaround

Describe the RTL fix, TB workaround, or temporary limitation.

If no fix has been made yet, write:

```text
No fix yet.
```

### Regression Result

Describe whether the original failing test and related regression tests pass after the fix.

### Related Files

* RTL:
* Testbench:
* Sequence:
* Scoreboard:
* Assertion:
* Coverage:
* Waveform:
* Log:

### Notes

Additional notes, risks, or follow-up items.

````

---

## Bug ID Rule

Bug IDs must follow this format:

```text
BUG-YYYYMMDD-NNN
```

Example:

```text
BUG-20260520-001
BUG-20260520-002
```

Rules:

1. `YYYYMMDD` is the date when the bug is first recorded.
2. `NNN` starts from `001` for each date.
3. If there are already bug entries for the same date, increment the last number.
4. Do not reuse bug IDs.
5. Do not rename existing bug IDs unless explicitly requested.

---

## Required Logging Discipline

When updating `tb/doc/bug_log.md`, the agent must:

1. Append new entries at the top of the file, below the file title and index section if one exists.
2. Preserve all existing bug entries.
3. Never delete historical debug notes unless explicitly requested.
4. Update the `Status` field when the bug progresses.
5. Add new debug findings under `Debug Process` instead of overwriting previous observations.
6. Clearly distinguish between:

   * confirmed facts
   * suspected causes
   * temporary assumptions
   * final root cause

---

## Recommended Top-Level Structure of bug_log.md

If `tb/doc/bug_log.md` does not exist, create it with the following initial structure:

```markdown
# DUT Bug Log

This document records DUT defects, suspected DUT defects, waveform anomalies, protocol violations, and debug history found during simulation.

## Bug Index

| Bug ID | Title | Status | Severity | First Found In | Last Updated |
|---|---|---|---|---|---|

---

<!-- New bug entries should be inserted below this line. -->
```

When adding a new bug entry, also update the `Bug Index` table.

---

## Evidence Requirements

A bug entry should be evidence-driven. Whenever possible, include:

1. test name
2. random seed
3. simulation command
4. failing timestamp
5. relevant transaction fields
6. scoreboard expected value
7. scoreboard actual value
8. assertion name
9. waveform file path
10. suspected RTL file and line number

Do not write vague descriptions such as:

```text
DUT seems wrong.
```

Instead, write concrete observations such as:

```text
At 1250 ns, awvalid and awready completed a handshake with awaddr=0x1000 and awlen=0x3. The following W channel transferred four beats, but the DUT issued only three AHB NONSEQ/SEQ transfers. The fourth AXI write beat was accepted but no corresponding AHB write was generated.
```

---

## Debug Process Requirements

The debug process must be written as a chronological investigation record.

Each debug step should include:

1. What was checked.
2. What evidence was found.
3. What conclusion was drawn.
4. Whether the suspicion shifted to another module or signal.

Example:

```markdown
- Step 1:
  - Action: Checked scoreboard mismatch around 2400 ns.
  - Observation: AXI write transaction contained 4 beats, but AHB monitor collected only 3 write transfers.
  - Conclusion: Failure is likely before or inside AXI-to-AHB command generation, not in the scoreboard.

- Step 2:
  - Action: Opened waveform and traced write_counter, AW_HS, W_HS, and htrans.
  - Observation: write_counter reached 3 while awlen was 3, but the FSM returned to IDLE before issuing the final SEQ transfer.
  - Conclusion: Suspect off-by-one condition in write burst termination logic.
```

---

## Classification Rules

Use the following severity definitions:

### Critical

The DUT deadlocks, violates a fundamental protocol rule, corrupts data broadly, or prevents a major feature from working.

### Major

A legal transaction fails under specific but important conditions, such as burst length, address range, response type, alignment, interrupt behavior, or backpressure.

### Minor

A corner case fails, but the main function still works and the workaround is simple.

### Trivial

Documentation mismatch, non-functional issue, debug signal issue, or cosmetic behavior.

---

## Status Definitions

Use the following status values only:

```text
Open
Under Debug
Fixed
Cannot Reproduce
False Alarm
Won't Fix
```

Meaning:

* `Open`: Issue has been observed but not deeply analyzed.
* `Under Debug`: Debug is in progress.
* `Fixed`: Root cause was fixed and regression passed.
* `Cannot Reproduce`: The failure cannot be reproduced after reasonable attempts.
* `False Alarm`: The issue was caused by testbench, reference model, configuration, or user error.
* `Won't Fix`: The behavior is accepted as a design limitation or intentional behavior.

---

## Interaction With Testbench Changes

Before modifying testbench code to avoid a failure, the agent must decide whether the failure indicates a real DUT issue.

If the agent changes the testbench because the previous test expectation was wrong, the bug log must record:

1. why the original expectation was wrong
2. what was changed in the testbench
3. why the DUT behavior is now considered legal

If the agent changes the testbench only to work around a DUT limitation, the bug log must record:

1. the original DUT limitation
2. the workaround
3. the risk of masking future bugs

---

## Regression Rules

After a bug fix, the agent should record:

1. the original failing test result
2. at least one rerun of the same test
3. related directed or random regression result, if available
4. whether coverage or assertions were affected

Example:

```markdown
### Regression Result

- Original failing test:
  - test: axi_wrap_burst_write_read_test
  - seed: 12345
  - result before fix: FAIL
  - result after fix: PASS

- Related regression:
  - axi_incr_burst_random_test: PASS
  - axi_fixed_burst_random_test: PASS
  - axi_wrap_burst_random_test: PASS
```

---

## Agent Behavior Requirements

When working under `tb/`, the agent must:

1. Run or inspect the relevant test whenever possible before claiming that a bug is fixed.
2. Avoid silently changing tests to pass without explaining the reason.
3. Avoid deleting failing tests unless explicitly instructed.
4. Prefer adding targeted regression tests for confirmed DUT bugs.
5. Keep bug entries technical, factual, and waveform/log-driven.
6. Use precise protocol terminology.
7. Avoid mixing unrelated bugs into one entry.
8. Create a separate bug entry if a new independent issue is found during debug.

---

## Final Response Requirement

After updating `tb/doc/bug_log.md`, the agent should summarize to the user:

1. which bug ID was added or updated
2. current status
3. suspected or confirmed root cause
4. files changed
5. whether the failing test was rerun

Do not paste the entire bug log into the chat unless explicitly requested.
