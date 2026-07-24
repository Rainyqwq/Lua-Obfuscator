-- ================================================================
-- passes/header.lua
-- 浠ｇ爜澶撮儴
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 鍦ㄦ贩娣嗗悗鐨勪唬鐮佸紑澶存坊鍔犵増鏈爣璇嗗拰璀﹀憡淇℃伅
-- 杩欐槸 Pipeline 鐨勬渶鍚庝竴姝ワ紝涓嶆敼鍙樹唬鐮侀€昏緫

local M = {}

M.name    = "header"
M.title   = "娣诲姞浠ｇ爜澶?
M.version = "1.1.0"
M.order   = 200

function M.apply(code, _ctx)
  local header = string.format([=[
-- ============================================================
-- Obfuscated by Lua Obfuscator v2.10.0
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
