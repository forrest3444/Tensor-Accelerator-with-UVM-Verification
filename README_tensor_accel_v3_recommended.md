# Lightweight Multi-Precision Tensor Accelerator V3 Specification

> 版本定位：基于前期讨论形成的 **V3 推荐规格**。  
> 目标不是复刻完整 TPU，也不是实现满血竞赛级多精度浮点张量处理器，而是设计一个 **工程化、可落地、适合秋招展示的推理型张量计算加速器 IP**。

---

## 1. 项目定位

### 1.1 项目名称

推荐英文名：

```text
Lightweight Multi-Precision Tensor Accelerator with AXI4 DMA and UVM Verification
```

推荐中文名：

```text
轻量级多精度张量计算加速器设计与 UVM 验证
```

### 1.2 项目目标

本项目面向边缘 AI 推理场景，设计一个基于 **4×4 systolic array** 的矩阵乘加加速器，支持：

- INT8 / INT16 多精度整数计算；
- INT32 累加；
- 最大 64×64 矩阵计算；
- AXI-Lite 配置接口；
- AXI4-Full Master DMA 数据搬运；
- 统一 scratchpad 地址空间；
- 可配置 tensor region；
- bias / ReLU / saturation 后处理；
- overflow / error / irq 状态上报；
- UVM 验证闭环。

### 1.3 项目边界

本项目聚焦 **推理型 tensor accelerator IP**，暂不支持训练链路。

不支持内容包括：

```text
1. 不支持 loss / gradient / weight update
2. 不支持完整训练链路
3. 不支持 FP16 / BF16 / TF32 / FP32
4. 不支持结构化稀疏
5. 不支持多 AXI ID
6. 不支持 AXI out-of-order response
7. 不支持 cache coherence
8. 不强制 FPGA 上板
9. 不强制 PPA / 功耗优化
```

这些功能可以作为 Future Work。

---

## 2. V3 设计 Profile

为了兼顾项目可落地性和工程展示价值，V3 分为两个 profile：

```text
V3 Base Profile       ：功能完整、优先落地
V3 Performance Profile：性能增强、用于加分展示
```

### 2.1 V3 Base Profile

Base Profile 是第一阶段必须完成的目标。

```text
1. 最大矩阵尺寸 M/N/K <= 64
2. 4×4 systolic array
3. INT8 / INT16 输入
4. INT32 accumulator
5. AXI-Lite Slave 配置接口
6. AXI4-Full Master 数据接口
7. 统一 scratchpad 地址空间
8. 可配置 A/B/C/Bias region offset/size
9. AXI burst length 支持 1/4/8/16
10. Read/Write outstanding depth = 1
11. 串行 tile load：LOAD_A → LOAD_B → LOAD_BIAS
12. 4KB boundary 检查，跨界可先报错
13. 支持 bias / ReLU / saturation
14. 支持 UVM directed/random 验证
```

### 2.2 V3 Performance Profile

Performance Profile 是推荐增强目标，适合在 Base Profile 稳定后加入。

```text
1. AXI4 burst length up to 256 beats
2. Read outstanding depth = 2
3. Write outstanding depth = 1 或 2
4. LOAD_TILE_PARALLEL 并行加载状态
5. A/B/bias burst 交错发起
6. 支持 4KB boundary 自动拆分
7. burst descriptor FIFO depth = 2
8. 支持更高效的 tile load/store 调度
```

---

## 3. 总体架构

### 3.1 系统框图

```text
                       CPU / Host / Testbench
                                │
                                │ AXI-Lite Slave
                                ▼
                     ┌─────────────────────┐
                     │ Register File        │
                     │ CTRL / STATUS / CFG  │
                     └──────────┬──────────┘
                                │
                                ▼
                     ┌─────────────────────┐
                     │ Command FSM          │
                     │ Tile Scheduler       │
                     └──────────┬──────────┘
                                │
          ┌─────────────────────┼─────────────────────┐
          │                     │                     │
          ▼                     ▼                     ▼
 ┌────────────────┐    ┌────────────────┐    ┌────────────────┐
 │ AXI Read DMA    │    │ AXI Write DMA   │    │ Error / IRQ     │
 └───────┬────────┘    └───────┬────────┘    └────────────────┘
         │                     │
         │ AXI4-Full Master    │ AXI4-Full Master
         ▼                     ▼
              External DDR / AXI Memory Model
         ▲                     │
         │                     ▼
 ┌────────────────────────────────────────────────────┐
 │             Unified Scratchpad Address Space        │
 │                                                    │
 │  A Region / B Region / C Region / Bias Region       │
 │  programmable offset + programmable size            │
 └───────────────────────┬────────────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ 4×4 Systolic Array   │
              │ INT8/INT16 MAC       │
              └──────────┬──────────┘
                         ▼
              ┌─────────────────────┐
              │ Accumulator          │
              │ Bias / ReLU / SAT    │
              └──────────┬──────────┘
                         ▼
                    Output Region
```

### 3.2 数据流

完整任务链路：

```text
寄存器配置
→ start
→ 配置检查
→ DMA 读取 A/B/bias
→ 写入 unified scratchpad
→ tile scheduler 调度计算
→ systolic array 执行矩阵乘加
→ bias / ReLU / saturation 后处理
→ C tile 写回 scratchpad
→ DMA 写回外部 memory
→ done / irq / status 上报
```

---

## 4. 计算规格

### 4.1 支持计算

基础矩阵乘：

```text
C = A × B
```

带 bias：

```text
C = A × B + bias
```

带 ReLU：

```text
C = ReLU(A × B + bias)
```

带 saturation：

```text
C = Saturate(ReLU(A × B + bias))
```

建议固定后处理顺序为：

```text
accumulate → bias add → ReLU → saturation → output write
```

### 4.2 数据精度

| 模式 | A 输入 | B 输入 | 累加 | 输出 |
|---|---:|---:|---:|---:|
| INT8 mode | signed int8 | signed int8 | signed int32 | signed int32 |
| INT16 mode | signed int16 | signed int16 | signed int32 | signed int32 |

V3 建议输出统一为 INT32，避免过早引入输出量化复杂度。

### 4.3 矩阵尺寸

```text
1 <= M <= 64
1 <= N <= 64
1 <= K <= 64
```

支持非 4 对齐尺寸：

```text
当 M/N 不是 4 的整数倍时，最后一个 tile 通过 valid mask 处理。
当 K 不是内部 K tile 的整数倍时，最后一个 K tile 通过 valid mask 处理。
```

### 4.4 Tiling 策略

阵列规模固定为：

```text
ARRAY_M = 4
ARRAY_N = 4
```

每次计算一个 C tile：

```text
C_tile = 4 × 4
```

对 64×64 输出矩阵：

```text
tile_m_count = ceil(M / 4)
tile_n_count = ceil(N / 4)
```

若 M=N=64，则输出 tile 数量为：

```text
16 × 16 = 256 tiles
```

每个 C tile 沿 K 方向累加。

---

## 5. Systolic Array 规格

### 5.1 阵列结构

V3 使用：

```text
4×4 PE array
```

每个 PE 包含：

```text
1. A 数据寄存器
2. B/weight 数据寄存器
3. INT8 / INT16 乘法单元
4. INT32 accumulator
5. valid 传播逻辑
6. tile mask 支持
```

### 5.2 数据流风格

推荐采用：

```text
weight-stationary dataflow
```

基本思想：

```text
1. B tile / weight tile 预加载或保持在 PE 内部
2. A 数据按节拍输入阵列
3. partial sum 在阵列内累加
4. C tile 计算完成后输出到后处理模块
```

### 5.3 设计约束

V3 不追求高频 PPA，而追求结构清晰和可验证性：

```text
1. PE 阵列优先保证功能正确
2. valid/mask 传播逻辑要清晰
3. 支持 reset during compute
4. 支持 tile 边界处理
5. 支持 INT8 / INT16 precision mode
```

---

## 6. Unified Scratchpad 规格

### 6.1 基本思想

V3 将原先固定 A/B/C/Bias buffer 分区升级为：

```text
Unified Scratchpad Address Space + Programmable Tensor Regions
```

也就是内部只有一个统一 scratchpad 地址空间，A/B/C/Bias 通过寄存器配置 offset 和 size。

### 6.2 Region 配置

推荐寄存器：

```text
A_SPAD_OFFSET
A_SPAD_SIZE
B_SPAD_OFFSET
B_SPAD_SIZE
C_SPAD_OFFSET
C_SPAD_SIZE
BIAS_SPAD_OFFSET
BIAS_SPAD_SIZE
```

每个 region 表示：

```text
region_start = SPAD_BASE + REGION_OFFSET
region_end   = region_start + REGION_SIZE - 1
```

### 6.3 配置检查

任务启动前，Command FSM 需要检查：

```text
1. region 是否越界
2. region 是否重叠
3. region size 是否满足当前 M/N/K/precision/post-op 配置
4. region offset 是否满足内部访问对齐
5. C region 是否足够容纳输出矩阵
6. bias region 是否在 bias enable 时有效
```

新增错误码：

```text
ERROR_REGION_OVERLAP
ERROR_SPAD_OUT_OF_RANGE
ERROR_REGION_TOO_SMALL
```

### 6.4 优点

统一 scratchpad 的优势：

```text
1. 支持不同矩阵尺寸下灵活划分 buffer
2. 支持 INT8 / INT16 不同容量需求
3. 便于后续扩展 double buffering
4. 更接近真实 accelerator memory subsystem
```

---

## 7. 外部 Memory 数据布局

### 7.1 数据布局

V3 规定外部 memory 中 tensor 使用 row-major 布局：

```text
A[M][K]    row-major
B[K][N]    row-major
C[M][N]    row-major
bias[N]    row-major
```

### 7.2 外部基地址

由寄存器配置：

```text
A_BASE
B_BASE
C_BASE
BIAS_BASE
```

### 7.3 对齐约束

推荐 V3 约束：

```text
1. A_BASE / B_BASE / C_BASE / BIAS_BASE 必须按 AXI data width 对齐
2. 不支持 unaligned access
3. 不生成 narrow transfer
4. tensor 数据按 row-major 连续存储
5. tensor size 建议按 AXI beat 对齐，不足由软件 padding
```

说明：

```text
V3 重点不是做通用 DMA IP，因此允许通过软件 padding 简化最后一个 beat 的处理。
```

---

## 8. AXI-Lite Slave 控制接口

### 8.1 用途

AXI-Lite Slave 用作 control plane：

```text
CPU / Host 通过 AXI-Lite 配置寄存器、启动任务、查询状态、中断清除。
```

### 8.2 参数

推荐参数：

```text
AXIL_ADDR_WIDTH = 16
AXIL_DATA_WIDTH = 32
```

### 8.3 寄存器表

| 地址 | 名称 | 功能 |
|---:|---|---|
| `0x0000` | `CTRL` | start / soft_reset / irq_en |
| `0x0004` | `STATUS` | busy / done / error / irq |
| `0x0008` | `M_SIZE` | M 维度 |
| `0x000C` | `N_SIZE` | N 维度 |
| `0x0010` | `K_SIZE` | K 维度 |
| `0x0014` | `PRECISION` | INT8 / INT16 |
| `0x0018` | `POST_OP` | none / bias / ReLU / bias+ReLU |
| `0x001C` | `SAT_MODE` | wrap / saturate |
| `0x0020` | `A_BASE` | A 外部 memory 基地址 |
| `0x0024` | `B_BASE` | B 外部 memory 基地址 |
| `0x0028` | `C_BASE` | C 外部 memory 基地址 |
| `0x002C` | `BIAS_BASE` | bias 外部 memory 基地址 |
| `0x0030` | `A_SPAD_OFFSET` | A region scratchpad offset |
| `0x0034` | `A_SPAD_SIZE` | A region size |
| `0x0038` | `B_SPAD_OFFSET` | B region scratchpad offset |
| `0x003C` | `B_SPAD_SIZE` | B region size |
| `0x0040` | `C_SPAD_OFFSET` | C region scratchpad offset |
| `0x0044` | `C_SPAD_SIZE` | C region size |
| `0x0048` | `BIAS_SPAD_OFFSET` | bias region scratchpad offset |
| `0x004C` | `BIAS_SPAD_SIZE` | bias region size |
| `0x0050` | `DMA_CFG` | burst length / outstanding config |
| `0x0054` | `IRQ_STATUS` | 中断状态 |
| `0x0058` | `OVF_COUNT` | 溢出计数 |
| `0x005C` | `ERROR_CODE` | 错误码 |

### 8.4 CTRL

建议 bit 定义：

| Bit | 名称 | 说明 |
|---:|---|---|
| 0 | `start` | 写 1 启动任务 |
| 1 | `soft_reset` | 写 1 触发软复位 |
| 2 | `irq_en` | 中断使能 |
| 3 | `clear_done` | 清 done |
| 4 | `clear_error` | 清 error |
| 31:5 | reserved | 保留 |

### 8.5 STATUS

建议 bit 定义：

| Bit | 名称 | 说明 |
|---:|---|---|
| 0 | `busy` | 正在执行任务 |
| 1 | `done` | 任务完成 |
| 2 | `error` | fatal error |
| 3 | `irq` | 中断状态 |
| 4 | `overflow_seen` | 本次任务出现过溢出 |
| 31:5 | reserved | 保留 |

---

## 9. AXI4-Full Master 数据接口

### 9.1 用途

AXI4-Full Master 用作 data plane：

```text
Accelerator 通过 AXI4-Full Master 自主从外部 memory 读取 A/B/bias，
并将 C 写回外部 memory。
```

### 9.2 推荐参数

```text
AXI_ADDR_WIDTH = 32
AXI_DATA_WIDTH = 64
AXI_ID_WIDTH   = 1 或 fixed ID = 0
```

可以预留参数化到：

```text
AXI_DATA_WIDTH = 128
```

但 V3 推荐优先实现 64 bit，降低 pack/unpack 难度。

### 9.3 支持特性

V3 推荐支持：

```text
1. INCR burst
2. aligned transfer
3. burst length 1 ~ 256 beats
4. fixed ID = 0
5. read burst for A / B / bias
6. write burst for C
7. OKAY / SLVERR / DECERR response handling
8. 4KB boundary handling
```

### 9.4 不支持特性

V3 不支持：

```text
1. WRAP burst
2. FIXED burst
3. unaligned transfer
4. narrow transfer
5. multiple AXI ID
6. out-of-order response
7. exclusive access
8. cache / protection / QoS 高级属性
```

可以在文档中称为：

```text
AXI4-Full Restricted Master Profile
```

---

## 10. DMA 规格

### 10.1 DMA 功能

DMA 负责：

```text
1. load A tile
2. load B tile
3. load bias
4. store C tile
5. AXI burst 生成
6. 4KB boundary 处理
7. AXI response error 捕获
8. 将数据写入/读出 unified scratchpad
Base DMA：
  - 64-bit AXI
  - 8-byte aligned address
  - 8-byte aligned byte_len
  - WSTRB always 8'hFF
  - burst length max 16 beats
  - 4KB crossing detect only
  - row stride padding in scratchpad

Performance DMA：
  - support partial last beat
  - support WSTRB
  - burst length up to 256
  - 4KB auto split
  - outstanding depth = 2
```

### 10.2 Burst Length

Base Profile：

```text
burst length: 1 / 4 / 8 / 16
```

Performance Profile：

```text
burst length: 1 ~ 256
```

AXI 编码：

```text
ARLEN/AWLEN = burst_beats - 1
```

### 10.3 Outstanding Depth

Base Profile：

```text
read_outstanding_depth  = 1
write_outstanding_depth = 1
```

Performance Profile：

```text
read_outstanding_depth  = 2
write_outstanding_depth = 1 or 2
```

约束：

```text
1. AXI ID fixed to 0
2. 不支持乱序返回
3. burst descriptor FIFO depth = outstanding depth
```

### 10.4 4KB Boundary 处理

AXI4 INCR burst 不允许跨越 4KB boundary。

Base Profile 可以先选择：

```text
跨 4KB boundary 报错
```

Performance Profile 推荐实现：

```text
自动拆分为多个合法 burst
```

拆分逻辑：

```text
remaining_bytes = total_bytes_to_transfer
current_addr    = base_addr

while remaining_bytes > 0:
    bytes_to_4kb = 4096 - current_addr[11:0]
    max_burst_bytes_by_4kb = bytes_to_4kb
    max_burst_bytes_by_axi = 256 * beat_bytes

    burst_bytes = min(remaining_bytes,
                      max_burst_bytes_by_4kb,
                      max_burst_bytes_by_axi)

    issue burst

    current_addr     += burst_bytes
    remaining_bytes  -= burst_bytes
```

约束：

```text
1. current_addr 必须 beat-aligned
2. burst_bytes 必须是 beat_bytes 的整数倍
3. tensor size 建议由软件 padding 到 beat 对齐
```

### 10.5 Burst Descriptor

Performance Profile 建议增加 descriptor FIFO。

Descriptor 字段：

```text
addr
byte_len
tensor_type
tile_index
target_spad_offset
is_last
```

其中 `tensor_type` 可以包括：

```text
A_TILE
B_TILE
BIAS
C_TILE
```

---

## 11. 控制 FSM 与调度

### 11.1 推荐顶层 FSM

为了支持 64×64 矩阵和 tile 化计算，推荐顶层 FSM 使用 tile-oriented flow：

```text
IDLE
CHECK_CONFIG
PREPARE_TILE
LOAD_TILE
LOAD_TILE_PARALLEL
COMPUTE_TILE
POST_PROCESS_TILE
STORE_TILE
NEXT_TILE
DONE
ERROR
```

### 11.2 Base Profile 控制流

Base Profile 可以使用串行加载：

```text
IDLE
CHECK_CONFIG
PREPARE_TILE
LOAD_A_TILE
LOAD_B_TILE
LOAD_BIAS
COMPUTE_TILE
POST_PROCESS_TILE
STORE_TILE
NEXT_TILE
DONE
ERROR
```

### 11.3 Performance Profile 控制流

Performance Profile 使用并行加载状态：

```text
LOAD_TILE_PARALLEL
```

该状态下：

```text
1. load scheduler 根据 outstanding slot 发起 burst
2. A/B/bias burst 可以交错发起
3. read DMA 通过 descriptor 区分返回数据目标
4. 数据写入对应 scratchpad region
5. A/B/bias 依赖满足后进入 COMPUTE_TILE
```

注意：

```text
所谓并行加载不是多个 AXI read physical channel，
而是在同一个 AXI read master 上利用 outstanding transaction
交错发起 A/B/bias read burst。
```

### 11.4 Tile Loop

推荐逻辑：

```text
for tile_m in 0 .. ceil(M/4)-1:
  for tile_n in 0 .. ceil(N/4)-1:
    clear C_tile accumulator

    for tile_k in 0 .. ceil(K/K_TILE)-1:
      load A tile
      load B tile
      compute partial sum

    post-process C tile
    store C tile
```

---

## 12. 后处理模块

### 12.1 支持模式

`POST_OP` 支持：

| 编码 | 模式 |
|---:|---|
| 0 | none |
| 1 | bias |
| 2 | ReLU |
| 3 | bias + ReLU |

### 12.2 Saturation

`SAT_MODE` 支持：

| 编码 | 模式 |
|---:|---|
| 0 | wrap / truncate |
| 1 | saturate |

### 12.3 Overflow

溢出建议定义为 status event，不作为 fatal error：

```text
overflow is a status event, not a fatal error
```

行为：

```text
1. 发生溢出时 OVF_COUNT 增加
2. STATUS.overflow_seen 置位
3. 若 SAT_MODE = saturate，则结果钳位
4. 若 SAT_MODE = wrap，则结果按截断/wrap 处理
5. STATUS.error 不因 overflow 自动置位
```

---

## 13. 错误处理

### 13.1 错误码

推荐错误码：

| 错误码 | 名称 | 含义 |
|---:|---|---|
| `0x00` | `NO_ERROR` | 无错误 |
| `0x01` | `ILLEGAL_MATRIX_SIZE` | 非法 M/N/K |
| `0x02` | `ILLEGAL_PRECISION` | 非法 precision mode |
| `0x03` | `UNALIGNED_BASE_ADDR` | 外部 memory base 未对齐 |
| `0x04` | `AXI_READ_ERROR` | AXI read SLVERR/DECERR |
| `0x05` | `AXI_WRITE_ERROR` | AXI write SLVERR/DECERR |
| `0x06` | `COMMAND_WHILE_BUSY` | busy 时再次 start |
| `0x07` | `INTERNAL_TIMEOUT` | 内部超时 |
| `0x08` | `REGION_OVERLAP` | scratchpad region 重叠 |
| `0x09` | `SPAD_OUT_OF_RANGE` | scratchpad region 越界 |
| `0x0A` | `REGION_TOO_SMALL` | scratchpad region 容量不足 |
| `0x0B` | `BURST_CROSS_4KB` | Base Profile 下 burst 跨 4KB |

### 13.2 Fatal Error

以下情况进入 ERROR：

```text
1. 非法矩阵尺寸
2. 非法精度模式
3. 外部地址未对齐
4. AXI read/write error
5. scratchpad region overlap
6. scratchpad region out of range
7. region too small
8. command while busy
9. internal timeout
```

以下情况不进入 ERROR：

```text
1. overflow
2. saturation event
3. padding bytes 被读取
```

---

## 14. 中断规格

### 14.1 IRQ 输出

顶层提供：

```systemverilog
output logic irq
```

### 14.2 触发条件

```text
1. task done 且 irq_en = 1
2. fatal error 且 irq_en = 1
```

### 14.3 清除方式

```text
CPU 写 IRQ_STATUS.clear = 1
或者写 CTRL.clear_done / CTRL.clear_error
```

---

## 15. UVM 验证规格总纲

### 15.1 验证目标

V3 验证目标是证明：

```text
1. AXI-Lite 配置正确
2. AXI4 DMA load/store 正确
3. scratchpad region 管理正确
4. systolic array 计算正确
5. tile 调度正确
6. INT8 / INT16 模式正确
7. bias / ReLU / saturation 正确
8. error / irq / status 正确
9. reset during compute 正确
10. output 与 golden model 一致
```

### 15.2 UVM 环境组成

```text
tb/
├── axi_lite_master_agent
├── axi_full_slave_memory_agent
├── tensor_env
├── virtual_sequencer
├── virtual_sequences
├── scoreboard
├── coverage_collector
├── reference_model_adapter
└── top_tb.sv
```

### 15.3 验证组件职责

| 组件 | 作用 |
|---|---|
| AXI-Lite master agent | 配置寄存器，启动任务，读状态 |
| AXI-Full slave memory agent | 模拟外部 DDR，响应 DUT DMA |
| Memory model | 保存 A/B/bias/C 数据 |
| Scoreboard | 比对 DUT 写回结果与 golden model |
| Coverage collector | 收集功能覆盖率 |
| Virtual sequence | 组织数据初始化、寄存器配置、启动、等待、检查 |
| Reference model adapter | 调用 Python/Numpy 或 SV reference model |

### 15.4 Golden Model

推荐使用 Python/Numpy：

```text
C_ref = A × B
if bias_en:
    C_ref = C_ref + bias
if relu_en:
    C_ref = max(0, C_ref)
if sat_en:
    C_ref = saturate(C_ref)
```

需要支持：

```text
1. INT8 input
2. INT16 input
3. INT32 accumulation
4. overflow/saturation 语义
5. tile mask 语义
6. 非 4 对齐矩阵尺寸
```

### 15.5 Directed Tests

建议包含：

```text
1. basic INT8 4×4 matmul
2. basic INT16 4×4 matmul
3. 8×8 matmul
4. 16×16 matmul
5. 32×32 matmul
6. 64×64 matmul
7. rectangular matrix M≠N≠K
8. non-4-aligned matrix size
9. bias enable
10. ReLU enable
11. bias + ReLU enable
12. saturation enable
13. overflow case
14. minimum matrix size 1×1
15. maximum matrix size 64×64
```

### 15.6 Random Tests

建议包含：

```text
1. random M/N/K in 1..64
2. random precision mode
3. random matrix data
4. random bias
5. random post-op mode
6. random saturation mode
7. random AXI ready delay
8. random burst length
9. random scratchpad region offset
10. random legal padding
11. random back-to-back command
```

### 15.7 Error Tests

建议包含：

```text
1. illegal M/N/K
2. illegal precision
3. unaligned A/B/C/BIAS base address
4. command while busy
5. AXI read SLVERR
6. AXI write SLVERR
7. scratchpad region overlap
8. scratchpad region out of range
9. region too small
10. burst crossing 4KB in Base Profile
11. reset during LOAD
12. reset during COMPUTE
13. reset during STORE
```

### 15.8 Performance Profile Tests

如果实现 Performance Profile，额外增加：

```text
1. burst length = 256
2. read outstanding depth = 2
3. write outstanding depth = 2
4. A/B parallel load
5. 4KB boundary auto split
6. descriptor FIFO full/empty
7. read return routing by descriptor
8. random ready delay under outstanding=2
```

### 15.9 Functional Coverage

建议覆盖点：

```text
precision mode
M/N/K size bins
matrix alignment
tile count
post-op mode
saturation mode
overflow occurrence
AXI burst length
AXI response type
read outstanding depth
write outstanding depth
4KB boundary split
scratchpad region overlap
FSM state transition
reset timing
back-to-back command
```

---

## 16. 推荐工程目录结构

```text
mp_tensor_accel/
├── rtl/
│   ├── common/
│   │   ├── mac_unit.sv
│   │   ├── saturate.sv
│   │   ├── fifo.sv
│   │   └── tensor_pkg.sv
│   ├── compute/
│   │   ├── pe.sv
│   │   ├── systolic_array.sv
│   │   ├── accumulator.sv
│   │   └── post_process.sv
│   ├── memory/
│   │   ├── scratchpad.sv
│   │   ├── scratchpad_ctrl.sv
│   │   └── region_checker.sv
│   ├── dma/
│   │   ├── axi_read_dma.sv
│   │   ├── axi_write_dma.sv
│   │   ├── dma_burst_splitter.sv
│   │   ├── dma_descriptor_fifo.sv
│   │   ├── tensor_loader.sv
│   │   └── tensor_writer.sv
│   ├── bus/
│   │   ├── axi_lite_slave.sv
│   │   └── reg_file.sv
│   ├── control/
│   │   ├── command_fsm.sv
│   │   ├── tile_scheduler.sv
│   │   └── load_scheduler.sv
│   └── top/
│       └── tensor_accel_top.sv
├── tb/
│   ├── agents/
│   │   ├── axi_lite_agent/
│   │   └── axi_full_slave_agent/
│   ├── env/
│   ├── seq_lib/
│   ├── tests/
│   ├── scb/
│   ├── cov/
│   └── top_tb.sv
├── model/
│   ├── golden_model.py
│   └── gen_test_data.py
├── docs/
│   ├── architecture.md
│   ├── register_map.md
│   ├── interface_spec.md
│   ├── dma_spec.md
│   ├── verification_plan.md
│   └── coverage_plan.md
├── scripts/
│   ├── run_sim.sh
│   ├── run_regression.sh
│   └── merge_cov.sh
└── README.md
```

---

## 17. 实现优先级建议

### Phase 1：计算核心

```text
1. INT8 4×4 PE array
2. 4×4 matmul
3. basic accumulator
4. direct TB load
5. golden model 比对
```

### Phase 2：扩展计算规格

```text
1. INT16 mode
2. M/N/K up to 64
3. tile scheduler
4. non-4-aligned mask
5. bias / ReLU / saturation
```

### Phase 3：控制接口

```text
1. AXI-Lite Slave
2. register file
3. command FSM
4. status / error / irq
5. region checker
```

### Phase 4：Base DMA

```text
1. AXI4-Full Master read/write
2. burst length 1/4/8/16
3. outstanding depth = 1
4. serial load/store
5. 4KB boundary check
```

### Phase 5：Performance DMA

```text
1. burst length up to 256
2. read outstanding depth = 2
3. descriptor FIFO
4. LOAD_TILE_PARALLEL
5. 4KB boundary auto split
```

### Phase 6：UVM 验证闭环

```text
1. AXI-Lite master agent
2. AXI-Full slave memory agent
3. scoreboard
4. coverage collector
5. directed/random/error tests
6. regression + coverage report
```

---

## 18. 简历包装建议

可以写成：

```text
轻量级多精度张量计算加速器设计与 UVM 验证

- 设计基于 4×4 systolic array 的矩阵乘加加速器，支持 INT8/INT16 输入、INT32 累加、最大 64×64 矩阵计算，以及 bias/ReLU/saturation 后处理；
- 设计 AXI-Lite 配置接口与 AXI4-Full Master DMA 数据通路，实现外部 memory 与统一 scratchpad 之间的 burst-based tensor load/store；
- 设计统一 scratchpad 地址空间与可配置 A/B/C/Bias region，支持 region 越界、重叠和容量检查；
- 设计 tile scheduler、command FSM、tensor loader/writer 和 post-process 数据通路，支持非 4 对齐矩阵尺寸和 tile mask；
- 在性能增强规格中支持 AXI burst up to 256、read outstanding depth=2、A/B tile 并行加载和 4KB boundary 自动拆分；
- 搭建 UVM 验证环境，包含 AXI-Lite master agent、AXI-Full slave memory model、scoreboard、coverage collector 和 virtual sequence；
- 基于 Python/Numpy golden model 完成输出矩阵逐元素比对，覆盖 directed/random、溢出、非法配置、AXI error、scratchpad region error、reset during compute 和 back-to-back command 等场景。
```

---

## 19. 一句话总结

V3 推荐规格的核心是：

```text
一个带 AXI4 DMA 的轻量级多精度矩阵计算加速器，
主打 INT8/INT16 推理计算、4×4 systolic array、
最大 64×64 tile 调度、统一 scratchpad、
AXI burst 数据搬运、可选 outstanding/并行加载优化，
以及完整 UVM 验证闭环。
```

该版本相对于 tiny-tpu 更工程化，相对于集创赛满血题目更可控，适合作为数字 IC 前端设计 + 验证全栈方向的秋招展示项目。
