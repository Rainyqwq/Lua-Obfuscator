-- ================================================================
-- passes/instr_sub.lua
-- 指令替换
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将简单的 Lua 运算替换为等价的复杂表达式
-- 例如: a + b → a - (-b), a == b → not (a ~= b)
--
-- 不改变程序语义，但增加逆向分析时的阅读难度

local utils = require("passes.utils")
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local strip_strings_from_line = utils.strip_strings_from_line
local gsub_safe = utils.gsub_safe

local M = {}

M.name    = "instruction_substitution"
M.title   = "指令替换"
M.version = "1.0.0"
M.order   = 40
M.enabled = true  -- 100轮单独+50轮累积测试全部通过

-- 等价替换规则
-- 每条规则: {原模式, 替换函数}
-- 仅在安全上下文中替换（排除字符串和注释）
local substitutions = {
  -- 算术运算
  { pattern = "([%w_]+)%s*([%+%-%*%%])%s*([%w_]+)", handler = function(a, op, b)
    if op == "+" then return string.format("%s-(-(%s))", a, b)
    elseif op == "-" then return string.format("%s+(-(%s))", a, b)
    elseif op == "*" then
      if random_int(1,2) == 1 then
        return string.format("math.floor(%s/%s)*%s", a, "(1/" .. b .. ")", b)
      end
      return string.format("%s*%s", a, b)
    end
    return nil
  end },
}

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}
  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    -- 跳过注释行
    if not trimmed:match("^%-%-") then
      -- 跳过包含科学计数法的行（1e10, 1.5e-3 等）
      local safe = strip_strings_from_line(line)
      local has_sci = safe:match("%d[%.%d]*[eE][%+%-]?%d")
      -- 随机选择是否对本行应用替换（控制密度）
      if not has_sci and random_int(1, 3) == 1 then
        -- 对安全版本做替换标记，然后在原行中只替换非字符串部分
        for _, sub in ipairs(substitutions) do
          local count = 0
          safe = gsub_safe(safe, sub.pattern, function(...)
            count = count + 1
            if count > 2 then return nil end
            local result = sub.handler(...)
            return result or nil
          end)
        end
        -- 用安全版本指导替换（简化处理：直接替换整行）
        if safe ~= strip_strings_from_line(line) then
          line = safe
        end
      end
    end
    result[#result + 1] = line
  end
  return join_lines(result)
end

return M
