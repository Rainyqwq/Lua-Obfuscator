# Pass API 文档

## 概述

Pass 系统将混淆功能模块化。每个 Pass 封装一种混淆技术，通过 PassManager 统一管理执行。

```
源代码 → [字符串提取] → [Pass 1] → [Pass 2] → ... → [字符串恢复] → 混淆后代码
```

## Pass 接口

```lua
{
  -- 必填
  name    = "string_id",        -- 唯一标识符
  title   = "显示名称",          -- UI 显示
  apply   = function(code, ctx) -- 核心变换
              return code       -- 返回变换后的代码
            end,

  -- 可选
  description = "功能描述",
  version     = "1.0.0",
  author      = "作者",
  order       = 100,            -- 执行顺序（越小越先）
  requires    = {},             -- 依赖的 Pass 名称
  enabled     = true,           -- 默认是否启用
  config      = {},             -- 配置项定义

  validate = function(code)     -- 验证函数（可选）
    return true                 -- true=通过, false+msg=失败
  end,
}
```

### 配置项定义

```lua
config = {
  { key = "method", label = "加密方式", type = "select",
    values = {"xor", "rot13"}, default = "xor" },
  { key = "depth", label = "深度", type = "number",
    default = 2, min = 1, max = 5 },
  { key = "prefix", label = "前缀", type = "string",
    default = "_" },
  { key = "verbose", label = "详细", type = "boolean",
    default = false },
}
```

## PassManager API

```lua
local PassManager = require("pass_manager")
local pm = PassManager.new()
```

| 方法 | 说明 |
|------|------|
| `pm:register(pass)` | 注册 Pass |
| `pm:list()` | 获取所有 Pass 列表 |
| `pm:get(name)` | 获取单个 Pass 信息 |
| `pm:set_enabled(name, bool)` | 启用/禁用 |
| `pm:set_config(name, key, val)` | 设置配置项 |
| `pm:run(code, opts)` | 执行 Pipeline |
| `pm:export_config()` | 导出配置 |
| `pm:import_config(config)` | 导入配置 |

### 执行 Pipeline

```lua
local result, log = pm:run(code, {
  vm_module = vm,                    -- 可选：预加载的 VM 模块
  on_pass = function(name, title, idx, total)  -- 进度回调
    print(string.format("[%d/%d] %s", idx, total, title))
  end,
})

-- log: { {name, title, elapsed, input_size, output_size}, ... }
```

## 内置 Pass（v2.8.0）

| order | name | title | 默认 | 说明 |
|-------|------|-------|------|------|
| 10 | `vm_protect` | VM 字节码虚拟化 | ❌ | 自定义字节码 + 解释器 |
| 15 | `anti_debug` | 反调试检测 | ❌ | hook / 计时 / JIT |
| 20 | `string_encryption` | 字符串加密 | ✅ | 分层字符串池 |
| 30 | `variable_mangling` | 变量名混淆 | ✅ | 局部变量随机化 |
| 40 | `instruction_substitution` | 指令替换 | ❌ | 原子表达式等价替换 |
| 50 | `constant_encryption` | 常量数字加密 | ✅ | Fengari 安全编码 |
| 65 | `advanced_fake_cf` | 虚假控制流增强 | ✅ | 不可达复杂分支 |
| 70 | `control_flow_flattening` | 控制流平坦化 | ❌ | dispatcher 重组 |
| 80 | `bogus_control_flow` | BCF 虚假控制流 | ❌ | 仅包装完整语句 |
| 85 | `call_indirection` | 调用间接化 | ❌ | 全局调用经分发表 |
| 90 | `basic_block_splitting` | 基本块拆分 | ✅ | goto/label 拆分 |
| 100 | `junk_comments` | 垃圾注释注入 | ✅ | 噪音注释 |
| 200 | `header` | 代码头部 | ✅ | 版本与警告头 |

Pass **不会**因启用 VM 而被流水线静默禁用。

## 执行顺序

```
order  10: VM 字节码虚拟化（最先）
order  20: 字符串加密
order  30: 变量名混淆
order  50: 常量数字加密
order  65: 虚假控制流增强
order  90: 基本块拆分
order 100: 垃圾注释注入
order 200: 代码头部（最后）
```

## VM 模式兼容性

启用 `vm_protect` 时，以下三个 Pass 会自动禁用（它们通过正则重写会破坏 VM 生成的字节码解释器）：

- `instruction_substitution`（order 40）
- `control_flow_flattening`（order 70）
- `bogus_control_flow`（order 80）

其余 Pass 与 VM 兼容，正常执行。此行为在 `obfuscator.lua` 的 `obfuscate()` 函数中实现。

## 添加自定义 Pass

1. 在 `passes/` 下新建文件
2. 实现标准接口
3. 在 `passes/init.lua` 的 `BUILTIN` 表中注册

```lua
-- passes/dead_code.lua
local M = {}
M.name = "dead_code"
M.title = "死代码注入"
M.order = 66
M.enabled = true

function M.apply(code, ctx)
  -- 在函数定义后注入死代码
  return code:gsub("function%s+([%w_]+)%s*%(", function(name)
    return string.format('if false then _=0 end\nfunction %s(', name)
  end)
end

return M
```

## 错误处理

Pass 内部用 `error()` 抛出异常：

```lua
function M.apply(code, ctx)
  local result, err = do_something(code)
  if not result then error("失败: " .. tostring(err)) end
  return result
end
```

PassManager 捕获错误并附带 Pass 名称重新抛出：

```
Pass 'vm_protect' (VM字节码虚拟化) 执行失败: 解析错误 at pos 123
```
