-- ================================================================
-- passes/bcf.lua
-- BCF 虚假控制流
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 基于不透明谓词 (Opaque Predicate) 注入永远不会执行的代码分支
-- 不透明谓词：在编译期就能确定真假的条件表达式，但逆向时难以判断
--
-- 示例：
--   原始: do_something()
--   混淆: if (x*x+x)%2 == 0 then   ← 永远为真（但逆向不知道）
--           do_something()
--         else
--           <垃圾代码>
--         end

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines

local M = {}

M.name    = "bogus_control_flow"
M.title   = "BCF虚假控制流"
M.version = "1.0.0"
M.order   = 80
M.enabled = false  -- 默认禁用，由 Config 控制；修复了 then/else 分支交换 bug

-- 生成不透明谓词（永远为真的条件表达式）
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

-- 生成虚假代码块（看起来有意义但不会执行）
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

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}
  local depth = 0

  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    local indent = line:match("^(%s*)") or ""

    -- 在可执行语句前注入 BCF（跳过空行、注释、控制流语句）
    if trimmed ~= "" and
       not trimmed:match("^%-%-") and
       not trimmed:match("^end%s*$") and
       not trimmed:match("^else") and
       not trimmed:match("^elseif") and
       not trimmed:match("^then%s*$") and
       not trimmed:match("^do%s*$") and
      not trimmed:match("^local%s+function") and
      not trimmed:match("^function") and
       not trimmed:match("^local%s") and
      not trimmed:match("^return%s") and
       not trimmed:match("^return$") and
       not trimmed:match("^break%s*$") and
       -- 跳过控制流语句（if/for/while/repeat 开头或以 then/do 结尾）
       not trimmed:match("^if%s") and
       not trimmed:match("^for%s") and
       not trimmed:match("^while%s") and
       not trimmed:match("^repeat%s*$") and
       not trimmed:match("then%s*$") and
       not trimmed:match("do%s*$") and
       random_int(1, 4) == 1 then

     local predicate = generate_opaque_predicate()
     local fake_code = generate_bcf_code()
     result[#result + 1] = string.format("%sif %s then", indent, predicate)
     result[#result + 1] = string.format("    %s", trimmed)
      result[#result + 1] = string.format("%selse", indent)
      result[#result + 1] = string.format("    %s", fake_code)
     result[#result + 1] = string.format("%send", indent)
    else
      result[#result + 1] = line
    end
  end

  return join_lines(result)
end

return M
