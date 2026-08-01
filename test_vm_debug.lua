package.path = "./?.lua;./?/init.lua;" .. package.path

local vm = require("passes.vm")
local vm_code = vm.protect_as_expr("local function test(a, b) return a + b end")

print("VM code length:", #vm_code)

-- 检查是否有未闭合的字符串
local pos = 1
local in_str = false
local str_char = nil
while pos <= #vm_code do
  local c = vm_code:sub(pos, pos)
  if not in_str then
    if c == '"' or c == "'" then
      in_str = true
      str_char = c
    end
  else
    if c == "\\" then
      pos = pos + 2
    elseif c == str_char then
      in_str = false
    end
  end
  pos = pos + 1
end

print("Unclosed string:", in_str and "YES" or "NO")

-- 统计各种括号
local braces = {open = 0, close = 0}
local parens = {open = 0, close = 0}
local brackets = {open = 0, close = 0}

for i = 1, #vm_code do
  local c = vm_code:sub(i, i)
  if c == "{" then braces.open = braces.open + 1
  elseif c == "}" then braces.close = braces.close + 1
  elseif c == "(" then parens.open = parens.open + 1
  elseif c == ")" then parens.close = parens.close + 1
  elseif c == "[" then brackets.open = brackets.open + 1
  elseif c == "]" then brackets.close = brackets.close + 1
  end
end

print("Braces: { =", braces.open, ", } =", braces.close)
print("Parens: ( =", parens.open, ", ) =", parens.close)
print("Brackets: [ =", brackets.open, ", ] =", brackets.close)

-- 检查是否存在不平衡
if braces.open ~= braces.close then print("WARNING: Unbalanced braces!") end
if parens.open ~= parens.close then print("WARNING: Unbalanced parens!") end
if brackets.open ~= brackets.close then print("WARNING: Unbalanced brackets!") end
