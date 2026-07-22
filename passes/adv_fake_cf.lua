-- ================================================================
-- passes/adv_fake_cf.lua
-- 虚假控制流增强
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 在代码中注入多层嵌套的虚假分支结构
-- 比 BCF 更深入：使用随机变量 + 多条件嵌套，大幅增加控制流复杂度
--
-- 注入的代码永远不会执行，但静态分析工具必须将其纳入考量

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local calc_depth = utils.calc_depth

local M = {}

M.name    = "advanced_fake_cf"
M.title   = "虚假控制流增强"
M.version = "1.0.0"
M.order   = 65  -- 在控制流平坦化之前执行，注入的虚假分支会被平坦化一并处理

-- 生成不透明谓词（始终为假，但不容易看出来）
local function generate_predicate()
  local v = "_p" .. random_id(3)
  local method = random_int(1, 4)
  if method == 1 then
    return string.format("(function() local %s=%d; return %s*%s<0 end)()", v, random_int(1,500), v, v)
  elseif method == 2 then
    return string.format("(function() local %s=%d; return %s<0 end)()", v, random_int(1,999), v)
  elseif method == 3 then
    return string.format("(function() local %s=%d; return (%s%%2)~=0 and (%s%%2)==0 end)()", v, random_int(1,100), v, v)
  else
    return string.format("(function() local %s=%d; return %s~=1 and %s==0 end)()", v, random_int(2,99), v, v)
  end
end

-- 生成一段虚假代码
local function generate_fake_block(indent)
  local lines = {}
  local vars = {}
  local count = random_int(2, 4)
  for i = 1, count do
    vars[i] = "_af" .. random_id(4)
    lines[#lines + 1] = string.format("%slocal %s=%d", indent, vars[i], random_int(0, 0xFFFF))
  end
  for i = 1, random_int(1, 3) do
    local a = vars[random_int(1, #vars)]
    local b = vars[random_int(1, #vars)]
    local ops = { "+", "-", "~", "*", "&" }
    lines[#lines + 1] = string.format("%s%s=%s%s%s", indent, a, a, ops[random_int(1,#ops)], b)
  end
  -- 加个递归调用伪装（不用 break，避免在循环外出错）
  if random_int(1, 2) == 1 then
    local lv = "_lp" .. random_id(3)
    lines[#lines + 1] = string.format("%slocal %s=%d", indent, lv, random_int(1,99))
    lines[#lines + 1] = string.format("%sif %s>%d then %s=%s-%d end", indent, lv, random_int(100,999), lv, lv, random_int(1,10))
  end
  return table.concat(lines, "\n")
end

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}
  local depth = 0

  for _, line in ipairs(lines) do
    local o, c = calc_depth(line)
    depth = depth + o - c

    result[#result + 1] = line

    -- 在函数开始和条件分支后注入虚假代码
    -- 不在 if/then 行后注入（避免破坏 elseif 链）
    local trimmed = line:match("^%s*(.-)%s*$") or ""
   if o > 0 and depth > 0 and random_int(1, 3) == 1 and
      not trimmed:match("then%s*$") and
      not trimmed:match("do%s*$") and
      not trimmed:match("^if%s") and
      not trimmed:match("^for%s") and
      not trimmed:match("^while%s") and
      not trimmed:match("^return") and
      not trimmed:match("^else") and
      not trimmed:match("^elseif%s") then
      local indent = line:match("^(%s*)") or ""
      local pred = generate_predicate()
      local fake = generate_fake_block(indent .. "  ")
      result[#result + 1] = string.format("%sif %s then", indent, pred)
      result[#result + 1] = fake
      result[#result + 1] = string.format("%send", indent)
    end
  end

  return join_lines(result)
end

return M
