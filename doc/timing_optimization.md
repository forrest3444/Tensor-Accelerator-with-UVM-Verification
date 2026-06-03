# 时序优化迭代记录

## 环境

- 工艺库: Nangate 45nm (FreePDK45), Typical Corner, 1.1V / 25°C
- STA 工具: OpenSTA
- 综合: Yosys 0.66 + ABC
- 目标频率: 250 MHz (4.0 ns)

---

## axi_write_dma 时序优化迭代

### 初始状态 (v0 — 优化前)

| 指标 | 值 |
|------|-----|
| WNS | **-4.51 ns** |
| TNS | **-801.2 ns** |
| 违例路径 | 100/100 (全部来自 state_q[1]) |
| 面积 | 4,012 |
| 寄存器 | 77 DFFR_X1 |
| 最差路径深度 | ~65 级门 |

**瓶颈**: `state_q[1] → spad_addr_o[15]` (reg-to-output)

**根因**: FSM 状态寄存器 `state_q` 直接驱动所有 MUX 选择端 (`active_addr`, `active_byte_len`, `active_spad_offset`)，MUX 输出馈入纯组合的 `dma_burst_splitter` 和 slot 计算链，最终到达 `spad_addr_o`。全程无流水线寄存器。

```
state_q → MUX(组合) → splitter(组合,~25级) → slot_calc(组合) → spad_addr_o
└────────────────────── 7.71ns, 65级门 ──────────────────────────┘
```

扇出热点:
- `_2754_` NOR3_X1: fanout=145, 356fF, 2.84ns gate delay
- `_3662_` INV_X1: fanout=67, 161fF, 0.40ns gate delay

---

### 第 1 轮优化 (v1 → v2)

**改动**: 新增 `S_PLAN` 状态，插入流水线寄存器

- `state_q` 不再直接驱动 MUX —— MUX 输出由 `state_d` 预判，计算结果寄存器化
- `dma_burst_splitter` 输出寄存 (`burst_beats_q`, `burst_bytes_q`)
- `slot_*` 计算改为函数式，结果在对应状态消耗
- `segment_data_bytes` 等中间量位宽从 32b 缩减到 16b

**结果**:

| 指标 | 优化前 | 优化后 | 改善 |
|------|--------|--------|------|
| WNS | -4.51 ns | **+0.316 ns** | +4.83 ns |
| TNS | -801.2 ns | **0** | +801.2 ns |
| 最差路径深度 | 65 级 | 6 级 | -91% |
| 面积 | 4,012 | 4,409 | +10% |
| 寄存器 | 77 | 250 | +225% |

**新瓶颈**: `start_i → state_d` (input-to-register)

```
start_i → NAND3(fanout=121) → INV(fanout=73) → NOR2 → INV(fanout=141) → OAI21 → DFF
                              └── 6级门, slack +0.316ns ──┘
```

根因: `state_q == S_IDLE && start_i` 同时使能 ~188 个 DFF 的加载逻辑。

---

### 第 2 轮优化 (v2 → v3)

**改动**: 将 `start_i` 驱动的批量寄存器加载拆散

- 第 263 行的 `if (state_q == S_IDLE && start_i)` 只保留最小必要逻辑
- 地址/长度/偏移等非立即需要的寄存器加载推后到 `S_PLAN` 状态

**结果**:

| 指标 | v2 | v3 | 改善 |
|------|-----|-----|------|
| WNS slack | +0.316 ns | **+0.871 ns** | +0.555 ns |
| 最差路径深度 | 6 级 | 35 级 | 更深但 slack 更好 |
| 瓶颈 startpoint | start_i (input) | bytes_remaining_q (reg) | input→reg 变为 reg→reg |

**新瓶颈**: `bytes_remaining_q[0] → splitter → burst_bytes → reg`

```
bytes_remaining_q[0] → 32b ADD(transfer_bytes) → splitter(~25级) → segment比较 → reg
                       └────────── 35级门, slack +0.871ns ──────────────┘
```

根因: `dma_burst_splitter` 仍是纯组合模块，`transfer_bytes → splitter → burst_bytes` 串联深度大。

---

### 第 3 轮优化 (v3 → v4)

**改动**: 在 `transfer_bytes → splitter` 之间插入流水线寄存器

- `transfer_bytes` 计算与 splitter 输入分离为不同周期
- `S_PLAN` 状态内部再分拍

**结果**:

| 指标 | v3 | v4 | 改善 |
|------|-----|-----|------|
| WNS slack | +0.871 ns | **+1.110 ns** | +0.239 ns |
| 最差路径深度 | 35 级 | 10 级 | -71% |
| 瓶颈 startpoint | bytes_remaining_q | state_q[1] | splitter 路径消失 |
| 等效 Fmax | ~290 MHz | **~346 MHz** | +56 MHz |

**当前瓶颈**: `state_q[1] → state_d` (FSM 译码)

```
state_q[1] → NOR2 → NAND2 → INV → AND2 → NAND2(fanout=234) → INV → NOR2 → INV(fanout=141) → OAI21 → DFF
            └──────────────────── 10级门, slack +1.110ns ──────────────────────┘
```

根因: `state_q` 译码树驱动全模块 ~234 个条件分支。10 级门、slack +1.11ns，250MHz 下余量充裕。

---

### 总结

```
         WNS         TNS       面积    寄存器    等效 Fmax
v0:   -4.510 ns   -801.2 ns   4,012      77       ~155 MHz
v1:   +0.316 ns      0        4,409     250       ~260 MHz
v2:   +0.871 ns      0        4,971     —         ~290 MHz
v3:   +1.110 ns      0         —         —        ~346 MHz
─────────────────────────────────────────────────────────
累计:  +5.620 ns   +801.2 ns   +24%     +225%     +191 MHz
```

面积增加约 24%，换取了 5.6ns 的 slack 改善和 191MHz 的频率上限提升。

---

## mac_unit 时序优化迭代

详见 [mac_unit STA 报告](../sta/reports/mac_unit/)。

### 优化前

| 指标 | 值 |
|------|-----|
| 时钟 | 100 MHz (10 ns) |
| 面积 | 5,289 |
| 寄存器 | 41 DFFR_X1 |
| 乘法器 | 32b×32b 统一乘法器 |
| 流水线 | 单周期 (乘法+累加同一拍) |

### 优化后

| 指标 | 值 |
|------|-----|
| 时钟 | 250 MHz (4 ns) |
| 面积 | 4,172 (**-21%**) |
| 寄存器 | 74 DFFR_X1 |
| 乘法器 | 16b×16b (按精度选择) |
| 流水线 | 2 级 (Stage1: 乘法, Stage2: 累加) |

### 微架构改动

1. **乘法器拆分**: INT8/INT16 分别使用 8b×8b / 16b×16b 乘法器，消除 32b×32b 的冗余
2. **2 级流水线**: `product_q` 寄存器拦断乘法→累加关键路径
3. **溢出检测简化**: 41b 常数比较 → 10b 符号位一致性检查
4. **acc_o 扩展到 40b**: 防止中间累加溢出
