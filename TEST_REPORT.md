# 测试报告

## 测试环境

- Lua 5.4.8（CLI）
- Fengari（浏览器端 Lua VM）
- 测试日期：2025-07-22

## 核心测试

### test_85.lua - 核心测试

```
81/81 通过, 0 失败
```

覆盖：类型、算术、位运算、比较、逻辑、字符串、表、控制流、函数、闭包、协程、元表、OOP、模式匹配、错误处理、goto 等。

### test_full.lua - 完整测试

```
119/119 通过, 0 失败
```

在 test_85 基础上增加：嵌套调用、select、特殊字符、边界情况等。

## v2.5.1 修复验证

### 修复 1：CLI 默认配置

三个不稳定 Pass（`instruction_substitution`、`control_flow_flattening`、`bogus_control_flow`）的 CLI 默认值从 `true` 改为 `false`。

```
默认配置（非 VM）混淆 test_85：10/10 通过
```

### 修复 2：VM 模式自动禁用

VM 模式下自动禁用三个不兼容 Pass，避免正则重写破坏 VM 字节码解释器。

```
VM + 默认配置混淆 test_85（CLI）：10/10 通过
VM + 默认配置混淆 test_85（Bundle）：20/20 通过
```

### 修复 3：adv_fake_cf return 语句

虚假控制流增强 Pass 不再在 `return` 语句后注入代码块，修复 Lua 语法错误。

## 单 Pass 稳定性测试

对 fib+sort 代码进行 50 轮混淆验证：

| Pass | 结果 |
|------|------|
| string_encryption | 50/50 ✅ |
| variable_mangling | 50/50 ✅ |
| constant_encryption | 50/50 ✅ |
| advanced_fake_cf | 50/50 ✅ |
| junk_comments | 50/50 ✅ |

## 全面特性测试

### test_comprehensive.lua

20 个 Lua 特性模块，共 42 个测试用例：

```
总计: 42 | 通过: 4 | 失败: 38
```

通过的 Pass：`string_encryption`、`junk_comments`（单独和累积均通过）。
失败的 Pass：`variable_mangling`、`instruction_substitution`、`constant_encryption`、`control_flow_flattening`（见下方已知问题）。

## 已知问题

### 待修复 Bug

| Pass | 问题 | 复现条件 |
|------|------|----------|
| variable_mangling | 错误重命名表字段键 | `local t = {name="x", value=42}` 中字段键被重命名，但 `t["value"]` 仍引用原名 |
| constant_encryption | 错误加密标识符中的数字 | `ok2` → `ok(0xEC27~0xEC25)`，破坏变量声明语法 |

### 不稳定 Pass（默认关闭）

| Pass | 问题 | 复现条件 |
|------|------|----------|
| instruction_substitution | 等价替换改变语义 | 复杂表达式中的算术运算 |
| control_flow_flattening | elseif 链嵌套错误 | 长 elseif 链 + 深嵌套 |
| bogus_control_flow | 破坏控制流结构 | if/for/while 行后注入 |

以上 Pass 默认关闭，需手动开启。VM 模式下会被自动禁用。

## 性能基准

| 指标 | 值 |
|------|------|
| 单次混淆（fib+sort） | ~0.5ms |
| 吞吐量 | ~678 KB/sec |
| 81 项测试 | < 1s |
| 119 项测试 | < 3s |
