# Lua Obfuscator v2.10.0 Release Notes

**发布日期：2026-07-24**

## 概要

P2 函数级 VM 保护：通过 `--@vm` 注解选择性保护关键函数，兼顾强度与性能。

## 新增

### 函数级 VM 保护 (Function-Level VM)
- 新增 `vm_function` Pass（`passes/vm_function.lua`）
- 通过 `--@vm` 注解标记需要保护的顶层函数
- 每个函数独立编译为 VM 字节码，运行时按需解密执行
- 与整文件 VM (`vm_protect`) 互斥：启用函数级 VM 时自动关闭整文件 VM

### 注解语法
```lua
--@vm
local function sensitive_algorithm(data)
  -- 此函数将被 VM 字节码虚拟化保护
  return transform(data)
end

local function normal_function(x)
  -- 此函数不受影响
  return x + 1
end
```

### CLI
- `--vm-function`：启用函数级 VM 保护

### Web
- 新增 "函数级VM保护" 复选框
- 预设：balanced/max 默认开启，fast 默认关闭

## 修复

- 修复 `protect_as_expr` 函数体解析 bug（`func_stmt.body` → `func_stmt.body.stmts`）
- 修复 `protect_as_expr` 输出作用域问题（移除外层 `do...end` 包裹）

## 测试

- `tests/test_vm_function.lua`：4 个测试用例
  - 单函数保护
  - 多函数选择性保护
  - 递归函数保护
  - 无注解时透传

## 版本

- 版本号：v2.10.0
- CLI / Web / 输出头 / package.json / 文档均已更新

## 升级

```bash
git pull origin main
```
