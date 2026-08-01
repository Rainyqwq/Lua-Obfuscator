package.path = "./?.lua;./?/init.lua;" .. package.path

local vm = require("passes.vm")
local vm_code = vm.protect_as_expr("local function test(a, b) return a + b end")

print("VM code length:", #vm_code)

-- 逐步测试每个部分

-- 1. 测试跳过字符串字面量
print("1. Testing string literal skip...")
local pos = 1
local len = #vm_code
local str_count = 0
local start = os.clock()
while pos <= len do
  local b = vm_code:byte(pos)
  if b == 34 or b == 39 then
    local q = b
    pos = pos + 1
    while pos <= len do
      local cb = vm_code:byte(pos)
      if cb == 92 then
        pos = pos + 2
      elseif cb == q then
        pos = pos + 1
        str_count = str_count + 1
        break
      else
        pos = pos + 1
      end
    end
  else
    pos = pos + 1
  end
  if str_count >= 5 then break end
end
print("   Done:", os.clock() - start, "seconds, strings:", str_count)

-- 2. 测试跳过 [expr] 数组
print("2. Testing bracket skip for large arrays...")
pos = 1
start = os.clock()
local bracket_count = 0
local iterations = 0
while pos <= len and iterations < 100000 do
  iterations = iterations + 1
  local b = vm_code:byte(pos)
  if b == 91 then
    bracket_count = bracket_count + 1
    pos = pos + 1
    local depth = 1
    while pos <= len and depth > 0 do
      iterations = iterations + 1
      local cb = vm_code:byte(pos)
      if cb == 91 then
        depth = depth + 1
        pos = pos + 1
      elseif cb == 93 then
        depth = depth - 1
        pos = pos + 1
      elseif cb == 34 or cb == 39 then
        local q2 = cb
        pos = pos + 1
        while pos <= len do
          if vm_code:byte(pos) == 92 then
            pos = pos + 2
          elseif vm_code:byte(pos) == q2 then
            pos = pos + 1
            break
          else
            pos = pos + 1
          end
        end
      else
        pos = pos + 1
      end
    end
  else
    pos = pos + 1
  end
end
print("   Done:", os.clock() - start, "seconds, brackets:", bracket_count, "iterations:", iterations)
if iterations >= 100000 then
  print("   WARNING: Hit iteration limit!")
end
