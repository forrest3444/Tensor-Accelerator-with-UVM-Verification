# Tensor Accel Performance 优化计划

## 1. 目标和范围

本计划面向当前 `tensor_accel` RTL 的架构和性能优化。阶段目标是不扩展精度，继续保持现有 INT8/INT16 输入、INT32 输出和整数矩阵乘加语义，优先提升推理侧吞吐率、降低流水空泡，并增强 RTL 的可参数化、可综合、可验证能力。

当前不纳入本轮范围：

- FP16/BF16/FP32 浮点计算。
- 完整 mixed precision 数据通路。
- 算法层模型结构变化。
- SoC-level integration、低功耗、CDC/RDC、gate-level timing signoff。

本轮重点：

- 建立性能基线。
- 参数化当前 4x4 tile 架构中的硬编码。
- 优化 DMA 和 scratchpad 吞吐。
- 逐步引入 load/compute/store overlap。
- 在必要时扩展 array 规模。
- 补强 assertion、coverage、scoreboard 和 debug 能力。

## 2. 当前 RTL 性能瓶颈概述

当前 RTL 执行流整体偏串行：

```text
LOAD_A -> LOAD_B -> LOAD_BIAS(optional) -> COMPUTE -> POST_PROCESS -> STORE
```

主要瓶颈和硬编码点：

- `tensor_pkg.sv` 中 `precision_e` 仅包含 `PREC_INT8` 和 `PREC_INT16`，本轮保持不变。
- `tensor_accel_top.sv` 中大量逻辑按 4x4 tile 编写，例如 `row_base = tile_m << 2`、`col_base = tile_n << 2`、`compute_k_limit <= 4`。
- C 输出和 bias 当前固定为 32-bit element，相关逻辑中存在 `* 4`、`<< 2`、`32'd4`。
- `compute_array_done` 使用固定延迟假设，当前依赖 `compute_k_limit + 3`。
- `scratchpad_ctrl` 对 DMA 和 compute 使用单端口仲裁，无法同时服务 load/store 和 compute。
- `axi_read_dma` 一次只发一个 read burst，等数据写入 scratchpad 后再继续。
- `command_fsm` 当前按阶段串行等待，不支持下一 tile 预取或上一 tile 写回并行。
- `post_process` 后逐元素写 scratchpad，再由 writer 写回外部 memory。

因此，performance 版本不应只看 MAC 数量，而应优先解决数据搬运、scratchpad 访问和 tile pipeline 空泡。

## 3. 总体路线

推荐路线：

1. 先建立性能基线和 profiling counter。
2. 做低风险参数化和控制清理。
3. 优化 DMA、burst、scratchpad 和 descriptor 路径。
4. 引入 load/compute/store tile pipeline。
5. 最后再考虑扩大 array 规模。

不建议一开始直接做 8x8/16x16 array 或复杂流水。当前 top、scheduler、post-process、store 路径仍有较多 4x4 假设，直接扩大 array 会显著增加 debug 和验证风险。

## 4. 阶段 0：建立性能基线

### 4.1 阶段目标

量化当前架构慢在哪里，形成后续优化的可比较基线。

### 4.2 关键工作

在验证环境实现 performance monitor，建议至少包含：

- `total_cycles`
- `load_cycles`
- `compute_cycles`
- `post_process_cycles`
- `store_cycles`
- `idle_or_wait_cycles`
- `axi_read_bytes`
- `axi_write_bytes`
- `tile_count`
- `read_burst_count`
- `write_burst_count`
- `stall_on_axi_read`
- `stall_on_axi_write`
- `stall_on_spad`

性能统计通过 testbench probe 和 AXI monitor 完成，不占用可综合 RTL 资源，也不作为软件寄存器契约。

建议固定 workload：

- 16x16 INT8/INT16
- 32x32 INT8/INT16
- 64x64 INT8/INT16
- bias/relu/saturation 典型场景

### 4.3 关键节点

- M0.1：counter 能正确统计一次 operation 的 cycle breakdown。
- M0.2：regression log 或 report 能输出性能数据。
- M0.3：形成 baseline 表格，作为后续优化对比依据。

### 4.4 验收标准

- 不改变现有 directed/random/exception testcase 结果。
- 至少覆盖 16x16、32x32、64x64 三类矩阵规模。
- 每个 workload 能输出 total/load/compute/post/store/idle cycle。

### 4.5 风险

风险低。主要风险是 counter 统计边界和状态定义不清，需要先明确 load/compute/store 的起止条件。

## 5. 阶段 1：低风险参数化和控制清理

### 5.1 阶段目标

在不改变外部行为的前提下，消除关键硬编码，为后续 performance 架构铺路。

### 5.2 关键工作

#### 5.2.1 tile 参数化

建议引入统一参数：

```systemverilog
parameter int TILE_M = ARRAY_M;
parameter int TILE_N = ARRAY_N;
parameter int TILE_K = 4;
parameter int OUT_BYTES = 4;
parameter int BIAS_BYTES = 4;
```

需要检查和替换的典型位置：

- `tile_count_fsm.sv` 中 tile count、row/col valid loop 和 C external offset 计算。
- `load_scheduler.sv` 中 tile_rows/tile_cols/tile_k 的 `> 4` 判断。
- `tensor_accel_top.sv` 中 row_base、col_base、k_base、compute_k_limit、C write byte 计算。
- post-process writeback 计数和地址计算。

#### 5.2.2 compute latency 参数化

当前 compute 完成条件依赖固定表达式：

```systemverilog
compute_array_done = compute_active_q && (compute_count_q == (compute_k_limit + 4'd3));
```

建议改为：

```systemverilog
localparam int COMPUTE_PIPE_LATENCY = 3;
```

后续如果 PE pipeline 或 array 结构调整，只需修改 latency 参数和对应验证。

#### 5.2.3 burst 参数化

当前 `axi_read_dma/axi_write_dma` 默认 `MAX_BURST_BEATS=16`，而 testbench performance profile 已存在 `burst_len=256` 概念。需要明确 performance 版本是否支持 256 beats。

建议：

- 保留 base profile：`MAX_BURST_BEATS=16`。
- 增加 performance profile：`MAX_BURST_BEATS=256`。
- 将顶层参数传入 DMA 和 splitter。
- 保留对 `burst_len=0` 和超限值的验证。

### 5.3 关键节点

- M1.1：tile、output byte、bias byte、compute latency 常量统一参数化。
- M1.2：`MAX_BURST_BEATS` 可由顶层参数选择 16 或 256。
- M1.3：现有 4x4 行为完全保持，完整 regression 通过。
- M1.4：性能 counter 显示无明显退化。

### 5.4 验收标准

- 现有 INT8/INT16 directed testcase 通过。
- exception testcase 中非法尺寸、region、burst、reset 行为不退化。
- 4x4 仍为默认配置。

### 5.5 风险

风险中等。参数化容易引入边界尺寸、尾 tile、地址 stride 和 post-process 写回错误。

## 6. 阶段 2：DMA 和 Scratchpad 吞吐优化

### 6.1 阶段目标

减少 DMA 和 scratchpad 等待，提高 AXI 带宽利用率，为后续 tile pipeline 准备数据通路。

### 6.2 关键工作

#### 6.2.1 Read DMA 4KB 自动切分

当前 read DMA 对 4KB crossing 更偏向报错，write DMA 已支持自动切分。performance 版本建议支持 read 自动切分，减少软件对数据对齐和分段的负担。

需要注意：

- 现有 `ERR_BURST_CROSS_4KB` 语义可能变化。
- 建议通过配置位选择 legacy mode 或 performance mode。
- 需要保留原异常 testcase，新增 auto split testcase。

#### 6.2.2 Descriptor FIFO

当前 command FSM 需要等待每个 load/store 完成。建议增加 descriptor FIFO：

- read descriptor FIFO：A/B/bias load descriptor。
- write descriptor FIFO：C store descriptor。
- 初始深度建议 2 到 4。

当前粗优化收尾状态：

- read descriptor FIFO 已接入 A/B/bias load path。
- write descriptor FIFO 已接入 C store path，当前主要作为 store FSM 与 writer 的结构解耦边界。
- 为避免单个 `store_row_buffer` 被提前覆盖，buffer release 和 command done 仍严格等待实际 writer done；因此该 write FIFO 当前不作为性能收益项验收。
- FIFO overflow/underflow、重复 store descriptor、零行 store descriptor 已补内部 assertion。

收益：

- scheduler 可提前准备下一笔 DMA。
- 减少 command FSM 和 DMA 之间的空泡。
- 为 tile pipeline 做铺垫。

#### 6.2.3 Scratchpad bank 或 ping-pong buffer

当前 `scratchpad_ctrl` 对 DMA 和 compute 单端口仲裁。performance 版本建议使用 ping-pong buffer 或 banked scratchpad：

- buffer0 被 compute 使用时，buffer1 可加载下一 tile。
- C 不再持久化到 scratchpad，post-process 结果进入临时 `store_row_buffer` 后由 writer 按外部 row-major C 语义写回。
- 每个 tile context 记录 `buffer_id`。

第一步可以不改物理 memory 数量，只先在地址规划上切分 buffer region；第二步再改为多 bank 或双端口实现。

### 6.3 关键节点

- M2.1：read/write DMA 支持 performance burst 参数。
- M2.2：read DMA 支持 4KB auto split，且 legacy error mode 可保留。
- M2.3：descriptor FIFO 接入 load/store path。
- M2.4：scratchpad 支持 ping-pong buffer 地址规划。
- M2.5：AXI utilization 和 idle cycle 相比 baseline 有改善。

### 6.4 验收标准

- AXI read/write SLVERR、中途 error、unaligned write、burst_len、4KB testcase 通过。
- reset during load/store 能清空 FIFO 和 buffer ownership。
- 无 descriptor 泄漏、重复执行或丢失。

### 6.5 风险

风险中到高。DMA 和 scratchpad 是当前异常测试覆盖最密集的区域，容易影响错误码优先级、reset 行为和 4KB boundary 语义。

## 7. 阶段 3：Load/Compute/Store Pipeline

### 7.1 阶段目标

把当前串行 tile 执行改为可并发流水，提高大矩阵推理吞吐。

### 7.2 目标架构

目标执行形式：

```text
cycle window N:
  LOAD      tile i+1
  COMPUTE   tile i
  STORE     tile i-1
```

对外语义保持不变：

- 软件仍只看到一次 start。
- 所有 tile 完成并写回后才置 `done`。
- 任一 inflight tile 发生 error，operation 进入 error 状态。
- reset/soft reset 清空所有 inflight context。

### 7.3 关键工作

#### 7.3.1 分层状态机

`command_fsm` 只保留命令级生命周期，不再承载 tile 内部流水细节：

- `IDLE`
- `CHECK_CONFIG`
- `RUN`
- `DONE`
- `ERROR`

tile pipeline 内部至少拆成以下子状态机，各子状态机通过 ready/valid/done 形式握手，不直接跳转对方状态：

- `tile_count_fsm`：按 in-order 顺序产生 tile token，维护 `tile_m/tile_n/tile_k/last_tile`，不参与资源仲裁。
- `buffer_manager_fsm`：维护每个 buffer 的所有权、hazard 检查和 in-order 提交窗口。
- `load_fsm`：消费 load token，发起 A/B/bias read descriptor，并在 descriptor drain 后回写 buffer 状态。
- `compute_fsm`：消费 ready-for-compute token，锁存 compute context，启动 array，完成后回写 buffer 状态。
- `store_fsm`：消费 ready-for-store token，发起 C write descriptor/row writeback，完成后释放 buffer。

子状态机之间只交换事件和 token，例如：

- `tile_valid/tile_ready`
- `load_req_valid/load_req_ready`
- `load_done_valid/load_done_ready`
- `compute_req_valid/compute_req_ready`
- `compute_done_valid/compute_done_ready`
- `store_req_valid/store_req_ready`
- `store_done_valid/store_done_ready`

所有 tile 必须严格 in-order issue、in-order compute、in-order store commit。允许 load/compute/store 并行，但不允许后续 tile 越过前序 tile 对外完成。

#### 7.3.2 引入 tile context

每个 inflight tile 至少需要保存：

- `tile_m`
- `tile_n`
- `tile_k`
- `row_valid`
- `col_valid`
- `first_k_tile`
- `last_k_tile`
- `last_tile`
- `buffer_id`
- `post_op`
- `sat_mode`
- `c_ext_offset`

#### 7.3.3 Buffer ownership

每个 buffer 需要独立维护一组状态监测变量。建议最小集合：

- `valid`
- `tile_id`
- `tile_m/tile_n/tile_k`
- `a_region_state`
- `b_region_state`
- `c_region_state`
- `bias_state`
- `load_inflight`
- `compute_inflight`
- `store_inflight`
- `ready_for_compute`
- `ready_for_store`
- `release_pending`

buffer 主状态建议为：

- free
- loading
- ready_for_compute
- computing
- ready_for_store
- storing

任何时候禁止多个 stage 写同一可变 region。B 条带是按 N 复用的单条带资源，不作为 ping-pong bank；只有跨 N 且当前 compute 仍依赖旧 B 条带时，buffer manager 才能阻止下一 N 的 B load。A/C 使用 ping-pong buffer，bias 使用固定条带并在 compute 启动时锁存到 compute context。

当前粗优化收尾后的 SPAD 地址规划采用：

- A ping-pong bank0/bank1
- B single stripe
- bias single stripe

B 输入矩阵默认由软件预转置，以便硬件按列条带顺序读取；C 外部矩阵契约保持 row-major。硬件内部使用多行写/row buffer 保持 C row-major 兼容，不要求软件改变 C 布局。

#### 7.3.4 Error 和 reset 处理

需要明确：

- error 发生后是否允许已发出的 AXI transaction drain。
- error 后是否停止 issue 新 descriptor。
- reset/soft reset 如何清空 DMA、FIFO、buffer state。
- 多个 error 同时发生时的优先级。

### 7.4 关键节点

- M3.1：tile context 定义完成并接入 scheduler。
- M3.2：load/compute/store tracker 可独立运行。
- M3.3：double buffering 跑通 16x16/32x32。
- M3.4：64x64 INT8/INT16 相比 baseline 有明确吞吐提升。
- M3.5：reset/error/IRQ/overflow sticky 行为通过 regression。

### 7.5 验收标准

- 所有 directed matmul testcase 通过。
- 所有 exception testcase 通过或有明确 spec 更新。
- performance monitor 显示 load/compute/store overlap 命中。
- 大矩阵场景 idle cycle 明显下降。

### 7.6 风险

风险高。主要风险：

- last tile 和 done 判断错误。
- K tile 累加顺序错误。
- C tile 写回顺序错误。
- buffer ownership 冲突。
- reset during pipeline 阶段清理不完整。
- error 优先级和 IRQ sticky bit 行为变化。

## 8. 阶段 4：可扩展 Array 规模

### 8.1 阶段目标

在 pipeline 和 memory bandwidth 稳定后，再评估是否把默认 4x4 array 扩展到 8x8 或其他规模。

### 8.2 前置条件

不建议在阶段 0 到阶段 3 之前扩大 array。扩大 array 之前必须满足：

- tile size 已参数化。
- scratchpad 带宽能支撑更大 tile。
- post-process 写回不会成为新瓶颈。
- DMA 能提供足够数据带宽。
- 4x4 配置 regression 稳定通过。

### 8.3 关键工作

- 让 `ARRAY_M/ARRAY_N/TILE_K` 在 top、scheduler、load、post-process、store 中真正参数化。
- 支持 8x8 build/elab。
- 增加 8x8 directed testcase。
- 根据综合和 STA 报告评估频率、面积、功耗。

### 8.4 关键节点

- M4.1：4x4 参数化配置 regression 通过。
- M4.2：8x8 配置编译和 elaboration 通过。
- M4.3：8x8 基础 INT8/INT16 testcase 通过。
- M4.4：综合/STA 报告满足目标频率。

### 8.5 风险

风险高。当前 `systolic_array` 局部有参数，但 top-level 数据装载、tile 调度、post-process 和写回仍有大量 4x4 假设。

## 9. 除 Performance 外的建议优化项

### 9.1 Config Freeze

建议 start 时 latch 一份 `cfg_active`，operation 期间所有控制和 datapath 使用 latched config，而不是直接使用 live register config。

当前粗优化收尾状态：已在 top 中接入 `cfg_active`。寄存器文件仍暴露 live `cfg` 给软件读写；配置合法性检查继续基于 start 前的 live `cfg`；start 被接受后 scheduler、DMA、compute/post/store 数据通路使用 frozen `cfg_active`。

收益：

- 避免软件 mid-flight 改配置导致不可预测行为。
- 简化 debug。
- 方便 assertion 检查。

### 9.2 Error Priority 固化

建议明确并文档化 error 优先级。例如：

```text
soft_reset > command_while_busy > config_error > 4KB_error > internal_timeout > AXI_read_error > AXI_write_error
```

实际优先级需要结合设计语义确定，并用 testcase/assertion 固化。

### 9.3 DUT SVA

优先添加以下 assertion：

- start while busy/done 行为。
- reset/soft_reset 后状态清零。
- AXI valid 保持到 ready。
- burst 不跨 4KB，或 auto split 后每笔 burst 不跨 4KB。
- descriptor FIFO 不 overflow/underflow。
- ping-pong buffer ownership 不冲突。
- pipeline 中 done 只能在所有 inflight tile 完成后置位。
- store row buffer 读写 row index 不越界。
- 固定 SPAD layout 中 A0/A1/B/bias window 不重叠且不越界。

### 9.4 Scoreboard 和 Monitor 收敛

当前验证中大量 golden compare 在 vseq 内部完成。performance 架构引入并发后，建议：

- 增加 tensor-level monitor。
- 将 program/start/done/error/C writeback 形成 transaction。
- 统一送入 scoreboard 和 coverage。
- 减少 vseq 对内部信号和 memory backdoor 的直接依赖。

### 9.5 Coverage 增强

performance 相关覆盖建议：

- `burst_len`：16/32/64/128/256。
- load/compute/store overlap 命中。
- ping/pong buffer 切换。
- descriptor FIFO depth watermark。
- reset during load/compute/store/post/store overlap。
- AXI read/write error during inflight multi-tile。
- last tile with non-aligned M/N/K。
- overflow during pipeline。

## 10. 里程碑总览

| 里程碑 | 阶段目标 | 主要产物 | 风险 |
|---|---|---|---|
| M0 | 建立性能基线 | testbench performance monitor、baseline report | 低 |
| M1 | 低风险参数化 | tile/latency/burst 参数化，4x4 regression 通过 | 中 |
| M2 | DMA/scratchpad 提速 | burst 256、read 4KB auto split、descriptor FIFO、ping-pong 基础 | 中高 |
| M3 | tile pipeline | load/compute/store overlap，64x64 性能显著提升 | 高 |
| M4 | 可扩展 array | 4x4/8x8 参数化构建、基础 testcase、综合/STA 评估 | 高 |
| M5 | signoff 强化 | SVA、coverage、scoreboard、performance regression 收敛 | 中 |

## 11. 推荐执行顺序

推荐最小执行路径：

1. 完成 M0，拿到明确 baseline。
2. 完成 M1，先消除硬编码但保持行为不变。
3. 根据 M0 数据判断下一步：
   - 如果主要瓶颈是 DMA/store，优先做 M2。
   - 如果主要瓶颈是 compute，评估 M4，但仍建议先完成 M2 的 scratchpad/burst 基础能力。
   - 如果 idle cycle 很高，优先做 M3。
4. 每完成一个阶段都运行完整 directed/exception regression，并比较 testbench performance report。
5. 进入 M3/M4 前必须补齐关键 assertion 和 pipeline coverage。

## 12. 初步风险判断

| 优化项 | 工作量 | 性能收益 | 风险 | 建议优先级 |
|---|---:|---:|---:|---|
| testbench performance monitor | 小 | 间接收益 | 低 | P0 |
| tile/latency 参数化 | 中 | 间接收益 | 中 | P0 |
| burst 256 支持 | 中 | 中 | 中 | P1 |
| read 4KB auto split | 中 | 中 | 中 | P1 |
| descriptor FIFO | 中 | 中 | 中高 | P1 |
| ping-pong scratchpad | 大 | 高 | 高 | P0 for pipeline |
| load/compute/store overlap | 大 | 高 | 高 | P0 for performance version |
| 8x8 array | 大 | 高 | 高 | P2，后置 |
| config freeze | 小到中 | 间接收益 | 低 | P0 |
| SVA/coverage 增强 | 中 | 间接收益 | 低到中 | P0 |

## 13. 建议结论

当前 IP 用于通信链路质量预测推理侧时，短期不建议扩展浮点或 mixed precision。更合理的 performance 路线是：

- 第一阶段先量化瓶颈。
- 第二阶段参数化当前 4x4 架构。
- 第三阶段优化 DMA 和 scratchpad。
- 第四阶段实现 tile pipeline。
- 最后再评估是否扩大 array。

这样可以在保持 INT8/INT16 功能稳定的基础上逐步提升吞吐，并把每一步的风险控制在可验证、可回退的范围内。
