-- Bisect: test each suspect pass to find the intermittent bug culprit
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
quicksort(data, 1, #data)
print("排序后: " .. table.concat(data, ", "))
local function fib(n)
  if n <= 1 then return n end
  return fib(n - 1) + fib(n - 2)
end
print("fib(10) = " .. fib(10))
]=]

local function merge(...)
  local r = {}
  for _, t in ipairs({ ... }) do for k, v in pairs(t) do r[k] = v end end
  return r
end

local function run_test(label, opts, N)
  N = N or 30
  local fails = 0
  for i = 1, N do
    local ok, result = pcall(Obfuscator.obfuscate_code, example, opts)
    if not ok then
      fails = fails + 1
    else
      local out = {}
      local old_print = print
      _G.print = function(...) local t = { ... } local s = {} for j = 1, select("#", ...) do s[j] = tostring(t[j]) end out[#out + 1] = table.concat(s, "\t") end
      local exec_ok = pcall(load(result))
      _G.print = old_print
      if not exec_ok then
        fails = fails + 1
      else
        local output = table.concat(out, "\n")
        if not output:match("排序后: 1, 2, 3, 4, 5, 6, 7, 8") then
          fails = fails + 1
        end
      end
    end
  end
  print(string.format("%-45s %d/%d passed, %d failed", label, N - fails, N, fails))
  return fails
end

local base = {
  variable_mangling = true, constant_encryption = true, string_encryption = true,
  advanced_fake_cf = true, junk_comments = true,
  control_flow_flattening = false, bogus_control_flow = false,
  instruction_substitution = false, basic_block_splitting = false, vm_protect = false,
}

run_test("base (CLI defaults)", base)
run_test("base + cf_flatten", merge(base, { control_flow_flattening = true }))
run_test("base + bcf", merge(base, { bogus_control_flow = true }))
run_test("base + instr_sub", merge(base, { instruction_substitution = true }))
run_test("base + cf_flatten + bcf", merge(base, { control_flow_flattening = true, bogus_control_flow = true }))
run_test("base + cf_flatten + instr_sub", merge(base, { control_flow_flattening = true, instruction_substitution = true }))
run_test("full web config", merge(base, { control_flow_flattening = true, bogus_control_flow = true, instruction_substitution = true }))
