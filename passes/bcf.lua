-- ================================================================
-- passes/bcf.lua
-- BCF 虚假控制流
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 基于不透明谓词 (Opaque Predicate) 注入永远不会执行的代码分支
-- 只包装“完整、可独立执行的语句”，避免打断多行表达式 / function 定义

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines

local M = {}

M.name    = "bogus_control_flow"
M.title   = "BCF虚假控制流"
M.version = "1.1.0"
M.order   = 80
M.enabled = false

local function generate_opaque_predicate()
  local v = "_v" .. random_id(3)
  local method = random_int(1, 5)
  if method == 1 then
    return string.format("(function() local %s=%d; return (%s*%s+%s)%%2==0 end)()", v, random_int(1,1000), v, v, v)
  elseif method == 2 then
    return string.format("(function() local %s=%d; return %s*%s>=0 end)()", v, random_int(-1000,1000), v, v)
  elseif method == 3 then
    return string.format("(function() local %s=%d; return (%s+%s)%%2==0 end)()", v, random_int(1,500), v, v)
  elseif method == 4 then
    return string.format("(function() local %s=%d; return %s~=0 or true end)()", v, random_int(1,999), v)
  else
    return string.format("(function() local %s=%d; return not (%s<%s) end)()", v, random_int(1,100), v, v)
  end
end

local function generate_bcf_code()
  local fake_vars = {}
  local count = random_int(2, 5)
  for i = 1, count do
    fake_vars[i] = "_fv" .. random_id(4)
  end
  local lines = {}
  for _, var in ipairs(fake_vars) do
    local val = random_int(0, 0xFFFF)
    lines[#lines + 1] = string.format("local %s=0x%X", var, val)
  end
  for i = 1, random_int(1, 3) do
    local a = fake_vars[random_int(1, #fake_vars)]
    local b = fake_vars[random_int(1, #fake_vars)]
    local ops = { "+", "-", "~", "&", "|" }
    local op = ops[random_int(1, #ops)]
    lines[#lines + 1] = string.format("%s=%s%s%s", a, a, op, b)
  end
  return table.concat(lines, "\n    ")
end

-- Balance of brackets / strings on one line (rough completeness check)
local function is_balanced_line(s)
  local depth = 0
  local i, n = 1, #s
  local in_str, q = false, 0
  while i <= n do
    local b = s:byte(i)
    if in_str then
      if b == 92 then
        i = i + 2
      elseif b == q then
        in_str = false
        i = i + 1
      else
        i = i + 1
      end
    else
      if b == 34 or b == 39 then
        in_str = true
        q = b
        i = i + 1
      elseif b == 40 or b == 91 or b == 123 then
        depth = depth + 1
        i = i + 1
      elseif b == 41 or b == 93 or b == 125 then
        depth = depth - 1
        if depth < 0 then return false end
        i = i + 1
      else
        i = i + 1
      end
    end
  end
  return depth == 0 and not in_str
end

-- Only wrap complete single statements. Incomplete lines (multi-line
-- calls / anonymous functions / open parentheses) must not be wrapped.
local function is_safe_statement(trimmed)
  if trimmed == "" then return false end
  if trimmed:match("^%-%-") then return false end
  if trimmed:match("^end%s*$") then return false end
  if trimmed:match("^else") then return false end
  if trimmed:match("^elseif") then return false end
  if trimmed:match("^then%s*$") then return false end
  if trimmed:match("^do%s*$") then return false end
  if trimmed:match("^local%s+function") then return false end
  if trimmed:match("^function") then return false end
  if trimmed:match("^local%s") then return false end
  if trimmed:match("^return%s") or trimmed:match("^return$") then return false end
  if trimmed:match("^break%s*$") then return false end
  if trimmed:match("^if%s") then return false end
  if trimmed:match("^for%s") then return false end
  if trimmed:match("^while%s") then return false end
  if trimmed:match("^repeat%s*$") then return false end
  if trimmed:match("then%s*$") then return false end
  if trimmed:match("do%s*$") then return false end
  if trimmed:match("^goto%s") then return false end
  if trimmed:match("^::") then return false end
  -- never wrap lines that open a function expression / incomplete call
  if trimmed:find("function%s*%(", 1) and not trimmed:find("%f[%a]end%f[%A]") then
    return false
  end
  if not is_balanced_line(trimmed) then return false end
  -- trailing operators / open commas often mean multi-line expression
  if trimmed:match("[,%+%-%*%/%%%^%.&|~<>]=?%s*$") and not trimmed:match("%)%s*$") then
    return false
  end
  return true
end

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    local indent = line:match("^(%s*)") or ""

    if is_safe_statement(trimmed) and random_int(1, 4) == 1 then
      local predicate = generate_opaque_predicate()
      local fake_code = generate_bcf_code()
      -- Real branch first (always taken), fake branch never runs.
      result[#result + 1] = string.format("%sif %s then", indent, predicate)
      result[#result + 1] = string.format("%s  %s", indent, trimmed)
      result[#result + 1] = string.format("%selse", indent)
      result[#result + 1] = string.format("%s  %s", indent, fake_code)
      result[#result + 1] = string.format("%send", indent)
    else
      result[#result + 1] = line
    end
  end

  return join_lines(result)
end

return M