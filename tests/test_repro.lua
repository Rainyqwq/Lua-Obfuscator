-- Reproduce intermittent "attempt to compare number with nil" bug
-- Runs obfuscation N times with default config (no VM) and executes output

local Obfuscator = require("obfuscator")

local example = [=[
local function quicksort(arr, low, high)
  if low < high then
    local pivot = arr[high]
    local i = low - 1
    for j = low, high - 1 do
      if arr[j] <= pivot then
        i = i + 1
        arr[i], arr[j] = arr[j], arr[i]
      end
    end
    arr[i + 1], arr[high] = arr[high], arr[i + 1]
    local pi = i + 1
    quicksort(arr, low, pi - 1)
    quicksort(arr, pi + 1, high)
  end
end

local data = {5, 3, 8, 4, 2, 7, 1, 6}
print("排序前: " .. table.concat(data, ", "))
quicksort(data, 1, #data)
print("排序后: " .. table.concat(data, ", "))

local function fib(n)
  if n <= 1 then return n end
  return fib(n - 1) + fib(n - 2)
end
print("fib(10) = " .. fib(10))
]=]

local N = 50
local fails = 0
local fail_outputs = {}

for i = 1, N do
  local ok, result = pcall(Obfuscator.obfuscate_code, example)
  if not ok then
    print(string.format("Run %d: OBFUSCATE ERROR: %s", i, tostring(result)))
    fails = fails + 1
  else
    -- Execute the obfuscated code
    local exec_ok, exec_err = pcall(load(result))
    if not exec_ok then
      print(string.format("Run %d: EXEC ERROR: %s", i, tostring(exec_err)))
      fails = fails + 1
      if #fail_outputs < 3 then
        fail_outputs[#fail_outputs + 1] = { run = i, code = result, err = tostring(exec_err) }
      end
    end
  end
end

print(string.format("\n=== Results: %d/%d passed, %d failed ===", N - fails, N, fails))

-- Save first failing output for analysis
if #fail_outputs > 0 then
  local f = io.open("_fail_output.lua", "w")
  f:write(fail_outputs[1].code)
  f:close()
  print("\nFirst failing output saved to _fail_output.lua")
  print("Error: " .. fail_outputs[1].err)
end
if #fail_outputs > 1 then
  local f = io.open("_fail_output2.lua", "w")
  f:write(fail_outputs[2].code)
  f:close()
  print("\nSecond failing output saved to _fail_output2.lua")
end
