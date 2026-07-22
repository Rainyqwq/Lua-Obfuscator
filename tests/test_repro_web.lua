-- Reproduce intermittent bug with WEB default config (no VM)
-- Web defaults: var_mangle, num_encrypt, str_encrypt, cf_flatten, bcf, instr_sub, adv_fake, junk_comment = true
--                bb_split, vm_protect = false

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

-- Web default config
local function make_opts()
  return {
    variable_mangling = true,
    constant_encryption = true,
    string_encryption = true,
    control_flow_flattening = true,
    bogus_control_flow = true,
    basic_block_splitting = false,
    instruction_substitution = true,
    advanced_fake_cf = true,
    junk_comments = true,
    vm_protect = false,
  }
end

local N = 100
local fails = 0

for i = 1, N do
  local ok, result = pcall(Obfuscator.obfuscate_code, example, make_opts())
  if not ok then
    print(string.format("Run %d: OBFUSCATE ERROR: %s", i, tostring(result)))
    fails = fails + 1
  else
    -- Capture stdout
    local out = {}
    local old_print = print
    local function capture_print(...)
      local args = { ... }
      local t = {}
      for j = 1, select("#", ...) do t[j] = tostring(args[j]) end
      out[#out + 1] = table.concat(t, "\t")
    end
    _G.print = capture_print
    local exec_ok, exec_err = pcall(load(result))
    _G.print = old_print
    if not exec_ok then
      print(string.format("Run %d: EXEC ERROR: %s", i, tostring(exec_err)))
      fails = fails + 1
      if fails <= 3 then
        local f = io.open("_fail_web_" .. fails .. ".lua", "w")
        f:write(result)
        f:close()
      end
    else
      -- Check output correctness
      local output = table.concat(out, "\n")
      if not output:match("排序后: 1, 2, 3, 4, 5, 6, 7, 8") then
        print(string.format("Run %d: WRONG OUTPUT:\n%s", i, output))
        fails = fails + 1
        if fails <= 3 then
          local f = io.open("_fail_web_" .. fails .. ".lua", "w")
          f:write(result)
          f:close()
        end
      end
    end
  end
end

print(string.format("\n=== Results: %d/%d passed, %d failed ===", N - fails, N, fails))
