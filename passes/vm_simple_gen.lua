-- ================================================================
-- passes/vm_simple_gen.lua
-- 简单的 VM 代码生成器模板
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 用于生成混淆的 VM 代码模板

local M = {}

-- 将字符串转换为三位八进制转义的 Lua 字符串
-- Lua 支持 \ddd 格式（三位数八进制）
local function octal_escape(s)
  local backslash = string.char(92)  -- \
  local r = {}
  for i = 1, #s do
    local b = string.byte(s, i)
    r[#r + 1] = backslash .. string.format("%03d", b)
  end
  return table.concat(r)
end

-- 生成简单的 VM 模板代码
function M.generate_template(opts)
  opts = opts or {}

  local code = {}

  -- 获取全局引用
  table.insert(code, "local S=_G or _ENV or getfenv(0);")
  table.insert(code, "local type=" .. octal_escape("type") .. ";")
  table.insert(code, "local error=" .. octal_escape("error") .. ";")
  table.insert(code, "local select=" .. octal_escape("select") .. ";")
  table.insert(code, "local unpack=unpack or table.unpack;")

  -- 简单的 VM 数据
  table.insert(code, "local _d={1,2,3};")
  table.insert(code, "local _f=function()return 42;end;")

  -- 返回结果
  table.insert(code, "return 1;")

  return table.concat(code, "")
end

return M
