# Lua Obfuscator v3.1.0 Release Notes

**发布日期：2026-08-13**

## 概要

- 修复 `vm_protect` + `var_mangle` 同时开启时的 VM 标记损坏问题
- 修复 `vm_function` + `var_mangle` 同时开启时 `__vm_N` 变量作用域错误
- 统一 VM 标记为 `vm_function`/`vm_protect` 共同管理，重构生成逻辑

## 修复

### VM 标记损坏（`vm_protect` + `var_mangle` 组合）

当 `vm_protect` 和 `var_mangle` 同时开启时，`var_mangle` 的 VM 块提取算法（`extract_vm_blocks`）使用简单的行首 `do`/`end` 匹配，无法正确处理 vm_protect 生成的深层嵌套代码（`for`、`function` 等内部块）。导致 VM 块被提前截断，块内标识符泄露到重命名范围，生成的 `table.concat(t)` 被错误重命名为 `table.concat(_piOTvw)`，运行时崩溃。

**修复方案：** 重写 `extract_vm_blocks`，改为按单词边界（`%f[^%w_]` 模式）计数 `function/for/while/if/elseif/repeat/do/end/until` 关键字，正确跟踪嵌套深度。

### `__vm_N` 变量作用域错误（`vm_function` + `var_mangle` 组合）

`vm_function` 的 `protect_as_expr` 将 `local __vm_N = ...` 声明放在 `do...end` 块内部，导致外部函数桩 `local function fibonacci(n) return __vm_1(n) end` 无法访问该变量（`attempt to call a nil value (global '__vm_1')`）。

**修复方案：** 在 `do...end` 块外部先声明 `local __vm_N`，块内仅做赋值（去掉 `local` 关键字），确保函数桩能正确引用。

## 改动

### `passes/vm.lua`
- `generate_vm_source()` 模板：移除 `-- VM Protected Code` 注释行和外层 `do...end` 包裹
- `protect_as_expr()`：VM 声明先 `local` 再在 `do...end` 块内赋值，解决作用域问题
- 版本号：v3.0.0 → v3.1.0

### `passes/vm_protect.lua`
- `apply()`：对 `vm.protect()` 输出外包 `do...end` + `-- @vm (protected)` 标记
- 版本号：v2.9.0 → v2.9.1

### `passes/var_mangle.lua`
- `extract_vm_blocks()`：重写关键字深度跟踪，正确计数嵌套块
- 版本号：v1.1.0 → v1.2.0

### `passes/header.lua`
- 输出头版本号 v3.0.0 → v3.1.0

### `obfuscator.lua`
- 版本号：v3.0.0 → v3.1.0

## 测试

- 33/33 测试全部通过（单 Pass 14 + 双 Pass 组合 14 + 全 Pass 稳定性 5 轮）
- `vm_protect` + `var_mangle` 组合：Runtime OK
- `vm_function` + `var_mangle` 组合：Runtime OK

## 构建

- `obfuscator_bundle.lua`：20 模块，234645 字节
- `index.html`：Web 版本同步更新