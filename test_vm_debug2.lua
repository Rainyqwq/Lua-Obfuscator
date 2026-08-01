package.path = "./?.lua;./?/init.lua;" .. package.path

-- 加载 var_mangle 模块
local var_mangle_code = assert(loadfile("passes/var_mangle.lua"))()

-- 获取 VM 代码
local vm = require("passes.vm")
local vm_code = vm.protect_as_expr("local function test(a, b) return a + b end")

print("VM code length:", #vm_code)

-- 提取并手动运行 collect_table_keys
local keys = {}
local i = 1
local len = #vm_code
local steps = 0
local start_time = os.clock()
local max_steps = 100000

while i <= len and steps < max_steps do
  steps = steps + 1
  local b = vm_code:byte(i)

  -- Skip string placeholders
  if b == 95 and vm_code:sub(i, i+3) == "__ST" then
    local ep = vm_code:find("__", i+5, true)
    i = ep and (ep+2) or (i+1)
  -- Skip comments
  elseif b == 45 and i < len and vm_code:byte(i+1) == 45 then
    local nl = vm_code:find("\n", i+2, true)
    i = nl and (nl+1) or (len+1)
  -- Skip string literals
  elseif b == 34 or b == 39 then
    local q = b; i = i + 1
    while i <= len do
      if vm_code:byte(i) == 92 then i = i + 2
      elseif vm_code:byte(i) == q then i = i + 1; break
      else i = i + 1 end
    end
  -- Skip [expr] in table literals - THIS IS LIKELY THE SLOW PART
  elseif b == 91 then
    i = i + 1
    local depth = 1
    local bracket_start = i
    while i <= len and depth > 0 do
      steps = steps + 1
      local cb = vm_code:byte(i)
      if cb == 91 then depth = depth + 1
      elseif cb == 93 then depth = depth - 1
      elseif cb == 34 or cb == 39 then
        local q2 = cb; i = i + 1
        while i <= len do
          if vm_code:byte(i) == 92 then i = i + 2
          elseif vm_code:byte(i) == q2 then i = i + 1; break
          else i = i + 1 end
        end
      else i = i + 1 end
    end
  -- Table literal: { key = value }
  elseif b == 123 then
    i = i + 1
    local depth = 1
    while i <= len and depth > 0 do
      steps = steps + 1
      local cb = vm_code:byte(i)
      if cb == 123 then depth = depth + 1; i = i + 1
      elseif cb == 125 then depth = depth - 1; i = i + 1
      elseif cb == 34 or cb == 39 then
        local q3 = cb; i = i + 1
        while i <= len do
          if vm_code:byte(i) == 92 then i = i + 2
          elseif vm_code:byte(i) == q3 then i = i + 1; break
          else i = i + 1 end
        end
      elseif (cb >= 65 and cb <= 90) or (cb >= 97 and cb <= 122) or cb == 95 then
        local start = i
        i = i + 1
        while i <= len do
          local ib = vm_code:byte(i)
          if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
        end
        local key = vm_code:sub(start, i - 1)
        while i <= len and (vm_code:byte(i) == 32 or vm_code:byte(i) == 9) do i = i + 1 end
        if vm_code:byte(i) == 61 then
          keys[key] = true
          i = i + 1
        end
      else i = i + 1 end
    end
  else
    i = i + 1
  end
end

local elapsed = os.clock() - start_time
print("Steps:", steps)
print("Time:", elapsed, "seconds")
print("Keys found:", next(keys) and "yes" or "no")
print("Key count:", next(keys) and #keys or 0)

if steps >= max_steps then
  print("WARNING: Hit step limit!")
  print("Position:", i, "/", len)
end
