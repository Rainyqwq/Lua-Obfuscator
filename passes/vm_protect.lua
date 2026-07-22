-- ================================================================
-- passes/vm_protect.lua
-- VM 字节码虚拟化
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将 Lua 源码编译为自定义指令集，生成配套的 VM 解释器
-- 这是保护强度最高的 Pass，混淆后的代码完全不可逆
--
-- 工作原理：
--   1. 解析源码为 AST
--   2. 将 AST 编译为自定义字节码（不兼容标准 Lua 字节码）
--   3. 生成纯 Lua 实现的 VM 解释器 + 加密字节码数据
--   4. 运行时由 VM 解释器执行字节码

local M = {}

M.name        = "vm_protect"
M.title       = "VM字节码虚拟化"
M.description = "将Lua源码编译为自定义字节码，生成VM解释器执行。最强保护，代码完全不可逆。"
M.version     = "2.1.0"
M.author      = "Rainy_qwq"
M.order       = 10
M.enabled     = false  -- 默认关闭，需手动开启

function M.apply(code, ctx)
  local vm = ctx.vm_module or require("passes.vm")
  local result, err = vm.protect(code)
  if not result then
    error("VM保护失败: " .. tostring(err))
  end
  return result
end

return M
