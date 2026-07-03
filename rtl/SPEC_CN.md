[English](SPEC_EN.md) | **中文**

# Tensor Accelerator IP 规格说明

## 1. 模块概览

### Module Name

`tensor_accel_top`

### Purpose

`tensor_accel_top` 是一个轻量级整数矩阵乘加加速器 IP。软件通过 AXI-Lite 配置矩阵尺寸、外部矩阵基地址、精度和后处理模式，硬件通过 AXI4 master DMA 从外部存储加载 A/B/Bias，完成 tiled GEMM、后处理和 C 矩阵写回。

### Role in System

该 IP 是系统级可集成计算外设，包含：

* AXI-Lite 配置寄存器块
* AXI4 read/write DMA
* 固定内部 scratchpad 地址规划
* tile 计数与 buffer 管理
* load/compute/post-process/store 控制链路
* 4x4 systolic array 计算核心
* 状态、错误和中断上报

---

## 2. 需求来源

### User-Provided Requirements

* 支持 INT4/INT8/INT16 矩阵乘加，最大矩阵维度为 64。
* 采用 tiled 数据流，保持 C 外部矩阵 row-major 契约。
* B 矩阵由软件预转置，硬件按 B 条带复用读取。
* SPAD 的基地址和大小固定在模块内部，不向软件开放 offset/size 寄存器。
* A buffer 使用 ping-pong，B 条带复用，不设置双 B bank。
* store 支持多行写回，并通过固定 `C_STORE_NBLOCK=2` 的 C store coalescer 合并相邻 N tile 后写入外部 row-major C 矩阵。
* 读 DMA 有 descriptor FIFO，并支持参数化 4KB 自动 split。
* 性能计数逻辑不作为当前 RTL 主路径资源保留。
* 需要可形式验证的关键安全属性。

### Agent-Inferred Requirements

| 序号 | 推断决策 | 原因 |
| ---- | -------- | ---- |
| 1 | 软件只提供外部矩阵基地址，不管理内部 SPAD layout | 当前 RTL 中 `reg_file` 不暴露 SPAD offset/size，`buffer_manager_fsm` 固定 A/B/Bias 窗口 |
| 2 | C 外部布局保持 row-major | 当前 `tensor_writer` row-mode 以 `cfg_active.n_size * OUT_BYTES` 作为外部行 stride |
| 3 | B 外部布局不是原始 row-major B，而是软件预转置/预打包后的条带布局 | 当前 `load_scheduler` 使用 `b_base + col_base * align8(packed_row_bytes(K, precision))` |
| 4 | 当前默认顶层读 4KB auto split 未开启 | `tensor_accel_top.READ_AUTO_SPLIT_4KB` 默认值为 `1'b0` |
| 5 | 写 DMA 仍以跨 4KB 为错误条件 | 当前 `command_fsm` 对 `write_cross_4kb_i` 进入 error |

### Open Questions

| ID | 问题 | 影响 | 当前默认 |
| -- | ---- | ---- | -------- |
| Q1 | 顶层默认是否应把 `READ_AUTO_SPLIT_4KB` 改成 1 | 影响软件约束和错误码语义 | 按当前 RTL: 默认 0，参数可打开 |
| Q2 | B 软件预转置格式是否需要长期作为 ABI 固化 | 影响驱动、测试和系统集成 | 按当前 RTL: 需要预转置/预打包 |
| Q3 | 写 DMA 是否也需要 4KB 自动 split | 影响大矩阵 C 写回健壮性 | 按当前 RTL: 不支持，跨界报错 |
| Q4 | 当前是否支持 K 分块迭代 | 当前 compute 使用完整 K，不做 K tile partial accumulation | 按当前 RTL: 不支持 K 分块，K 一次覆盖 1..64 |

---

## 3. 范围

### Supported Features

* AXI-Lite slave 配置和状态访问。
* AXI4 master read/write，数据总线 64 bit，地址 32 bit。
* `M/N/K` 范围 1..64。
* INT4、INT8 和 INT16 signed 输入。
* 40-bit systolic accumulator，后处理输出 INT32。
* Bias、ReLU、saturation/wrap 模式。
* A ping-pong buffer，B 单 bank 复用，Bias 固定窗口。
* Read descriptor FIFO 和 write descriptor FIFO。
* Read DMA 参数化 4KB split。
* C store coalescer 支持 post-process 完成行后缓存 C 行，并在 N-block 尾或矩阵 N 尾触发较宽的 row-mode 写回。
* done/error/irq/overflow 状态上报。

### Unsupported Features

* 不支持 FP16/BF16/FP32。
* 不支持稀疏矩阵。
* 不支持 cache coherence。
* 不支持 AXI 多 ID 或 out-of-order response。
* 不支持软件配置 SPAD region offset/size。
* 不支持软件提交 descriptor 队列。
* 不支持 C tile-major 外部布局。
* 写 DMA 当前不自动 split 4KB。

### Explicit Non-Goals

* 不实现训练链路、梯度或权重更新。
* 不实现通用矩阵格式转换引擎。
* 不保证当前版本达到最优吞吐。
* 不把性能计数器作为综合主路径资源。

---

## 4. 参数

| 参数 | 默认值 | 合法范围 | 描述 |
| ---- | -----: | -------- | ---- |
| `TILE_M` | `ARRAY_M=4` | 建议 `>=1`，当前验证重点 4 | tile 行数和阵列行数 |
| `TILE_N` | `ARRAY_N=4` | 建议 `>=1`，当前验证重点 4 | tile 列数和阵列列数 |
| `OUT_BYTES` | 4 | 当前固定 4 | C 输出元素字节数，INT32 |
| `BIAS_BYTES` | 4 | 当前固定 4 | Bias 元素字节数，INT32 |
| `COMPUTE_PIPE_LATENCY` | 3 | `>=0` | compute FSM drain 延迟 |
| `MAX_BURST_BEATS` | 16 | 1..256 | 单次 AXI burst 最大 beat 数 |
| `READ_DESC_FIFO_DEPTH` | 4 | `>=1` | 读 descriptor FIFO 深度 |
| `WRITE_DESC_FIFO_DEPTH` | 2 | `>=1` | 写 descriptor FIFO 深度 |
| `C_STORE_NBLOCK` | 2 | 当前验证固定 2 | C 写回侧合并的相邻 N tile 数，不通过寄存器开放 |
| `SPAD_BUFFER_BYTES` | 1024 | 必须容纳最大 A/B/Bias tile | 固定 SPAD 窗口大小 |
| `READ_AUTO_SPLIT_4KB` | `1'b0` | 0/1 | 读 DMA 是否自动切分 4KB boundary |

相关 package 默认值：

| 常量 | 默认值 | 描述 |
| ---- | -----: | ---- |
| `AXIL_ADDR_WIDTH` | 16 | AXI-Lite 地址宽度 |
| `AXIL_DATA_WIDTH` | 32 | AXI-Lite 数据宽度 |
| `AXI_ADDR_WIDTH` | 32 | AXI master 地址宽度 |
| `AXI_DATA_WIDTH` | 64 | AXI master 数据宽度 |
| `SPAD_ADDR_WIDTH` | 16 | scratchpad 地址宽度 |
| `SPAD_DATA_WIDTH` | 32 | scratchpad 数据宽度 |
| `SPAD_BYTES` | 64 KiB | package 地址空间上限；顶层当前实例化 `4 * SPAD_BUFFER_BYTES` |
| `MAX_DIM` | 64 | 最大矩阵维度 |

### Parameter Notes

* `TILE_M/TILE_N` 影响阵列端口、C store coalescer、store FSM、buffer manager 和验证规模。
* `SPAD_BUFFER_BYTES` 必须满足固定窗口不重叠，并能容纳最大 tile。默认 1024B 是当前 4x4 阵列、`MAX_DIM=64` 下 A/B tile 理论上限 512B 的 2 倍。RTL 中有 `ASSERT_ON` 静态断言。
* `C_STORE_NBLOCK=2` 时，store 侧最多把同一 M tile 下两个相邻 N tile 的 C 行合并为一次 row-mode descriptor。当前软件不可配置该参数。
* `READ_AUTO_SPLIT_4KB=1` 时 read burst splitter 会把跨 4KB 的读请求截断到边界内，后续 burst 继续读取剩余数据。
* 写路径没有对应 auto split 参数。

---

## 5. 时钟和复位

| 信号 | 方向 | 描述 |
| ---- | ---: | ---- |
| `clk` | input | 单一主时钟 |
| `rst_n` | input | 低有效异步复位 |

### Reset Requirements

复位后：

* AXI-Lite 和 AXI master valid 输出为安全值。
* command FSM 回到 idle。
* status、error、irq、overflow count 清零。
* descriptor FIFO 为空。
* buffer 状态为空闲。
* compute/post/store 相关状态清零。
* 内部 A/B/Bias panel 和 C store coalescer 处于可重新开始状态。

### Reset Assumptions

* 所有 RTL 处于同一时钟域。
* `rst_n` 可在操作中拉低，模块应回到安全空闲状态。
* 软件可通过 `CTRL.soft_reset` 触发同步软复位，清除当前任务上下文。

---

## 6. 接口契约

### 顶层端口摘要

| 信号组 | 方向 | 位宽 | 描述 |
| ------ | ---: | ---: | ---- |
| `s_axil_aw*`, `s_axil_w*`, `s_axil_b*`, `s_axil_ar*`, `s_axil_r*` | mixed | AXI-Lite 32-bit data, 16-bit addr | 软件配置和状态访问 |
| `m_axi_ar*`, `m_axi_r*` | mixed | AXI4 read, 64-bit data | 外部 A/B/Bias 读取 |
| `m_axi_aw*`, `m_axi_w*`, `m_axi_b*` | mixed | AXI4 write, 64-bit data | 外部 C 写回 |
| `irq` | output | 1 | 完成或错误中断 |

仿真/验证构建在 `ifndef SYNTHESIS` 下额外暴露 `tb_cmd_force_start_i`、`tb_cmd_force_read_error_i`、`tb_cmd_force_write_error_i`、`tb_cmd_force_load_done_i`，用于 directed error-arc 注入。这些端口不属于综合接口契约。

### Interface Groups

* 配置接口：AXI-Lite slave。
* 数据读取接口：AXI4 read master，固定 `ARID=0`，`ARBURST=INCR`。
* 数据写回接口：AXI4 write master，固定 `AWID=0`，`AWBURST=INCR`。
* 内部存储接口：scratchpad 为 32-bit word 存储，不向顶层暴露。
* 中断接口：`irq` 为电平型状态输出，由 `IRQ_STATUS` 或 `CTRL` clear bit 清除。

### Interface Rules

* AXI-Lite 写入先寄存一拍，再更新配置或产生 pulse。
* AXI-Lite 读取返回寄存后一拍的数据。
* AXI master 不使用多个 ID，不支持乱序完成。
* burst size 固定为 64-bit beat。
* 外部 base 地址对齐要求由 `region_checker` 检查：
  * `A_BASE`、`B_BASE`、启用 bias 时 `BIAS_BASE` 必须 8-byte 对齐。
  * `C_BASE` 必须 4-byte 对齐。
* 读写 DMA 错误会锁存到 command FSM error 状态。

---

## 7. 握手和流控

### Transfer Rule

AXI 传输遵循标准 valid/ready：

```systemverilog
transfer = valid && ready;
```

内部 descriptor FIFO：

```systemverilog
push_accept = push_i && !full_o;
pop_accept  = pop_i  && !empty_o;
```

### Input Flow Control

* `load_scheduler` 只有在 read descriptor FIFO ready 时发出 load descriptor。
* `store_fsm` 只有在 write descriptor FIFO ready 且 row ready 条件满足时发出 store descriptor。
* `tensor_loader` 和 `tensor_writer` 以 `busy/done/error` 与上层串接。

### Output Flow Control

* Read DMA 在 `m_axi_rready` 且内部 read buffer 未满时接收 R beat。
* Write DMA 在 `m_axi_wready` 时推进 W beat。
* C store coalescer 允许 post-process 行完成后缓存对应 N-block slot，writer 按行读取合并后的连续 C block。

### Combinational Dependency Policy

| 路径 | 是否允许 | 原因 |
| ---- | -------- | ---- |
| 下游 ready -> 上游 valid | 部分允许 | AXI 和 descriptor 发射存在 ready gating，需关注时序 |
| 下游 ready -> 上游 ready | 允许 | 标准反压传播 |
| 输入 valid -> 输入 ready | 不作为系统级要求 | 主要由 AXI slave/DMA 子模块决定 |

---

## 8. 功能行为

### High-Level Behavior

1. 软件写配置寄存器，包括 `M/N/K`、precision、post-op、sat-mode、外部 A/B/C/Bias base 和 DMA burst length。
2. 软件写 `CTRL.start=1`。
3. `region_checker` 检查矩阵尺寸、precision 和 base 地址对齐。
4. `command_fsm` 初始化 tile 计数。
5. `load_scheduler` 产生 A/B/Bias read descriptor。
6. Read descriptor FIFO 驱动 `tensor_loader`，DMA 读取外部数据并写入内部 scratchpad/panel。
7. `compute_fsm` 启动 wavefront feeder 和 systolic array。
8. accumulator 捕获阵列结果。
9. post-process 执行 bias、ReLU、saturation/wrap。
10. C store coalescer 按行接收 C tile 结果，并按 M tile 和 N-block slot 保存。
11. `store_fsm` 和 `tensor_writer` 在 N-block 尾或矩阵 N 尾以 row-mode 多行写把合并后的 C block 写回 row-major 外部 C 矩阵。
12. 所有 tile 完成后进入 done，必要时产生 irq。

### Cycle-Level Behavior

| 事件 | 条件 | 行为 |
| ---- | ---- | ---- |
| start 接受 | `start_pulse && idle && !done && !error` | latch `cfg` 到 `cfg_active` |
| 非空闲 start | `start_i && state != ST_IDLE` | 进入 error，`ERR_COMMAND_WHILE_BUSY` |
| 配置非法 | `ST_CHECK_CONFIG && !cfg_valid` | 进入 error，记录 checker error |
| load descriptor push | `load_a_start/load_b_start/load_bias_start` | 写入 read descriptor FIFO |
| read DMA done | 单 descriptor 完成 | loader 发出 done，scheduler 更新 pending |
| compute launch | command 发出 `compute_start` | systolic clear，同时锁存 tile metadata |
| post row done | post-process FSM 完成一行 | C store coalescer 写入对应 M tile/N-block slot，store FSM 标记该行 ready |
| store descriptor push | 需要写回的 N-block 行已可用且 write descriptor FIFO ready | 写入 write descriptor FIFO |
| final done | 最后 tile store 完成 | status.done 置位 |

### State and Data Update Rules

* `cfg_active` 只在合法 start 接受时锁存。
* tile 计数在 `sched_init/sched_advance` 时更新。
* A panel 使用两个 bank，根据 `buffer_manager_fsm` 的 `tile_m/tile_n/tile_m_count` 选择 ping-pong。
* B panel 单 bank，跨 `M` tile 复用，在 `tile_m==0` 时重新加载。
* Bias 只在启用 bias 且 `tile_m==0` 时加载。
* C 不在 scratchpad 中持久化，post-process 结果进入 C store coalescer。
* `compute_tile_m/tile_n/col_base/C offset/tile shape` 在 compute launch 时锁存，供 post/store 使用，避免后续 tile 计数推进污染当前 tile 写回上下文。

---

## 9. 延迟、吞吐和顺序

### Latency

* 延迟为可变，取决于矩阵尺寸、AXI ready/valid 反压、burst length、post/store 进度。
* `compute_fsm` 对单 tile 的 valid 窗口约为 `K + ARRAY_M + ARRAY_N + COMPUTE_PIPE_LATENCY` 相关周期。
* `region_checker` 输出相对配置输入存在寄存器延迟。

### Throughput

* 阵列尺寸默认 4x4。
* load 和 compute 已存在一定流水化：下一 tile load 可在当前 tile compute 阶段预取，但受 buffer hazard 和 store 状态约束。
* store 可在 post-process 行完成后以 row-mode 逐行写出，不必等待完整任务完成。
* 对于 `C_STORE_NBLOCK=2`，第一个 N tile 的 post-process 结果只缓存不启动写回；第二个 N tile 或 N 方向尾 tile 完成时启动合并写回，单行写回宽度最多为 `2 * TILE_N * OUT_BYTES`。
* B 和 Bias 跨 `M` 方向复用，减少重复读取。

### Ordering

* tile 顺序按 `tile_n` 外层、`tile_m` 内层推进：先沿 M 方向，再进入下一 N 条带。
* N-block coalescing 不改变外部 C row-major 语义，只改变单次 row-mode descriptor 覆盖的连续列宽。
* 输出 C 维持外部 row-major 矩阵布局。
* 不支持 AXI transaction reorder。
* descriptor FIFO 严格 FIFO 顺序。

---

## 10. 状态机和控制

### FSM Summary

| FSM | 用途 | 复位状态 |
| --- | ---- | -------- |
| `command_fsm` | 顶层任务阶段控制、错误和状态管理 | `ST_IDLE` |
| `tile_count_fsm` | tile_m/tile_n 计数和 row/col valid 生成 | 0 |
| `buffer_manager_fsm` | A ping-pong buffer 选择、B/Bias 固定窗口管理、hazard 判断 | free |
| `load_scheduler` | 产生 A/B/Bias read descriptor，等待 DMA drain | `LS_IDLE` |
| `compute_fsm` | systolic launch/valid/done 时序 | idle |
| `post_process_fsm` | post-process 行完成标记 | idle |
| `c_store_coalescer` | 缓存 post-process C 行并合并相邻 N tile 结果供 writer 读取 | clear 后为 0 |
| `store_fsm` | row-ready 驱动的 store descriptor 生成，并锁存 active M tile 上下文 | idle |
| `tensor_loader` | 行模式 read DMA 调度 | idle |
| `tensor_writer` | 行模式 write DMA 调度 | idle |
| `axi_read_dma` | AXI AR/R 和 SPAD 写入 | `S_IDLE` |
| `axi_write_dma` | AXI AW/W/B 和 SPAD 读取 | idle |

### command_fsm State List

| 状态 | 含义 | 退出条件 |
| ---- | ---- | -------- |
| `ST_IDLE` | 等待 start | `start_i` |
| `ST_CHECK_CONFIG` | 检查配置 | valid 或 error |
| `ST_PREPARE_TILE` | 初始化 tile | 下一拍 |
| `ST_LOAD_TILE` | 首个 tile load | load done 或 error |
| `ST_COMPUTE_TILE` | 当前 tile compute，可触发预取 | compute done 或 pipe load |
| `ST_PIPE_LOAD` | load/compute 并行 | load 和 compute 均完成 |
| `ST_PIPE_WAIT_LOAD` | compute 已完成，等 load | load done |
| `ST_PIPE_WAIT_COMPUTE` | load 已完成，等 compute | compute done |
| `ST_POST_PROCESS_TILE` | post-process 并可启动 store | post/store 条件满足 |
| `ST_WAIT_STORE_SLOT` | 等待 store 空闲槽 | store 可启动 |
| `ST_STORE_TILE` | 等待当前 store | write done |
| `ST_WAIT_FINAL_STORE` | 等待最后一次 store | write done |
| `ST_DONE` | 任务完成 | clear done |
| `ST_ERROR` | 错误锁存 | clear error |

### Illegal State Behavior

* 各主要 FSM default 分支返回 idle。
* command FSM 在非法/忙时 start、DMA error、4KB crossing、timeout 时进入 error。
* `compute_done_i` 通过 `compute_issued_q` gate 后才作为当前 tile 完成条件，避免上一个 tile 的 done 残留造成错误转移。
* `store_required_i` 为 0 的 tile 只进行 post-process/coalescer 写入，不启动 write descriptor。
* `ASSERT_ON` 下检查 FIFO 溢出/下溢、store descriptor 上下文、固定 SPAD 窗口不重叠等条件。

---

## 11. 数据格式和算术

### Data Format

| 数据 | 格式 | 有符号 | 位宽 | 备注 |
| ---- | ---- | ------ | ---: | ---- |
| A INT4 | signed integer | 是 | 4 | 两个元素打包到 1 byte，低 nibble 为偶数 K，符号扩展到 16 |
| B INT4 | signed integer | 是 | 4 | 软件预转置条带布局，两个 K 元素打包到 1 byte，符号扩展到 16 |
| A INT8 | signed integer | 是 | 8 | 从 64-bit AXI beat 拆成 byte，符号扩展到 16 |
| B INT8 | signed integer | 是 | 8 | 软件预转置布局，符号扩展到 16 |
| A/B INT16 | signed integer | 是 | 16 | 需要 2-byte lane strobe 完整 |
| MAC product | signed integer | 是 | 32 | `mac_unit` 内部乘法 |
| accumulator | signed integer | 是 | 40 | systolic array 输出 |
| Bias | signed integer | 是 | 32 | 每个 N 列一个 bias |
| C output | signed integer | 是 | 32 | row-major 写回 |

### Arithmetic Rules

* INT4、INT8 和 INT16 均按 signed 乘法处理。
* MAC 内部 product 为 32-bit signed，accumulator 为 40-bit signed。
* post-process 顺序为 bias、ReLU、saturation/wrap。
* `SAT_WRAP` 下输出截断到 32-bit。
* `SAT_SATURATE` 下输出饱和到 int32 范围。
* overflow 会置位 `status.overflow_seen` 并累加 `OVF_COUNT`。

---

## 12. 存储和缓冲

| 存储 | 类型 | 深度/容量 | 位宽 | 用途 |
| ---- | ---- | --------: | ---: | ---- |
| `scratchpad` | SRAM-like | 默认 4 KiB | 32 | DMA 写入 A/B/Bias 的统一存储接口 |
| A panel bank 0/1 | 寄存器阵列 | `TILE_M * MAX_DIM` each | 16 | A ping-pong compute panel |
| B panel | 寄存器阵列 | `MAX_DIM * TILE_N` | 16 | B 条带复用 panel |
| Bias vector | 寄存器阵列 | `TILE_N` | 32 | bias 条带 |
| read descriptor FIFO | FIFO | 默认 4 | `dma_desc_t` 117 bits | A/B/Bias read descriptor |
| write descriptor FIFO | FIFO | 默认 2 | `dma_desc_t` 117 bits | C row-mode write descriptor |
| read DMA buffer | FIFO | 2 | 65 | R channel buffering |
| C store coalescer | M tile indexed row buffer | `MTILE_SLOTS * TILE_M * TILE_N * C_STORE_NBLOCK` | 32 | 合并同一 M tile 下相邻 N tile 的 C 行 |

### 固定 SPAD 地址规划

| 窗口 | Base | Size | 用途 |
| ---- | ---- | ---- | ---- |
| A bank 0 | `0x0000` | `SPAD_BUFFER_BYTES` | A tile buffer 0 |
| A bank 1 | `SPAD_BUFFER_BYTES`，默认 `0x0400` | `SPAD_BUFFER_BYTES` | A tile buffer 1 |
| B bank | `2 * SPAD_BUFFER_BYTES`，默认 `0x0800` | `SPAD_BUFFER_BYTES` | B 条带 buffer |
| Bias bank | `3 * SPAD_BUFFER_BYTES`，默认 `0x0c00` | `SPAD_BUFFER_BYTES` | Bias 条带 buffer |

### Buffer Behavior

* A buffer 用 ping-pong 方式减少 load/compute hazard。当前选择公式为 `tile_m[0] ^ (tile_n[0] & tile_m_count[0])`，用于避免跨 N 时连续选中同一 A buffer。
* B/Bias 只在 `tile_m==0` 时加载，沿同一 N 条带复用。
* C store coalescer 支持 post-process 行完成后立即写入对应 slot；store FSM 使用 row-ready bitmap 控制 writer 逐行读取。
* FIFO full/empty 的非法 push/pop 在 `ASSERT_ON` 下断言。

---

## 13. 寄存器映射

所有寄存器为 32-bit，AXI-Lite 地址为 byte address。

| 地址 | 名称 | R/W | 描述 |
| ---- | ---- | --- | ---- |
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
| `0x0054` | `IRQ_STATUS` | RO/W1C | bit0 irq, write bit0 clears irq |
| `0x0058` | `OVF_COUNT` | RO | overflow event count |
| `0x005c` | `ERROR_CODE` | RO | latched error code |

### Register Notes

* `CTRL.start`、`soft_reset`、`clear_done`、`clear_error`、`IRQ_STATUS[0]` 是 pulse/W1C 行为。
* 配置寄存器支持 byte strobe merge。
* SPAD offset/size 不存在软件可见寄存器。
* 软件应在 `busy=0` 且无未清除 `done/error` 时发起新任务。

---

## 14. 外部数据布局

### A Layout

A 以 row-major 的预打包行存储：

```text
A_addr(row) = A_BASE + row * align8(packed_row_bytes(K, precision))
```

每个 tile 读取 `tile_rows` 行，每行 `align8(packed_row_bytes(K, precision))` 字节。INT4 模式下每 byte 存两个 signed 4-bit 元素，偶数 K 放低 nibble，奇数 K 放高 nibble，K 为奇数时最后一个 byte 的高 nibble 不使用。

### B Layout

B 由软件预转置/预打包为按输出列连续的条带：

```text
B_addr(col) = B_BASE + col * align8(packed_row_bytes(K, precision))
```

每个 N tile 读取 `tile_cols` 条，每条 `align8(packed_row_bytes(K, precision))` 字节。硬件把外部条带解释为 `B[k][col]`。INT4 的 nibble 打包顺序与 A 相同。

### Bias Layout

Bias 为 INT32 向量：

```text
Bias_addr(col) = BIAS_BASE + col * 4
```

### C Layout

C 外部布局保持 row-major INT32：

```text
C_addr(row, col) = C_BASE + (row * N + col) * 4
```

Store 以 N-block 为单位生成 row-mode descriptor。对 `C_STORE_NBLOCK=2`，若当前 tile 是 N-block slot 0 且不是 N 尾，则只缓存不写回；若当前 tile 是 slot 1 或 N 尾，则写回从该 N-block 起始列开始的连续列块：

```text
slot = tile_n % C_STORE_NBLOCK
block_col_base = col_base - slot * TILE_N
base = C_BASE + ((row_base * N + block_col_base) * 4)
row_bytes = (slot * TILE_N + tile_cols) * 4
ext_row_stride = N * 4
row_count = tile_rows
spad_row_stride = C_STORE_NBLOCK * TILE_N * 4
```

该机制扩大单次 row-mode 写回粒度，但不改变外部 C 的 row-major ABI。

---

## 15. 错误和边界情况

### Error Behavior

| 条件 | 预期行为 | 恢复方式 |
| ---- | -------- | -------- |
| `M/N/K` 不在 1..64 | `ERR_ILLEGAL_MATRIX_SIZE` | 写 `CTRL.clear_error` 或 soft reset |
| precision 非 0/1/2 | `ERR_ILLEGAL_PRECISION` | 清错误后重配 |
| base 地址不满足对齐 | `ERR_UNALIGNED_BASE_ADDR` | 清错误后重配 |
| 非 idle 状态 start | `ERR_COMMAND_WHILE_BUSY` | 清错误 |
| AXI read `RRESP[1]` | `ERR_AXI_READ_ERROR` | 清错误 |
| AXI write `BRESP[1]` | `ERR_AXI_WRITE_ERROR` | 清错误 |
| 4KB crossing 且未 split | `ERR_BURST_CROSS_4KB` | 调整地址/长度或开启 read split |
| watchdog timeout | `ERR_INTERNAL_TIMEOUT` | soft reset 或清错误 |

### Corner Cases

* `M/N` 不是 `TILE_M/TILE_N` 整数倍时通过 row/col valid mask 处理。
* `K` 最大 64，当前 compute 对完整 K 一次计算。
* Bias 只有在 post-op 启用 bias 时读取。
* `read row_count_i==0` 或 `write row_count_i==0` 在 loader/writer 中等效为 1 行。
* 当 N 不是 `C_STORE_NBLOCK * TILE_N` 的整数倍时，N 尾 tile 会触发部分 N-block 写回，`row_bytes` 覆盖从 N-block 起始列到有效尾列。
* `burst_len=0` 会使 burst splitter invalid，可能导致 DMA error。

---

## 16. CDC 和时序假设

### CDC

本 IP 为单时钟设计，没有 CDC 跨域。

### Timing-Awareness

潜在时序敏感点：

* load address pipeline 中的乘法和 align8 计算。
* C offset 计算：`row_base * N + col_base`。
* wavefront feeder 对 panel 的多维数组选择。
* systolic array MAC 链和 accumulator。
* AXI DMA burst splitter 的 4KB/长度比较。
* C store coalescer 读地址解码。

### Timing Mitigation

* `load_scheduler` 已将地址计算拆为多级寄存器。
* A/B/C 地址相关配置不经软件 offset/size 动态规划，降低控制面复杂度。
* C 不在 scratchpad 中持久化，C store coalescer 只缓存有限 N-block，降低完整 C 矩阵片上缓存压力。
* Read DMA 内部有小 FIFO 缓冲 R channel。

---

## 17. 必需断言

RTL 或 formal 中应覆盖：

* 固定 SPAD 窗口不重叠且不超过 `SPAD_BYTES`。
* 最大 A/B/Bias tile 能放入各自固定窗口。
* descriptor FIFO 不发生 full push 或 empty pop。
* store descriptor push 时必须存在 active store context。
* store descriptor row count 非零。
* `c_store_coalescer` 写入的 M tile、row、N-block slot 和读取 row 均在合法范围内。
* `dma_burst_splitter` 不产生超过 `MAX_BURST_BEATS` 或跨 4KB 的非法 burst。
* `axi_read_dma` 在 `AUTO_SPLIT_4KB=1` 时不发出跨 4KB AR burst。
* AXI read/write error response 能锁存为 error。
* `wavefront_feeder` 输出与 skewed A/B panel 索引一致。
* `systolic_array` reset/clear 后 accumulator 和 overflow 清零。
* `region_checker` 错误优先级和输出延迟符合实现。

---

## 18. 最小验证要求

### Required Dynamic Tests

* INT8 4x4 基础通路。
* INT16 4x4 基础通路。
* INT4 4x4 基础通路。
* 矩形矩阵。
* 非对齐尺寸。
* bias、ReLU、saturation。
* back-to-back command。
* precision switch，覆盖 INT4/INT8/INT16。
* IRQ clear 和 done/error clear。
* AXI read SLVERR。
* 合法随机矩阵配置。
* row-mode C 写回检查。

### Required Formal Targets

当前 formal 目录应至少覆盖：

* Phase 1: `dma_burst_splitter`、`dma_descriptor_fifo`、`axi_read_dma`
* Phase 2: `buffer_manager_fsm`、`store_fsm`、`c_store_coalescer`/store row ready-read safety
* Phase 3: `compute_fsm`、`wavefront_feeder`、`systolic_array`
* Phase 4: `region_checker`

### Required Review Evidence

* RTL 编译通过。
* 基础动态仿真通过。
* formal/STA 证据按项目阶段另行要求；当前动态收敛阶段不作为每轮 SPEC 更新的完成条件。
* 已知参数默认值和软件 ABI 记录在本 SPEC。

---

## 19. 最终 SPEC 摘要

### Confirmed Design Decisions

* 顶层 IP 为 AXI-Lite 配置、AXI4 master DMA 的单时钟矩阵加速器。
* 默认阵列规模为 4x4，最大矩阵维度为 64。
* A 使用 ping-pong buffer，B 单 bank 沿 M 方向复用。
* SPAD 地址空间由硬件固定规划，不暴露 offset/size 寄存器。
* C 外部矩阵契约保持 row-major，store 使用多行写和固定 `C_STORE_NBLOCK=2` 的 N-block coalescing 扩大写回粒度。
* B 外部输入要求软件预转置/预打包。
* 读 DMA 具备参数化 4KB auto split，顶层默认未开启。

### Human Review Required

| ID | 项目 | 重要性原因 |
| -- | ---- | ---------- |
| HR1 | 是否将 `READ_AUTO_SPLIT_4KB` 默认改为 1 | 影响软件是否需要规避 read 4KB crossing |
| HR2 | 是否为 write DMA 增加 4KB auto split | 当前 C row write 仍可能遇到 4KB crossing 错误 |
| HR3 | 是否正式冻结 B 预转置 ABI | 影响驱动、测试数据生成和系统集成文档 |
| HR4 | 是否移除或重定义未实际使用的 K tile 语义 | 影响未来强 weight-stationary 或 K 分块改造 |

### SPEC Status

当前状态：待审查。本文档以当前 RTL 实现为准，可作为后续验证、驱动和系统集成的基线规格。
