# Tensor Accel UVM 验证计划

## 1. 验证范围

### 1.1 验证对象

本验证计划面向 `tensor_accel_top` 及其子模块的 UVM block-level 验证环境。DUT 主要包含以下功能域：

- AXI-Lite 寄存器配置接口：配置矩阵维度、precision、post-op、saturation、DMA base address、burst_len、start/clear/irq 控制。
- AXI4 DMA 数据搬运接口：从外部 memory 读取 A/B/bias，向外部 memory 写回 C。
- scratchpad 数据暂存与硬件内部固定地址规划；C 结果不再持久化到 scratchpad，而是通过 post-process row buffer 流式写回。
- 4x4 systolic array 计算、accumulator、post_process、saturate。
- command_fsm、load_scheduler、tile_count_fsm、buffer_manager_fsm、store_fsm、tensor_loader、tensor_writer 等控制与调度逻辑。
- 状态、错误码、IRQ、overflow 标志和 reset/soft reset 行为。

### 1.2 覆盖范围

当前 UVM 环境覆盖以下内容：

- AXI-Lite register reset、读写、reserved bit、RO register 保护。
- 合法矩阵乘法：INT8/INT16、方阵、矩形矩阵、非 4 对齐尺寸、退化维度、最大 64x64 维度。
- post-op：无后处理、bias、ReLU、bias + ReLU 顺序。
- saturation：wrap 和 saturate 两种模式，overflow status 检查。
- DMA 配置：burst_len 典型值、ready delay/backpressure、非对齐写回地址、4KB boundary 保护。
- 错误处理：非法矩阵维度、非法 precision、base address 未对齐、AXI read/write SLVERR、中途 write error、internal timeout、busy/done 状态下重复 start。
- interrupt：正常完成 IRQ、错误完成 IRQ、IRQ clear。
- reset：soft reset、idle soft reset、load/compute/store 阶段异步 reset。
- constrained random：合法配置随机、corner data 随机、max stress 随机，并通过多 seed regression 扩展覆盖。
- 代码覆盖：regression 脚本开启 `line+cond+fsm+branch+tgl+assert` 并执行 merge。

### 1.3 不覆盖范围

以下内容当前不在本 UVM block-level 计划范围内：

- SoC-level integration、cache coherency、系统地址映射以外的全芯片互连行为。
- 真实 DDR/NoC latency 模型和 QoS/arbiter 系统级性能验证。
- clock-domain crossing、低功耗 UPF、电源状态切换。
- gate-level simulation、SDF timing、STA signoff。
- 形式验证和 CDC/RDC 专项 signoff。
- 大规模性能 benchmark 的吞吐率签核；当前 performance profile 只作为功能压力配置。
- 未在 DUT 中实现的多 master、多 outstanding 深度协议组合；当前环境配置为 1 个 AXI-Lite master、1 个 AXI memory slave，base profile outstanding=1，performance profile outstanding=2。

## 2. Feature List and Verification Mapping

| Feature ID | 功能点 | 验证目标 | 优先级 | 验证方法 | 对应用例 ID |
|---|---|---|---|---|---|
| F001 | AXI-Lite register reset/read/write | 确认 reset default、RW register 回读、reserved bit mask、STATUS/ERROR_CODE 初值正确 | P0 | Directed register sequence + RAL check | TC001 |
| F002 | RO register 保护 | 确认 STATUS、IRQ_STATUS、ERROR_CODE 等只读或受控清除寄存器不能被普通写破坏 | P0 | Directed RAL write/readback | TC002 |
| F003 | 基础 INT8 matmul | 确认 4x4 INT8 A*B 结果写回 C memory 正确 | P0 | Directed data pattern + memory compare | TC003 |
| F004 | 基础 INT16 matmul | 确认 4x4 INT16 A*B 计算、符号扩展和写回正确 | P0 | Directed data pattern + memory compare | TC004 |
| F005 | 大尺寸/tiling | 覆盖 8x8、16x16、32x32、64x64 下 load/compute/store 多 tile 调度 | P0 | Directed size sweep + timeout/done check | TC005, TC006, TC007, TC008 |
| F006 | 矩形和非对齐尺寸 | 覆盖 M/N/K 不相等、非 4 对齐、尾 tile 和 mask 行为 | P0 | Directed matrix shape sweep + memory compare | TC009, TC010 |
| F007 | 退化维度 | 覆盖 M/N/K 为 1 的边界矩阵，确认最小维度不误报 error | P1 | Directed edge dimension | TC011 |
| F008 | back-to-back operation | 连续启动多次 operation 时状态清除、配置更新和结果独立性正确 | P0 | Directed repeated start/clear | TC012 |
| F009 | precision 切换 | 连续 operation 在 INT8/INT16 间切换，确认配置不会串扰 | P0 | Directed back-to-back precision switch | TC013 |
| F010 | bias post-op | 确认 bias 读取、按列加 bias、C 结果正确 | P0 | Directed bias preload + golden compare | TC014 |
| F011 | ReLU post-op | 确认负数结果被 clamp 到 0，非负结果保持 | P0 | Directed signed pattern + golden compare | TC015 |
| F012 | bias + ReLU 顺序 | 确认先加 bias 后执行 ReLU | P0 | Directed post-op ordering check | TC016 |
| F013 | saturation/overflow | 覆盖 SAT_WRAP 和 SAT_SATURATE，确认 C 结果、overflow_seen 状态正确 | P0 | Directed overflow data + STATUS check | TC017, TC018 |
| F014 | DMA burst_len | 覆盖合法 burst_len 配置、burst_len=0、burst_len 超限处理 | P1 | Directed DMA_CFG + AXI ARLEN monitor | TC019, TC036, TC037 |
| F015 | AXI ready delay/backpressure | 确认 AXI slave ready delay 下 DUT 能完成读写且结果正确 | P1 | SVT AXI slave sequence delay injection | TC020 |
| F016 | 非对齐 C base 写回 | 覆盖写回地址非自然对齐场景，确认 byte lane 和 C 数据正确 | P1 | Directed unaligned writeback + memory compare | TC021 |
| F017 | IRQ 正常完成 | irq_en 下 operation done 后 STATUS.irq 和外部 irq pin 正确，clear 后撤销 | P0 | Directed IRQ check | TC022 |
| F018 | 非法矩阵尺寸 | M/N/K 为 0 或超过 MAX_DIM 时必须进入 error，ERROR_CODE 正确 | P0 | Negative directed | TC023 |
| F019 | 非法 precision | 非 INT8/INT16 precision 编码必须报 ERR_ILLEGAL_PRECISION | P0 | Negative directed | TC024 |
| F020 | base address 未对齐 | A/B/C/bias base address 未对齐时必须报 ERR_UNALIGNED_BASE_ADDR | P0 | Negative directed | TC025 |
| F022 | AXI read error | AXI read SLVERR、bias read error 必须报 ERR_AXI_READ_ERROR | P0 | SVT AXI slave error injection | TC029, TC030 |
| F023 | AXI write error | AXI write SLVERR、中途写错误必须报 ERR_AXI_WRITE_ERROR | P0 | SVT AXI slave error injection | TC031, TC032 |
| F024 | command 状态机非法 start | busy 或 done 未清除时再次 start，必须报 command error 且状态符合预期 | P0 | Directed command hazard | TC033, TC034 |
| F025 | 4KB boundary | DMA burst 不应跨 4KB boundary，非法场景报 ERR_BURST_CROSS_4KB | P1 | Directed boundary address + AR monitor | TC035 |
| F026 | internal timeout | AXI read 长时间无响应时进入 ERR_INTERNAL_TIMEOUT，不误判 done | P0 | Force rvalid low + monitor | TC038 |
| F027 | reset/soft reset | soft reset 和 load/compute/store 阶段 reset 后状态、错误码、IRQ、活跃信号恢复正确 | P0 | Directed reset injection + recovery operation | TC039, TC040, TC041, TC042, TC043 |
| F028 | error clear recovery | error clear 后可重新执行合法 operation 且结果正确 | P0 | Negative + clear + positive recovery | TC044 |
| F029 | constrained random 合法空间 | 随机组合 M/N/K、precision、post-op、sat_mode、burst_len、base，提升交叉覆盖 | P1 | Constrained random multi-seed | TC045 |
| F030 | corner data random | 覆盖极值、负数、零、溢出倾向数据组合 | P1 | Constrained random corner operand | TC046 |
| F031 | max stress random | 覆盖高维度和复杂配置压力组合 | P1 | Constrained random stress + multi-seed | TC047 |

## 3. Testcase List

| Testcase ID | 测试名称 | 测试目的 | 激励方式 | 检查点 | 覆盖 feature |
|---|---|---|---|---|---|
| TC001 | `tensor_base_reg_rw_test` | 验证寄存器 reset、读写和 reserved bit 行为 | RAL read/write directed sequence | register readback、STATUS/ERROR_CODE 初值 | F001 |
| TC002 | `tensor_base_ro_reg_protection_test` | 验证只读/状态寄存器保护 | RAL 强制写保护寄存器 | 写后状态不被非法修改 | F002 |
| TC003 | `tensor_base_int8_4x4_test` | 验证基本 INT8 4x4 matmul | 固定 pattern 预加载 A/B | STATUS.done、ERROR_CODE=0、C memory compare | F003 |
| TC004 | `tensor_base_int16_4x4_test` | 验证基本 INT16 4x4 matmul | 固定 INT16 pattern 预加载 A/B | C memory compare、符号结果正确 | F004 |
| TC005 | `tensor_base_8x8_test` | 验证 8x8 方阵 | directed matrix size | done/no error、C memory compare | F005 |
| TC006 | `tensor_base_16x16_test` | 验证 16x16 方阵和多 tile | directed matrix size | done/no error、C memory compare | F005 |
| TC007 | `tensor_base_32x32_test` | 验证 32x32 方阵压力 | directed matrix size | timeout 内完成、C memory compare | F005 |
| TC008 | `tensor_base_64x64_test` | 验证最大维度 64x64 | directed max dimension | timeout 内完成、C memory compare | F005 |
| TC009 | `tensor_base_rect_matrix_test` | 验证矩形矩阵 | directed M/N/K 不相等 | C memory compare | F006 |
| TC010 | `tensor_base_non_aligned_size_test` | 验证非 4 对齐尺寸和尾 tile | directed non-aligned dimensions | 尾部结果正确、无越界 error | F006 |
| TC011 | `tensor_base_degenerate_dims_test` | 验证 M/N/K 为 1 的边界尺寸 | directed degenerate dimensions | done/no error、C memory compare | F007 |
| TC012 | `tensor_base_back_to_back_test` | 验证连续 operation | 多次 program/start/wait/clear | 每次结果独立、状态正确清除 | F008 |
| TC013 | `tensor_base_bb_precision_switch_test` | 验证连续 operation precision 切换 | back-to-back INT8/INT16 配置 | 两种 precision 结果均正确 | F009 |
| TC014 | `tensor_base_bias_test` | 验证 bias post-op | 预加载 bias vector | C=A*B+bias | F010 |
| TC015 | `tensor_base_relu_test` | 验证 ReLU post-op | 构造含负数结果的数据 | 负值输出为 0，非负值保持 | F011 |
| TC016 | `tensor_base_bias_relu_order_test` | 验证 bias + ReLU 顺序 | bias + signed operand directed | 先 bias 后 ReLU 的 golden compare | F012 |
| TC017 | `tensor_base_saturation_test` | 验证 saturation 结果 | 溢出倾向数据，SAT_WRAP/SAT_SATURATE 对比 | wrap/saturate 结果、STATUS.overflow_seen | F013 |
| TC018 | `tensor_base_overflow_status_test` | 验证 overflow status | 构造 overflow 场景 | STATUS.overflow_seen 置位和清除行为 | F013 |
| TC019 | `tensor_base_burst_len_test` | 验证合法 burst_len | 配置 1/4/8/16 等 burst_len | operation 完成、AXI burst 行为合理 | F014 |
| TC020 | `tensor_base_axi_ready_delay_test` | 验证 AXI ready delay | 自定义 SVT AXI slave memory sequence 注入 ready delay | done/no error、C memory compare | F015 |
| TC021 | `tensor_base_write_unaligned_test` | 验证非对齐写回 | C base 非对齐配置 | byte lane/写回数据正确 | F016 |
| TC022 | `tensor_base_irq_test` | 验证正常完成 IRQ | irq_en operation | STATUS.irq、外部 irq pin、clear irq | F017 |
| TC023 | `tensor_err_illegal_matrix_size_test` | 验证非法矩阵尺寸 | M/N/K 为 0 或越界 | STATUS.error、ERR_ILLEGAL_MATRIX_SIZE | F018 |
| TC024 | `tensor_err_illegal_precision_test` | 验证非法 precision | 写非法 precision 编码 | STATUS.error、ERR_ILLEGAL_PRECISION | F019 |
| TC025 | `tensor_err_unaligned_base_test` | 验证 base address 未对齐 | A/B/C/bias base 低位非 0 | STATUS.error、ERR_UNALIGNED_BASE_ADDR | F020 |
| TC026 | `tensor_err_axi_read_slverr_test` | 验证 AXI read SLVERR | SVT AXI slave 注入 read SLVERR | STATUS.error、ERR_AXI_READ_ERROR | F022 |
| TC027 | `tensor_err_axi_read_bias_error_test` | 验证 bias read error | bias 读取阶段注入 read error | STATUS.error、ERR_AXI_READ_ERROR | F022 |
| TC028 | `tensor_err_axi_write_slverr_test` | 验证 AXI write SLVERR | SVT AXI slave 注入 write SLVERR | STATUS.error、ERR_AXI_WRITE_ERROR | F023 |
| TC029 | `tensor_err_axi_write_mid_row_error_test` | 验证写回中途错误 | C 写回过程中注入 error | STATUS.error、ERR_AXI_WRITE_ERROR | F023 |
| TC030 | `tensor_err_command_while_busy_test` | 验证 busy 期间重复 start | operation busy 后再次写 START | STATUS.error、ERR_COMMAND_WHILE_BUSY | F024 |
| TC031 | `tensor_err_start_while_done_test` | 验证 done 未清除时重复 start | operation done 后不 clear 再 start | done 保持、error 置位、ERROR_CODE 正确 | F024 |
| TC032 | `tensor_err_burst_cross_4kb_test` | 验证 burst 跨 4KB 保护 | 构造接近 4KB 边界的 base/burst | 无非法 AR burst、ERR_BURST_CROSS_4KB | F025 |
| TC033 | `tensor_err_burst_len_zero_test` | 验证 burst_len=0 | DMA_CFG burst_len 写 0 | 不正常 done，进入 error 或 timeout 检查 | F014 |
| TC034 | `tensor_err_burst_len_exceed_test` | 验证 burst_len 超限 | performance/超限 burst_len 配置 | AXI ARLEN 不超过允许值或报错 | F014 |
| TC035 | `tensor_err_internal_timeout_test` | 验证 internal timeout | 强制 AXI RVALID 低 | STATUS.error、ERR_INTERNAL_TIMEOUT、无 done | F026 |
| TC036 | `tensor_reset_during_load_test` | 验证 load 阶段 reset | load_active 时 apply_reset | 状态恢复、后续 operation 可正常执行 | F027 |
| TC037 | `tensor_reset_during_compute_test` | 验证 compute 阶段 reset | compute_active 时 apply_reset | 状态恢复、后续 operation 可正常执行 | F027 |
| TC038 | `tensor_reset_during_store_test` | 验证 store 阶段 reset | store_active 时 apply_reset | 状态恢复、后续 operation 可正常执行 | F027 |
| TC039 | `tensor_soft_reset_test` | 验证 busy 期间 soft reset | operation busy 后写 soft_reset | STATUS 清零、ERROR_CODE 清零、恢复 operation | F027 |
| TC040 | `tensor_soft_reset_during_idle_test` | 验证 idle soft reset | idle 状态写 soft_reset | 无误报 error，寄存器状态合理 | F027 |
| TC041 | `tensor_err_clear_error_recovery_test` | 验证 clear error 后恢复 | 先触发 error，再 clear，再执行合法 operation | error/irq 清除，合法 operation pass | F028 |
| TC042 | `tensor_base_random_legal_test` | 验证合法随机配置空间 | constrained random，regression 中多 seed、多 iteration | done/no error、C memory compare、coverage sample | F029 |
| TC043 | `tensor_base_random_corner_data_test` | 验证 corner data | 随机极值/零/负值/溢出倾向 operand | golden compare、overflow/saturation 行为 | F030 |
| TC044 | `tensor_base_random_max_stress_test` | 验证高压力随机场景 | 大尺寸和复杂 post-op/sat 随机 | timeout 内完成、C memory compare | F031 |

## 4. Checking Strategy

### 4.1 Reference Model

当前环境包含 `tensor_accel_ref_model`，其预测逻辑以 `tensor_accel_matrix_item` 为输入，执行 signed matrix multiply，并根据 `post_op` 执行 bias 和 ReLU。现有主要 directed/random sequence 还在 sequence 内部实现了 golden 计算和 memory compare：

- `tensor_matmul_vseq` 负责生成 A/B pattern、预加载外部 memory、计算 golden C、读取实际 C 并逐元素比较。
- `tensor_bias_vseq` 和 random vseq 在 golden 中加入 bias、ReLU、saturation/wrap 行为。
- 后续建议将 sequence 内 golden compare 收敛到统一 `reference model + analysis port + scoreboard` 流程，减少重复 golden 逻辑。

### 4.2 Scoreboard

`tensor_accel_scoreboard` 继承 `uvm_subscriber #(tensor_accel_matrix_item)`，核心检查方式为：

- 检查 `expected_c.size()` 与 `actual_c.size()` 一致。
- 对 `expected_c[idx]` 和 `actual_c[idx]` 逐元素四态比较。
- 记录 `compare_count` 和 `mismatch_count`，并通过 `cfg.add_scb_check_count()` / `cfg.add_scb_check_error()` 汇总检查结果。

当前已实现 scoreboard 组件，但实际主路径测试更多通过 vseq 内部 compare 完成。计划目标是将所有 matmul 类用例补齐 transaction 发布路径，使 scoreboard 成为统一数据结果检查点。

### 4.3 Assertion

当前 regression 已开启 `-cm line+cond+fsm+branch+tgl+assert`。DUT 内部固定 scratchpad 地址规划、descriptor FIFO 基本行为和 store row buffer 边界通过 assertion 检查，协议类 assertion 主要来自 VIP 侧。建议继续补充以下 assertion：

- AXI-Lite：valid/ready 握手后 response 必须返回，读写 response 不为 X。
- AXI4 read/write：burst 内 `len/size/last` 一致，禁止跨 4KB burst，`VALID` 保持直到 `READY`。
- command_fsm：busy/done/error 状态互斥关系，非法 start 必须进入 error。
- reset/soft reset：reset 后 busy/load/compute/store/irq/error 清零。
- register：RO register 普通写不改变状态，clear pulse 只影响对应 sticky bit。
- scratchpad 固定规划：内部 A0/A1/B/bias window 不重叠、不越界。
- store/writeback：post-process row index、store row buffer read/write index、write descriptor row_count 不越界。
- config freeze：start 被接受后，operation 执行期使用 frozen config，mid-flight 软件写配置不影响当前 operation。

### 4.4 Monitor

当前 monitor 主要由 Synopsys SVT AXI VIP 提供：

- AXI-Lite master monitor 连接到 `uvm_reg_predictor`，用于 RAL mirror/predict。
- AXI slave monitor/sequence 支持 memory model、ready delay、SLVERR 注入。
- 个别异常 vseq 直接监控 DUT/接口信号，例如 ARLEN、AR burst 是否跨 4KB、RVALID 是否被压低、`load_active/compute_active/store_active` 阶段 reset。

计划目标：

- 保持 SVT AXI monitor 作为协议与 transaction 观测基础。
- 增加 tensor-level monitor，将 program/start/done/error/C writeback 汇聚为 `tensor_accel_matrix_item`。
- 将 monitor 采集到的 transaction 同时送入 coverage 和 scoreboard，减少 vseq 对内部信号和 memory backdoor 的直接依赖。

## 5. Coverage Plan

### 5.1 功能覆盖率

当前 `tensor_accel_coverage` 已定义以下 coverpoint：

- `cp_m/cp_n/cp_k`：覆盖 1、小尺寸 2-15、中尺寸 16-32、最大 64。
- `cp_precision`：覆盖 `PREC_INT8`、`PREC_INT16`。
- `cp_post_op`：覆盖 `POST_NONE`、`POST_BIAS`、`POST_RELU`、`POST_BIAS_RELU`。
- `cp_sat_mode`：覆盖 `SAT_WRAP`、`SAT_SATURATE`。
- `cp_burst_len`：覆盖 1/4/8/16 和 17-256 performance 区间。
- `cp_overflow`：覆盖 overflow 未发生/发生。
- `cp_error`：覆盖正常完成/错误完成。
- `x_precision_post_op`：覆盖 precision 与 post_op 交叉。

功能覆盖目标：

- P0 feature 对应 coverpoint 和 testcase 全部命中。
- `precision x post_op` 交叉覆盖达到 100%。
- M/N/K 的 min、small、medium、max bins 均至少命中一次。
- `sat_mode` 两个 bins 均命中，且 overflow seen 至少命中 wrap 和 saturate 场景。
- error 类 testcase 覆盖所有 `error_code_e` 非零枚举。
- random regression 至少运行 3 个 seed，每个 random test 至少 5 次 iteration；收敛阶段根据 coverage hole 增加 seed 或 directed case。

待补功能覆盖项：

- `error_code` coverpoint 与 `error_code x irq_en` 交叉。
- `reset_phase` coverpoint：idle/load/compute/store。
- `axi_resp` coverpoint：OKAY/SLVERR for read/write。
- `burst_cross_4kb`、`unaligned_base`、`command_hazard` 独立 coverpoint。

### 5.2 代码覆盖率

regression 脚本当前默认 `COV=1`，仿真命令开启：

```text
-cm line+cond+fsm+branch+tgl+assert
```

代码覆盖目标：

- Block-level merged line coverage >= 90%。
- Branch/condition coverage >= 85%，未覆盖分支需要分类为不可达、异常分支待测或真实 coverage hole。
- FSM coverage >= 90%，command_fsm、load_scheduler、tile_count_fsm、buffer_manager_fsm、store_fsm、DMA FSM 的主要状态和状态跳转必须覆盖。
- Toggle coverage 作为辅助指标，目标 >= 80%；对常量 tie-off、参数裁剪、未使用高位信号允许 waiver。
- 覆盖报告输出目录为 `tb/sim/sim/merged_cov_report`，覆盖数据库为 `tb/sim/sim/merged_cov.vdb`。

### 5.3 断言覆盖目标

当前 DUT 专用 assertion 尚未系统化落地，因此断言覆盖分两阶段：

- 阶段 1：保持仿真 `assert` coverage 打开，确认 VIP/仿真器层面无 assertion failure。
- 阶段 2：补充 DUT SVA 后，目标为所有 P0 assertion 至少触发 pass 一次，关键错误场景 assertion cover property 至少命中一次。

建议断言覆盖目标：

- AXI handshake assertion pass coverage：100%。
- command_fsm 状态互斥与非法 start assertion pass coverage：100%。
- reset/soft reset 清零 assertion pass coverage：100%。
- 4KB boundary、burst_len 限制、固定 scratchpad 地址规划 assertion pass coverage：100%。
- 所有 assertion failure 均作为 P0/P1 bug 记录到 `tb/doc/bug_log.md`，除非已证明为 testbench 配置问题。

## 6. Regression Plan

当前 `tb/sim/run_regression.sh` regression 组织方式：

- Directed tests：23 个 testcase，seed=`SEED`。
- Exception tests：23 个 testcase，seed=`SEED`。
- Random tests：3 个 testcase，每个运行 `SEED`、`SEED+1`、`SEED+2`，并传入 `+RAND_ITERS=5`。
- 默认执行 coverage merge，生成 merged coverage database 和 HTML report。

建议 signoff 顺序：

1. 每次 RTL 修改后运行受影响 directed/exception testcase。
2. 每日或阶段性运行完整 regression。
3. 完整 regression 通过后分析 merged coverage，针对 hole 增补 directed test 或 random constraint。
4. 所有 P0 feature testcase pass，功能覆盖和代码覆盖达到目标后进入 block-level verification signoff。
