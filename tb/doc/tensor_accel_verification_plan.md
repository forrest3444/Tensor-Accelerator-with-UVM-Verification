# Tensor Accelerator 验证计划

## 1. 文档概述

### 1.1 文档目的

本文档为 `tensor_accel_top` 定义完整验证计划。基于当前 RTL 实现和 RTL SPEC，作为定向测试、约束随机测试、覆盖率收敛、断言、回归、bug 跟踪和签核的验证单一事实来源。

### 1.2 适用范围

| 范围 | 描述 |
| ---- | ---- |
| DUT | `tensor_accel_top` 及全部集成的 RTL 子模块 |
| 验证层级 | Block/subsystem 级 RTL 仿真 |
| 验证类型 | 功能验证、覆盖率驱动验证、错误注入、回归 |
| 测试语言 | SystemVerilog / UVM |
| 主要方法学 | 定向 + 约束随机 + scoreboard + 覆盖率 |

**范围内：**

- AXI-Lite 寄存器编程和状态行为。
- 通过集成 memory model/VIP 的 AXI4 读写 DMA 行为。
- INT4、INT8、INT16 矩阵乘法数据通路。
- Bias、ReLU、wrap、saturation、overflow tracking 和 IRQ 行为。
- A 乒乓缓冲、B 单条带复用、固定 Bias 窗口和内部 SPAD 布局。
- 读 descriptor FIFO、写 descriptor FIFO、读 4KB split 选项和写 4KB 错误上报。
- Load/compute 重叠和 post/store/writeback 行为。
- 固定 `C_STORE_NBLOCK=2` C store coalescing，保持外部 row-major C 布局。
- Reset、soft reset、命令冲突、合法随机配置和定向错误注入。
- 功能覆盖率和代码覆盖率收敛及记录过的 waivers。

**范围外（除非明确要求）：**

- 形式验证。
- STA 和门级时序仿真。
- 功耗、DFT、CDC sign-off、FPGA 原型验证和固件协同仿真。

### 1.3 参考文档

| 编号 | 文档 | 描述 |
| ---- | ---- | ---- |
| R1 | `rtl/SPEC_EN.md` | 当前 RTL 设计规范和 ABI 事实 |
| R2 | `rtl/SPEC_CN.md` | 中文 RTL 设计规范 |
| R3 | `rtl/top_level_system_diagram.md` | 架构文字框图及子系统划分 |
| R4 | `rtl/performance_optimization_plan.md` | 性能优化计划及实现说明 |
| R5 | `tb/doc/bug_log.md` | Bug 跟踪日志 |
| R6 | `script/filelist.f` | RTL/TB 编译文件列表 |
| R7 | `Makefile` | 回归、编译、运行、覆盖率和合并目标 |

## 2. DUT 概述

### 2.1 DUT 功能概述

`tensor_accel_top` 是一个单时钟整数矩阵乘法加速器。软件通过 AXI-Lite 配置矩阵维度、精度、后处理模式、基地址和 DMA burst 长度。DUT 通过 AXI4 read DMA 加载 A/B/Bias，用 4×4 脉动阵列分 tile 计算矩阵乘加，执行后处理，并通过 AXI4 write DMA 写出 row-major INT32 C 结果。

**主要功能：**

- AXI-Lite 寄存器接口用于配置、状态、IRQ、overflow 和错误码访问。
- 带内部 descriptor FIFO 的 AXI4 master 读写 DMA。
- 固定内部 SPAD 区域规划：A0/A1/B/Bias。
- 基于 M/N 的 tile 化计算，每 tile 全 K 迭代，无 K-tile 部分累加。
- 有符号 INT4/INT8/INT16 输入，40-bit 内部累加，INT32 输出。
- C store coalescing，固定 `C_STORE_NBLOCK=2`。

**关键特征：**

| 项目 | 值 |
| ---- | ---- |
| 时钟域 | 单 `clk` |
| 复位 | 低有效异步 `rst_n`；软件 `soft_reset` 脉冲 |
| AXI-Lite | 32-bit data, 16-bit address |
| AXI4 Master | 64-bit data, 32-bit address, fixed ID 0, INCR bursts |
| 默认阵列 | 4×4 |
| 最大维度 | `MAX_DIM=64` |
| 输出格式 | INT32 row-major C |
| B 布局 | 软件预转置/预打包的输出列条带 |
| C 写回 | Row-mode 多行写；相邻 N tile 两两合并 (N-block) |

### 2.2 DUT 结构框图

```text
+--------------------------------------------------------------------------+
|                             tensor_accel_top                              |
|                                                                          |
| AXI-Lite -> axi_lite_slave -> reg_file -> cfg_active/status/error/irq     |
|                                                                          |
| command_fsm -> tile_count_fsm -> buffer_manager_fsm                       |
|      |             |                 |                                    |
|      |             |                 +-> 固定 SPAD 基址 A0/A1/B/Bias     |
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

**模块说明：**

| 模块 | 功能 |
| ---- | ---- |
| `axi_lite_slave` | AXI-Lite 握手及寄存器访问转换 |
| `reg_file` | 寄存器映射、脉冲生成、IRQ 使能、状态回读、配置存储 |
| `region_checker` | 矩阵尺寸、精度和基地址对齐检查 |
| `command_fsm` | 顶层命令排序、状态、IRQ、超时和错误锁存 |
| `tile_count_fsm` | `tile_m/tile_n`、行列有效掩码、C 外部偏移 |
| `buffer_manager_fsm` | A 乒乓选择、B/Bias 固定基址、预取冲突检查 |
| `load_scheduler` | A/B/Bias descriptor 生成和挂起读 drain 跟踪 |
| `dma_descriptor_fifo` | 顺序读写 descriptor 缓冲 |
| `tensor_loader` | 行模式读调度、对齐调整、SPAD 写 |
| `tensor_writer` | 行模式写调度、row-ready 门控、SPAD/coalescer 读 |
| `axi_read_dma` | AXI AR/R burst 引擎，可选读 4KB split |
| `axi_write_dma` | AXI AW/W/B burst 引擎，含写错误和 4KB crossing 上报 |
| `wavefront_feeder` | 脉动阵列的偏斜 A/B 注入 |
| `systolic_array` | PE 阵列，带符号乘累加和传播 |
| `accumulator` | 捕获脉动阵列结果供后处理 |
| `post_process` | Bias、ReLU、wrap/saturate、overflow 生成 |
| `c_store_coalescer` | 以 M tile 和 N-block slot 索引的 C 行缓存 |

### 2.3 DUT 接口列表

| 接口 | 方向 | 位宽 | 描述 |
| ---- | ---- | ---: | ---- |
| `clk` | input | 1 | 单时钟 |
| `rst_n` | input | 1 | 低有效异步复位 |
| `s_axil_*` | mixed | 32-bit data / 16-bit addr | AXI-Lite 寄存器接口 |
| `m_axi_ar*`、`m_axi_r*` | mixed | 64-bit data / 32-bit addr | AXI4 读 master |
| `m_axi_aw*`、`m_axi_w*`、`m_axi_b*` | mixed | 64-bit data / 32-bit addr | AXI4 写 master |
| `irq` | output | 1 | 电平风格 completion/error 中断 |

`ifndef SYNTHESIS` 下的仿真专用端口用于 command FSM error-arc 注入，不属于可综合接口约定。

## 3. 验证目标

### 3.1 功能正确性

| 编号 | 目标 | 描述 |
| ---- | ---- | ---- |
| FC-01 | CSR 行为 | 验证复位值、RW/RO/W1C/pulse 语义、字节使能、无暴露的 SPAD offset/size 寄存器 |
| FC-02 | 矩阵数据通路 | 验证 INT4/INT8/INT16 下方阵、矩形、非对齐和退化合法维度的矩阵乘加 |
| FC-03 | 后处理 | 验证 bias、ReLU、bias+ReLU、wrap、saturation、overflow_seen 和 OVF_COUNT |
| FC-04 | 外部数据布局 | 验证 A row-major packed 布局，B 预转置条带布局，Bias 向量布局，row-major C 输出 |
| FC-05 | C store coalescing | 验证 `C_STORE_NBLOCK=2` 缓存、N-block 尾部处理、row_bytes 计算和 row-major 正确性 |
| FC-06 | 缓冲管理 | 验证 A 乒乓、B/Bias 在 `tile_m==0` 时复用、无 load/compute/store 冲突 |
| FC-07 | DMA descriptor | 验证 descriptor FIFO 顺序、行模式 descriptor、split/read 行为和写 descriptor 生成 |
| FC-08 | 错误行为 | 验证所有定义的错误码、锁存、清除行为及支持的恢复 |
| FC-09 | IRQ/状态 | 验证 done/error IRQ 的置位、保持、清除及 IRQ 使能行为 |
| FC-10 | 复位 | 验证冷复位、软复位及活跃 load/compute/store 中的复位 |

### 3.2 协议正确性

| 编号 | 目标 | 描述 |
| ---- | ---- | ---- |
| PC-01 | AXI-Lite | 验证 AW/W/B 和 AR/R 握手、读延迟、字节使能合并和响应稳定性 |
| PC-02 | AXI read | 验证 AR/R 顺序、RLAST 处理、RRESP 错误检测和背压下无数据丢失 |
| PC-03 | AXI write | 验证 AW/W/B 顺序、WSTRB 正确性、WLAST、BRESP 错误检测和行模式排序 |
| PC-04 | 内部 valid/ready | 验证 descriptor FIFO push/pop、loader/writer busy/done/error 和 store row-ready/read 安全 |
| PC-05 | 顺序执行 | 验证命令、descriptor、tile 和 C 写回严格保持 in-order |

### 3.3 边界条件

| 编号 | 目标 | 描述 |
| ---- | ---- | ---- |
| BC-01 | 最小合法维度 | `M/N/K=1` 及窄矩形形状 |
| BC-02 | 最大合法维度 | `M/N/K=64`，含随机合法最大压力种子 |
| BC-03 | Tile 尾部 | 非整倍 `M/N` 尺寸及 N-block 尾部 coalescing |
| BC-04 | 精度打包 | INT4 奇/偶 K nibble 打包、INT8 字节打包、INT16 lane strobe |
| BC-05 | Burst 边界 | Burst 长度最小/最大/零/超限及读写 4KB 边界行为 |
| BC-06 | FIFO 边界 | 读写 descriptor FIFO 空/满保护和顺序 |
| BC-07 | 状态边界 | busy/done/error 时 start、clear_done、clear_error、clear_irq、soft_reset |

### 3.4 鲁棒性

| 编号 | 目标 | 描述 |
| ---- | ---- | ---- |
| RB-01 | 连续命令 | 验证重复命令不泄漏状态 |
| RB-02 | 精度切换 | 验证 INT4/INT8/INT16 连续切换 |
| RB-03 | 随机合法配置 | 验证跨种子随机化合法矩阵形状和模式 |
| RB-04 | AXI 错误注入 | 在定向阶段注入读写错误 |
| RB-05 | Command FSM error arc | 使用仿真专用 force 端口触发难以覆盖的错误弧 |
| RB-06 | 操作中复位 | 在 load、compute、store 和 idle 中复位 |
| RB-07 | 长期稳定性 | 全回归：定向 + 异常 + 随机 + 覆盖率 |

## 4. 验证范围

### 4.1 范围内

| 编号 | 范围项 | 描述 |
| ---- | ------ | ---- |
| IS-01 | 定向基础测试 | 基础 INT4/INT8/INT16、8×8 通路、矩形、非对齐、退化、bias、ReLU、saturation |
| IS-02 | 异常测试 | 非法尺寸/精度/基址、AXI 读写错误、命令冲突、超时、IRQ on error |
| IS-03 | 随机测试 | 合法随机、corner-data 随机、max-stress 随机 |
| IS-04 | 覆盖率收敛 | 功能、分支、行、条件、翻转、FSM、断言覆盖率及 waiver |
| IS-05 | 寄存器验证 | CSR 读写/复位/RO/W1C/pulse 行为 |
| IS-06 | 数据完整性 | 端到端 scoreboard 与软件参考模型比对 |
| IS-07 | 性能观测 | TB 侧性能 monitor 观测延迟/阻塞/吞吐 |
| IS-08 | 断言 | `ASSERT_ON` 下可综合 RTL 断言 + TB/协议检查 |

### 4.2 范围外

| 编号 | 范围项 | 理由 |
| ---- | ------ | ---- |
| OS-01 | 形式验证 | 仅在明确要求时运行 |
| OS-02 | STA / 门级时序 | 物理时序收敛不在本 RTL 仿真计划内 |
| OS-03 | 软件驱动协同仿真 | 软件行为以寄存器和存储事务建模 |
| OS-04 | Tile-major C ABI | 当前 SPEC 要求 row-major C |
| OS-05 | 完整 B 片上转置引擎 | 当前 B ABI 为软件预转置/预打包 |
| OS-06 | 任意阵列尺寸参数签核 | 默认验证针对当前 4×4 配置；8×8 为后续阶段 |

## 5. 验证策略

### 5.1 验证层级

| 层级 | 范围 | 方法 | 目标 |
| ---- | ---- | ---- | ---- |
| L1 模块 | 集成 TB 环境中的叶级和控制器模块 | 定向测试 + 断言 | 通过顶层测试暴露的协议和基本行为 |
| L2 子系统 | Load/compute/store/DMA/寄存器子系统 | 定向 + 错误注入 | 验证子系统排序和恢复 |
| L3 端到端 | 完整 `tensor_accel_top` | Scoreboard + 定向/随机 | 验证矩阵结果和可观察状态 |
| L4 收敛 | 全回归 | 多种子随机 + 覆盖率合并 + waiver 评审 | 关闭覆盖率并稳定回归 |

### 5.2 验证方法

| 方法 | 应用层级 | 说明 |
| ---- | -------- | ---- |
| 定向测试 | L2/L3 | 目标和回归测试的主要工具 |
| 约束随机测试 | L3/L4 | 合法矩阵/模式随机化 + scoreboard 检查 |
| 错误注入 | L2/L3 | AXI response 错误、非法配置、命令冲突、超时、内部 force 钩子 |
| Scoreboard | L3/L4 | 矩阵参考模型比较外部 C memory 内容 |
| 功能覆盖率 | L3/L4 | Covergroup 在 `tb/env/tensor_accel_coverage.sv` |
| 代码覆盖率 | L4 | VCS line/cond/fsm/branch/tgl/assert + `cov_waivers` |
| 断言 | 全部 | RTL `ASSERT_ON` 和 TB 协议检查 |
| 性能 monitor | L3/L4 | 仅 TB monitor；性能计数器不在 RTL 主路径中保留 |

### 5.3 验证环境文件组织

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

### 5.4 检查机制

| 机制 | 检查内容 | 失败响应 |
| ---- | -------- | -------- |
| Scoreboard | 外部 C memory 结果与参考模型比对 | `uvm_error` / 测试失败 |
| 寄存器模型/sequence | CSR 访问、清除行为、状态/错误 | `uvm_error` |
| AXI VIP / monitor | AXI 协议、response 和 memory 行为 | VIP error 或 TB error |
| RTL 断言 | FIFO 边界、store context、SPAD 窗口、coalescer 边界 | `ASSERT_ON` 时 `$fatal` |
| 覆盖率模型 | 特性和跃迁覆盖率 | 覆盖率空洞分类 |
| 性能 monitor | 延迟/阻塞/吞吐观测 | 报告和趋势，非 sign-off 阻碍（除非定义阈值） |

## 6. 验证环境说明

### 6.1 验证环境架构

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

**VIP 信息：**

| VIP | 版本 | 供应商 | 接口 | 说明 |
| --- | ---- | ------ | ---- | ---- |
| SVT AXI System VIP | 2018.09 | Synopsys | AXI-Lite 和 AXI4 memory system | 用于寄存器和 memory 事务 |

### 6.2 Agent 划分

| Agent/Component | 类型 | 功能 |
| --------------- | ---- | ---- |
| AXI system sequencer | Active VIP | 驱动寄存器、memory 和 slave response sequence |
| `tensor_accel_env` | UVM env | 拥有参考模型、scoreboard、覆盖率和 perf monitor |
| `tensor_accel_ref_model` | 预测器 | 计算已配置操作的期望 C 矩阵 |
| `tensor_accel_scoreboard` | 比较器 | 比较期望和观测的 memory/结果行为 |
| `tensor_accel_coverage` | Subscriber | 采样功能覆盖率 |
| `tensor_perf_monitor` | Monitor | RTL 外部跟踪性能事件 |

### 6.3 参考模型

| 属性 | 描述 |
| ---- | ---- |
| 实现语言 | SystemVerilog |
| 精度 | Transaction-level 功能模型 |
| 支持特性 | INT4/INT8/INT16、row-major A、预转置 B 条带、Bias/ReLU/saturation/wrap、row-major C |
| 输入来源 | 编程的测试配置和 memory 初始化 |
| 输出目标 | Scoreboard 期望矩阵 |
| 配置感知 | 使用与 DUT 测试相同的寄存器配置 |

### 6.4 Scoreboard

| 属性 | 描述 |
| ---- | ---- |
| 比较粒度 | 逐矩阵元素 / 逐测试事务 |
| 输入来源 | 参考模型期望矩阵；DUT 完成后的实际 C memory 内容 |
| 排序 | In-order 命令完成 |
| 不匹配行为 | `uvm_error` 附不匹配详情 |
| 超时处理 | 测试超时/watchdog 使测试失败 |
| 丢拍/重复检测 | 由完整矩阵内容比较和完成状态覆盖 |

## 7. Feature List / 验证项

### 7.1 优先级定义

| 优先级 | 含义 |
| ------ | ---- |
| P0 | 任何可用发布必须通过 |
| P1 | 验证收敛必须通过 |
| P2 | 重要压力/覆盖项，可通过 review waiver |
| P3 | 可选探索项 |

### 7.2 验证项表

| Feature ID | 功能描述 | 目标 | 优先级 | 方法 | 覆盖率点 | 测试 |
| ---------- | -------- | ---- | ------ | ---- | -------- | ---- |
| F-REG | CSR 映射和语义 | Reset/RW/RO/W1C/pulse/IRQ 使能 | P0 | 定向 + RAL | CSR bins | reg, irq, ro protection |
| F-INT8 | INT8 数据通路 | 正确矩阵乘加和 C 写回 | P0 | 定向 + 随机 | precision bins | 4×4, 8×8, random |
| F-INT16 | INT16 数据通路 | 正确符号扩展和累加 | P0 | 定向 | precision bins | int16, max stress |
| F-INT4 | INT4 数据通路 | 正确 nibble 解包、符号扩展、结果 | P0 | 定向 + 随机 | precision bins | int4, precision switch |
| F-POST | 后处理 | Bias/ReLU/saturation/wrap/overflow | P0 | 定向 | post_op/sat bins | bias, relu, saturation |
| F-SHAPE | 矩阵形状 | 矩形、尾部、退化合法维度 | P0 | 定向 + 随机 | shape bins | rect, non-aligned, degenerate |
| F-BLAYOUT | B 预转置 ABI | 跨 M 的 B 条带读取和复用 | P0 | Scoreboard | B reuse bins | base/random |
| F-CSTORE | C row-major 写回 | N-block coalescer 和行模式写 | P0 | 定向 + 覆盖 | store/coalescer bins | 8×8, rect, random |
| F-DMA-R | 读 DMA | Descriptor FIFO、行模式、错误、可选 4KB split | P1 | 定向/错误 | read DMA bins | read slverr, burst |
| F-DMA-W | 写 DMA | 行模式、WSTRB、BRESP 错误、4KB crossing 错误 | P1 | 定向/错误 | write DMA bins | write slverr, unaligned |
| F-FSM | Command FSM | 正常、流水、done、error 弧 | P1 | 定向 + 错误注入 | FSM coverage | command error arc |
| F-BUF | 缓冲管理 | A 乒乓、B/Bias 复用、冲突 | P1 | 定向/随机 | buffer bins | base/random/back-to-back |
| F-RESET | 复位行为 | 冷复位、软复位、活跃复位 | P1 | 定向 | reset-state cross | reset tests |
| F-IRQ | IRQ/状态 | Done/error IRQ、清除、状态位 | P1 | 定向 | IRQ bins | base_irq, irq_on_error |
| F-RAND | 随机合法压力 | 合法随机化配置 | P2 | 随机 | config crosses | random legal/corner/max |
| F-COV | 覆盖率收敛 | 覆盖率合并和 waiver 评审 | P1 | 回归 | code/functional coverage | full regression |

## 8. 测试用例列表

### 8.1 测试类型说明

| 类型 | 描述 |
| ---- | ---- |
| 定向 | 手写单目标测试 |
| 约束随机 | 随机合法/corner/stress 配置 |
| 错误注入 | 非法配置、AXI 错误、命令冲突、force 钩子 |
| 压力 | 多种子或最大尺寸稳定性/性能测试 |

### 8.2 测试用例表

| 用例 ID | 测试名称 | 类型 | 目标 Feature | 通过/失败标准 |
| ------- | -------- | ---- | ------------ | ------------- |
| TC-BASE-8X8 | `tensor_base_8x8_test` | 定向 | F-INT8, F-CSTORE, F-BUF | 测试完成，`UVM_ERROR=0`，C 与参考一致 |
| TC-INT4 | `tensor_base_int4_4x4_test` | 定向 | F-INT4 | INT4 打包数据 C 与参考一致 |
| TC-INT8 | `tensor_base_int8_4x4_test` | 定向 | F-INT8 | C 与参考一致 |
| TC-INT16 | `tensor_base_int16_4x4_test` | 定向 | F-INT16 | C 与参考一致 |
| TC-BURST | `tensor_base_burst_len_test` | 定向 | F-DMA-R, F-DMA-W | Burst 配置变体通过，无 mismatch |
| TC-B2B | `tensor_base_back_to_back_test` | 定向 | F-BUF, F-FSM | 多次命令通过，无残留状态 |
| TC-PREC-SW | `tensor_base_bb_precision_switch_test` | 定向 | F-INT4, F-INT8, F-INT16 | 连续精度切换通过 |
| TC-IRQ | `tensor_base_irq_test` | 定向 | F-IRQ, F-REG | IRQ 按 SPEC 置位/清除 |
| TC-RECT | `tensor_base_rect_matrix_test` | 定向 | F-SHAPE, F-CSTORE | 矩形输出与参考一致 |
| TC-NONALIGNED | `tensor_base_non_aligned_size_test` | 定向 | F-SHAPE, F-CSTORE | M/N 尾部处理通过 |
| TC-DEGEN | `tensor_base_degenerate_dims_test` | 定向 | F-SHAPE | 合法窄形状通过 |
| TC-BIAS | `tensor_base_bias_test` | 定向 | F-POST | Bias 正确施加 |
| TC-RELU | `tensor_base_relu_test` | 定向 | F-POST | ReLU 正确施加 |
| TC-BIAS-RELU | `tensor_base_bias_relu_order_test` | 定向 | F-POST | Bias 先于 ReLU 施加 |
| TC-SAT | `tensor_base_saturation_test` | 定向 | F-POST | Saturation/wrap 行为与模型一致 |
| TC-OVERFLOW | `tensor_base_overflow_status_test` | 定向 | F-POST, F-IRQ | Overflow 状态/计数与期望一致 |
| TC-AXI-READY | `tensor_base_axi_ready_delay_test` | 定向 | F-DMA-R, F-DMA-W | 背压不破坏数据 |
| TC-RO | `tensor_base_ro_reg_protection_test` | 定向 | F-REG | RO 字段写入不改变 |
| TC-WR-UNALIGN | `tensor_base_write_unaligned_test` | 定向 | F-DMA-W | 支持的 C 对齐行为与 SPEC 一致 |
| TC-ERR-SIZE | `tensor_err_illegal_matrix_size_test` | 错误注入 | F-REG, F-FSM | `ERR_ILLEGAL_MATRIX_SIZE` 上报 |
| TC-ERR-PREC | `tensor_err_illegal_precision_test` | 错误注入 | F-REG, F-FSM | `ERR_ILLEGAL_PRECISION` 上报 |
| TC-ERR-BASE | `tensor_err_unaligned_base_test` | 错误注入 | F-REG, F-FSM | `ERR_UNALIGNED_BASE_ADDR` 上报 |
| TC-ERR-RD | `tensor_err_axi_read_slverr_test` | 错误注入 | F-DMA-R | `ERR_AXI_READ_ERROR` 上报且可恢复 |
| TC-ERR-WR | `tensor_err_axi_write_slverr_test` | 错误注入 | F-DMA-W | `ERR_AXI_WRITE_ERROR` 上报且可恢复 |
| TC-ERR-CMD | `tensor_err_command_while_busy_test` | 错误注入 | F-FSM | `ERR_COMMAND_WHILE_BUSY` 上报 |
| TC-ERR-DONE | `tensor_err_start_while_done_test` | 错误注入 | F-FSM | done/error 时 start 处理正确 |
| TC-ERR-BURST | `tensor_err_burst_len_zero_test`、`tensor_err_burst_len_exceed_test` | 错误注入 | F-DMA-R/W | 非法 burst 行为与 SPEC/测试意图一致 |
| TC-ERR-TIMEOUT | `tensor_err_internal_timeout_test` | 错误注入 | F-FSM | 超时错误上报 |
| TC-ERR-ARC | `tensor_err_command_fsm_error_arc_test` | 错误注入 | F-FSM | 其余可达 error arc 命中 |
| TC-RST-LOAD | `tensor_reset_during_load_test` | 定向 | F-RESET | 加载中复位可恢复 |
| TC-RST-COMP | `tensor_reset_during_compute_test` | 定向 | F-RESET | 计算中复位可恢复 |
| TC-RST-STORE | `tensor_reset_during_store_test` | 定向 | F-RESET | 存储中复位可恢复 |
| TC-SOFT-RST | `tensor_soft_reset_test`、`tensor_soft_reset_during_idle_test` | 定向 | F-RESET | 软复位行为与 SPEC 一致 |
| TC-RAND-LEGAL | `tensor_base_random_legal_test` | 约束随机 | F-RAND | 所有种子 scoreboard 和断言通过 |
| TC-RAND-CORNER | `tensor_base_random_corner_data_test` | 约束随机 | F-RAND, F-POST | Corner data pattern 通过 |
| TC-RAND-STRESS | `tensor_base_random_max_stress_test` | 压力 | F-RAND, F-BUF, F-CSTORE | 最大合法随机压力通过 |

## 9. 覆盖率计划

### 9.1 功能覆盖率

| Covergroup / Area | 描述 | 采样位置 | 目标 |
| ----------------- | ---- | -------- | ---: |
| CSR coverage | 寄存器访问、复位、清除、错误/状态字段 | 寄存器事务 | 100% P0/P1 |
| Precision coverage | INT4/INT8/INT16 | 测试配置 / 完成 | 100% |
| Shape coverage | 方阵、矩形、尾部、退化、最大 | 测试配置 | 100% P0/P1 |
| Post-op coverage | none/bias/ReLU/bias+ReLU × wrap/saturate | 测试配置 / 结果 | 100% |
| DMA coverage | 读写 descriptor、行模式、burst len、错误 | DMA monitor/状态 | 100% P0/P1 |
| C store coverage | `C_STORE_NBLOCK=2`、slot 0 缓存、slot 1 写、N-tail partial block | Store/coalescer 事件 | 100% |
| Buffer coverage | A bank 选择、N 切换、B/Bias 复用 | 内部/TB monitor | 100% |
| FSM coverage | Command FSM 状态和可达跃迁 | VCS FSM coverage | 100% 可达 |
| Error coverage | 每种错误码和恢复路径 | Status/error monitor | 100% P0/P1 |
| Reset coverage | idle/load/compute/store/done/error 中复位 | 复位测试 | 100% P1 |

### 9.2 交叉覆盖率

| 交叉 | 变量 | 目标 |
| ---- | ---- | ---: |
| Precision x Post-op | `precision` × `post_op` × `sat_mode` | 100% 有意义的合法组合 |
| Shape x Precision | matrix shape class × precision | 100% P0/P1 |
| C store x Shape | N-block slot/tail × tile_cols class | 100% |
| Error x FSM state | error source × command state | 100% 可达，不可达为 waiver |
| Reset x FSM state | reset type × active stage | 100% 定向状态 |
| Burst x DMA path | burst_len bucket × read/write × row_mode | 100% P1 |

### 9.3 代码覆盖率

| 类型 | 目标 | 说明 |
| ---- | ---: | ---- |
| 行 | ≥ 95% | 允许审核过的 waiver |
| 条件 | ≥ 90% | 不可达组合记录在案 |
| FSM 状态 | 100% 可达状态 | Reset-only/不可达弧已审核 |
| FSM 跃迁 | 100% 可达功能弧 | Error arc 已覆盖或 waiver |
| 分支 | ≥ 90% | Default 已审核 |
| 翻转 | ≥ 90% | 固定/仅测试/VIP/接口 waiver 允许 |
| 断言 | 100% 通过 | 无未审核断言失败 |

覆盖率排除存储在 `cov_waivers/`。已知的过滤范围包括 `axi_if`、`dut_if` 和 `uvm_custom_install_verdi_recording`。

## 10. 断言计划

### 10.1 严重级别定义

| 级别 | 含义 |
| ---- | ---- |
| S0 Fatal | 数据损坏、非法 FIFO 访问、协议破坏、不可恢复状态 |
| S1 Error | 功能正确性或错误处理违反 |
| S2 Warning | 可疑条件需要审核 |
| S3 Info | 调试/覆盖专用的观测 |

### 10.2 断言列表

| ID | 检查内容 | 级别 | 范围 |
| -- | -------- | ---- | ---- |
| AS-FIFO-01 | Descriptor FIFO push while full 非法 | S0 | 读写 descriptor FIFO |
| AS-FIFO-02 | Descriptor FIFO pop while empty 非法 | S0 | 读写 descriptor FIFO |
| AS-SPAD-01 | 固定 SPAD 窗口不重叠且适合实现的容量 | S0 | Buffer manager / region checker |
| AS-SPAD-02 | 最大 A/B/Bias tile 适合各固定窗口 | S0 | Region checker |
| AS-ST-01 | Store descriptor push 需要活跃 store context | S0 | Top/store FSM |
| AS-ST-02 | Store descriptor row count 非零 | S0 | Top/store FSM |
| AS-ST-03 | Store FSM 不能接受重叠 store start | S0 | Store FSM |
| AS-CSTORE-01 | Coalescer write M tile、row 和 N-block slot 在范围内 | S0 | C store coalescer |
| AS-CSTORE-02 | Coalescer read M tile 和 row 在范围内 | S0 | C store coalescer |
| AS-DMA-01 | Burst splitter 仅为合法输入产生有效非零 burst | S1 | DMA burst splitter |
| AS-DMA-02 | 读 auto split 启用时不发出跨 4KB 的 AR | S1 | AXI read DMA |
| AS-FSM-01 | Command FSM 状态保持合法 | S0 | Command FSM / coverage review |
| AS-AXI-01 | AXI 错误 response 锁存到期望错误码 | S1 | 读写 DMA + command FSM |

## 11. 回归测试计划

### 11.1 Smoke 回归

| 属性 | 描述 |
| ---- | ---- |
| 目的 | RTL/TB 修改后的快速信心检查 |
| 触发 | 本地改动或回归前检查 |
| 范围 | 核心 P0 定向测试 |
| 最大运行时间 | 每最小路径测试 180s（除非另有配置） |
| 通过标准 | 100% 通过，无 UVM error/fatal，无断言失败 |

Smoke 测试：`tensor_base_8x8_test`、INT4/INT8/INT16 4×4 测试、IRQ、矩形、非对齐、退化、saturation。

### 11.2 Base 回归

| 属性 | 描述 |
| ---- | ---- |
| 目的 | 每日功能稳定性 |
| 范围 | P0/P1 定向 + 异常测试 |
| 通过标准 | 所有 P0 通过，无未分类 P1 失败，无未审核断言失败 |
| 失败响应 | 诊断、分类为 RTL/TB/SPEC/基础设施，更新 `bug_log.md` |

### 11.3 Full 回归

| 属性 | 描述 |
| ---- | ---- |
| 目的 | 覆盖率收敛和发布质量检查 |
| 范围 | 所有定向、异常、随机、压力测试，启用覆盖率 |
| 通过标准 | 100% 测试通过或有记录 waiver；覆盖率目标达成或 waiver |
| 失败响应 | 修复或审核前阻塞覆盖率 sign-off |

### 11.4 性能 / 压力回归

| 指标 | 测量方法 | 阈值 |
| ---- | -------- | ---- |
| Load/compute overlap | TB 性能 monitor | 仅趋势（除非发布目标） |
| Store 进度 | Writer/store monitor | 无死锁；row-ready 遵守 |
| 连续稳定性 | 定向 B2B 和随机测试 | 无残留状态或 mismatch |
| 随机最大压力 | 多种子随机最大测试 | 无挂死/mismatch/断言失败 |

## 12. Pass/Fail 标准

### 12.1 单个测试 Pass/Fail 标准

| 结果 | 定义 |
| ---- | ---- |
| PASS | 测试完成，scoreboard 零 mismatch，`UVM_ERROR=0`，`UVM_FATAL=0`，断言干净 |
| FAIL | 任何 mismatch、UVM error/fatal、断言失败、超时、仿真器崩溃或意外 status/error |
| SKIP | 测试不适用于当前配置，报告记录的跳过原因 |

### 12.2 回归 Pass/Fail 标准

| 回归 | 标准 |
| ---- | ---- |
| Smoke | 100% 通过 |
| Base | 所有 P0/P1 预期测试通过或有记录的活跃 bug |
| Full | 所有测试通过，覆盖率合并，waiver 已审核 |
| 覆盖率收敛 | P0/P1 功能覆盖率关闭；代码覆盖率空洞已审核和 waiver/fix |

## 13. 签核

### 13.1 签核检查表

| ID | 检查项 | 负责人 | 标准 | 状态 |
| -- | ------ | ------ | ---- | ---- |
| SF-01 | RTL 编译干净 | RTL/DV | `make elab` 以选定选项通过 | Open |
| SF-02 | Smoke 回归干净 | DV | P0 smoke 全通过 | Open |
| SF-03 | Full 回归干净 | DV | 定向/异常/随机/压力全通过 | Open |
| SF-04 | 功能覆盖率关闭 | DV | P0/P1 100%，P2 空洞已审核 | Open |
| SF-05 | 代码覆盖率已审核 | DV + RTL | 目标达成或 waiver 已记录 | Open |
| SF-06 | 断言失败已解决 | RTL/DV | 零未审核失败 | Open |
| SF-07 | Bug 日志已审核 | RTL/DV | 无开放 P0/P1；P2 处置已记录 | Open |
| SF-08 | SPEC 对齐检查 | RTL/DV | 计划和测试匹配当前 SPEC | Open |
| SF-09 | Waiver 文件已审核 | RTL/DV | Waiver 有范围、有依据、可复现 | Open |

### 13.2 覆盖率收敛跟踪

覆盖率收敛在 `cov_waivers/` 和相关覆盖率报告中跟踪。每次收敛迭代必须记录：

- 回归命令/构建选项。
- 通过/失败测试列表。
- 覆盖率增量。
- 新排除项及依据。
- 剩余未覆盖分支/FSM 跃迁及负责人。

## 14. Bug 管理

### 14.1 Bug 严重级别

| 级别 | 含义 | 示例 |
| ---- | ---- | ---- |
| P0 | 阻断基本操作或损坏数据 | C 输出错误、死锁、复位损坏 |
| P1 | 阻断特性收敛 | 缺失错误码、IRQ 问题、覆盖率关键可达弧 |
| P2 | 重要但可用 waiver 不阻塞发布 | 罕见压力空洞、低风险覆盖率空洞 |
| P3 | 清理/文档 | 消息清晰度、非阻塞文档问题 |

### 14.2 Bug 生命周期

1. 以精确测试、种子、构建和选项复现。
2. 分类为 RTL、TB、SPEC、coverage waiver 或基础设施。
3. 记录到 `tb/doc/bug_log.md`。
4. 修复并重跑失败测试。
5. 重跑受影响的 smoke/base 测试。
6. 仅在证据记录后关闭。

### 14.3 Bug 记录字段

| 字段 | 描述 |
| ---- | ---- |
| ID | 稳定 bug ID |
| 日期 | 发现日期 |
| 测试/种子 | 复现方式 |
| 模块 | 怀疑的 RTL/TB 模块 |
| 症状 | 可观察失败 |
| 根因 | 确认原因 |
| 修复 | RTL/TB/SPEC 变更 |
| 验证 | 重跑测试 |
| 状态 | Open / Fixed / Waived / Duplicate |

## 15. 风险与限制

### 15.1 风险

| 风险 | 影响 | 缓解措施 |
| ---- | ---- | -------- |
| INT4 数据通路打包/符号扩展 | 数据损坏 | 定向 INT4 和随机 corner-data 测试 |
| C store coalescer 尾部处理 | Row-major C mismatch | 定向 N-tail 和矩形测试 |
| FSM error arc | 覆盖率空洞或不可达定义 | 定向错误注入和 waiver 审核 |
| 写 4KB crossing | 真实系统集成约束 | 定向错误测试和 SPEC 文档 |
| B 预转置 ABI | 软件/DV mismatch | SPEC 和参考模型对齐 |
| 随机种子逃逸 | 潜伏 corner bug | 多种子 legal/corner/max 随机回归 |

### 15.2 限制

- 当前计划聚焦 RTL 仿真。
- 形式验证和 STA 明确排除（除非要求）。
- 性能指标在 TB 中观测，但非 sign-off 阈值（除非后续定义）。
- 默认收敛目标为当前 4×4 RTL 配置；8×8 升级需要新的针对性收敛。
- 软件驱动行为由 UVM sequence 建模，非真实 CPU/driver 栈。

## 16. 交付物

| 交付物 | 路径 / 负责人 |
| ------ | ------------ |
| RTL SPEC | `rtl/SPEC_EN.md`、`rtl/SPEC_CN.md` |
| 验证计划 | `tb/doc/VERIFICATION_PLAN_V1.md` |
| Bug 日志 | `tb/doc/bug_log.md` |
| 覆盖率 waiver | `cov_waivers/` |
| 回归命令/结果 | `sim/run/*/log/run.log`、覆盖率报告 |
| Testbench 源码 | `tb/` |
| 文件列表和 Make 目标 | `script/filelist.f`、`Makefile` |

本计划针对当前 RTL 事实编制完整，应在 RTL SPEC 变更时同步更新。
