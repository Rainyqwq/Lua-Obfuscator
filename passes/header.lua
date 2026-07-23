-- ================================================================
-- passes/header.lua
-- 代码头部
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 在混淆后的代码开头添加版本标识和警告信息
-- 这是 Pipeline 的最后一步，不改变代码逻辑

local M = {}

M.name    = "header"
M.title   = "添加代码头"
M.version = "1.1.0"
M.order   = 200

function M.apply(code, _ctx)
  local header = string.format([=[
-- ============================================================
-- Obfuscated by Lua Obfuscator v2.9.0
-- https://github.com/Rainyqwq/Lua-Obfuscator
-- Author: Rainy_qwq
--
-- WARNING: This code has been obfuscated.
-- Modifying it may break functionality.
-- ============================================================
-- Protection layers applied: (see pipeline log)
-- Generated: %s
-- ============================================================
]=], os.date and os.date("%Y-%m-%d %H:%M:%S") or "unknown")

  return header .. code
end

return M
