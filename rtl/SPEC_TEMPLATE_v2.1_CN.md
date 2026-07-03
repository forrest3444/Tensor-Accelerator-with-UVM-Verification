[English](SPEC_TEMPLATE_v2.1.md) | **中文**

# SPEC Template Lite

本模板用于从不完整的设计需求生成初始 RTL 模块规格说明。

生成的 SPEC 必须明确区分已确认需求、推断设计决策和待解决问题。Agent 可以做出合理的工程决策，但不得隐藏假设。

---

## 1. Module Overview

### Module Name

`<module_name>`

### Purpose

用一段简洁的话描述模块的功能。

### Role in System

描述该模块在更大系统中的位置。

示例：

* 数据路径级
* 协议适配器
* 控制块
* 缓冲区
* 算术单元
* 寄存器块
* 流处理器
* 桥接组件

---

## 2. Requirement Source

### User-Provided Requirements

仅列出用户明确给出的事实。

* 需求 1
* 需求 2

### Agent-Inferred Requirements

列出 Agent 推断的合理假设或决策。

| 序号 | 推断决策         | 原因         |
| ---- | ---------------- | ------------ |
| 1    | `<decision>`     | `<reason>`   |

### Open Questions

列出可能影响 RTL 架构或验证的未解决问题。

| ID | 问题         | 影响         | 默认假设         |
| -- | ------------ | ------------ | ---------------- |
| Q1 | `<question>` | `<impact>`   | `<assumption>`   |

---

## 3. Scope

### Supported Features

* 功能 1
* 功能 2

### Unsupported Features

* 不支持的功能 1
* 不支持的功能 2

### Explicit Non-Goals

列出本模块不会实现的行为。

* 非目标 1
* 非目标 2

---

## 4. Parameters

| 参数          | 默认值 | 合法范围 | 描述       |
| ------------- | -----: | -------- | ---------- |
| `DATA_WIDTH`  |     32 | `>= 1`   | 数据位宽   |

### Parameter Notes

* 说明每个参数是否影响接口位宽、延迟、存储深度或行为。
* 非法的参数值必须被拒绝或在文档中注明。

---

## 5. Clock and Reset

| 信号    | 方向       | 描述           |
| ------- | ---------: | -------------- |
| `clk`   |     input  | 主时钟         |
| `rst_n` |     input  | 低有效复位     |

### Reset Requirements

复位后：

* 输出有效/控制信号必须处于安全值。
* FSM 状态必须合法。
* 内部计数器必须合法。
* 不得产生虚假的传输、写入、完成、错误或中断。

### Reset Assumptions

* 复位类型：
* 复位释放假设：
* 是否支持传输中途复位：

---

## 6. interface contract

### Port Summary

| 信号       |       方向 |     位宽 | 描述             |
| ---------- | ---------: | -------: | ---------------- |
| `<signal>` | input/output | `<width>` | `<description>` |

### Interface Groups

按功能对端口进行分组。

* 输入数据接口：
* 输出数据接口：
* 配置接口：
* 状态/错误接口：
* 存储器/寄存器接口：
* 中断接口：

### Interface Rules

* 信号极性：
* 信号稳定性要求：
* 顺序规则：
* 错误响应规则：
* 背压行为：

---

## 7. Handshake and Flow Control

仅当模块包含 valid/ready、req/ack、enable/done 或类似的流控机制时，才使用本节。

### Transfer Rule

精确定义传输何时被接受或完成。

示例：

```systemverilog
transfer = valid && ready;
```

### Input Flow Control

* 输入何时被接受：
* 输入何时可能被反压：
* 反压期间输入有效载荷是否必须保持稳定：

### Output Flow Control

* 输出何时变为有效：
* 输出何时被消费：
* 反压期间输出有效载荷是否必须保持稳定：

### Combinational Dependency Policy

说明以下路径是否允许。

| 路径                                  | 是否允许 | 原因         |
| ------------------------------------- | -------- | ------------ |
| 下游 ready -> 上游 ready              | 是/否    | `<reason>`   |
| 下游 ready -> 上游 valid              | 是/否    | `<reason>`   |
| 输入 valid -> 输入 ready              | 是/否    | `<reason>`   |

任何允许的组合依赖必须明确标记为时序风险。

---

## 8. Functional Behavior

### High-Level Behavior

按步骤描述行为。

1. 步骤 1
2. 步骤 2
3. 步骤 3

### Cycle-Level Behavior

在可能的情况下描述重要的周期级行为。

| 事件       | 条件           | 行为           |
| ---------- | -------------- | -------------- |
| 输入被接受 | `<condition>`  | `<behavior>`   |
| 输出被产生 | `<condition>`  | `<behavior>`   |
| 反压       | `<condition>`  | `<behavior>`   |
| 复位       | `<condition>`  | `<behavior>`   |

### State and Data Update Rules

* 状态更新时机：
* 状态保持时机：
* 状态清除时机：
* 数据捕获时机：
* 数据输出时机：

---

## 9. Latency, Throughput, and Ordering

### Latency

* 最小延迟：
* 最大延迟：
* 固定或可变：
* 延迟变化的原因：

### Throughput

* 最大吞吐量：
* 是否可每周期接受输入？
* 是否可每周期输出？
* 连续输入下的行为：
* 连续输出反压下的行为：

### Ordering

* 输出顺序是否与输入顺序一致？
* 是否允许重排序？
* 是否使用 ID/标签？
* 是否支持丢弃/重试/刷新？

---

## 10. State Machine and Control

仅当需要 FSM 时使用本节。

### FSM Summary

| FSM            | 用途         | 复位状态     |
| -------------- | ------------ | ------------ |
| `<fsm_name>`   | `<purpose>`  | `<state>`    |

### State List

| 状态    | 含义         | 退出条件       |
| ------- | ------------ | -------------- |
| `IDLE`  | `<meaning>`  | `<condition>`  |

### Illegal State Behavior

* 恢复状态：
* 非法状态期间的输出行为：
* 必需的断言：

如果不需要 FSM，请声明：

```text
不需要显式的 FSM。
```

---

## 11. Data Format and Arithmetic

仅当模块执行算术、编码、解码、比较、映射或格式转换时使用本节。

### Data Format

| 信号       | 格式               | 有符号？ | 位宽 | 备注       |
| ---------- | ------------------ | -------- | ---: | ---------- |
| `<signal>` | 整数/定点/枚举     | 是/否    |    N | `<notes>`  |

### Arithmetic Rules

* 符号性：
* 中间位宽：
* 输出位宽：
* 舍入：
* 饱和：
* 上溢：
* 下溢：
* 截断：
* 扩展：

如果不执行算术运算，请声明：

```text
不执行算术变换。
```

---

## 12. Storage and Buffering

仅当模块包含 FIFO、RAM、队列、寄存器文件或内部缓冲时使用本节。

| 存储     | 类型               | 深度 | 位宽 | 用途         |
| -------- | ------------------ | ---: | ---: | ------------ |
| `<name>` | FIFO/RAM/寄存器    |    N |    M | `<purpose>`  |

### Buffer Behavior

* 空行为：
* 满行为：
* 同时读写：
* 上溢行为：
* 下溢行为：
* 读延迟：
* 写延迟：

如果不使用存储，请声明：

```text
不需要除pipeline/控制寄存器之外的内部存储。
```

---

## 13. Error and Corner Cases

### Error Behavior

| 条件           | 预期行为         | 恢复方式         |
| -------------- | ---------------- | ---------------- |
| `<condition>`  | `<behavior>`     | `<recovery>`     |

### Corner Cases

* 空闲期间复位：
* 活跃操作期间复位：
* 活跃操作期间反压：
* 最小合法值：
* 最大合法值：
* 计数器边界值：
* 空/满条件（如适用）：
* 非法输入（如适用）：
* 不支持的功能访问（如适用）：

---

## 14. CDC and Timing Assumptions

### CDC

* 时钟域数量：
* 复位域数量：
* CDC 跨域：
* 所需的 CDC 结构：
* CDC 待解决问题：

如果仅单时钟，请声明：

```text
本模块为单时钟设计，没有 CDC 跨域。
```

### Timing-Awareness

识别可能的时序敏感逻辑。

* 宽多路选择器：
* 宽比较器：
* 长算术链：
* 高扇出控制：
* 未寄存的输出：
* Valid/Ready 组合路径：
* 大存储访问：
* 深度解码：

### Timing Mitigation

* 寄存输出：
* pipeline切点：
* Skid Buffer：
* 预解码：
* 资源复制：
* 其他缓解措施：

---

## 15. Required Assertions

列出必需的设计/协议断言。

* 复位清除输出 valid/控制信号。
* 反压期间有效载荷保持稳定。
* 无 valid 和 ready 时不发生传输。
* FSM 状态合法。
* 计数器保持在合法范围内。
* 复位后无未知控制值。
* CDC 握手正确性（如适用）。

---

## 16. Minimum Verification Requirements

这不是完整的验证计划，仅定义 RTL 被接受前必须完成的最低检查。

### Required Dynamic Tests

* 冒烟测试：
* 复位测试：
* 基本合法传输测试：
* 背压/反压测试（如存在流控）：
* 边界情况测试：
* 错误情况测试（如存在错误行为）：

### Required Review Evidence

* RTL 编译通过。
* 基本仿真通过。
* 复位行为已被观察或已添加断言。
* 基本测试中无断言失败。
* 已知限制已记录在案。

---

## 17. Final SPEC Summary

### Confirmed Design Decisions

* 决策 1
* 决策 2

### Agent Assumptions

* 假设 1
* 假设 2

### Human Review Required

| ID  | 项目       | 重要性原因       |
| --- | ---------- | ---------------- |
| HR1 | `<item>`   | `<reason>`       |

### SPEC Status

* 草稿
* 待审查
* 已批准用于 RTL 生成
* 因待解决问题而阻塞
