-- tests/test_vm_function.lua
-- Function-level VM pass test (--@vm annotation)
-- Run: lua tests/test_vm_function.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local o = require("obfuscator")

local function blank_opts()
  return {
    vm_protect = false,
    anti_debug = false,
    string_encryption = false,
    variable_mangling = false,
    instruction_substitution = false,
    constant_encryption = false,
    advanced_fake_cf = false,
    control_flow_flattening = false,
    bogus_control_flow = false,
    basic_block_splitting = false,
    junk_comments = false,
    call_indirection = false,
    vm_function = false,
  }
end

local function with_hang_guard(fn, max_ms)
  max_ms = max_ms or 15000
  local t0 = os.clock()
  if debug and debug.sethook then
    debug.sethook(function()
      if (os.clock() - t0) * 1000 > max_ms then
        error(string.format("hang-guard timeout >%dms", max_ms), 0)
      end
    end, "", 5000)
  end
  local ok, a, b = pcall(fn)
  if debug and debug.sethook then debug.sethook() end
  if not ok then return false, a end
  return true, a, b
end

local function capture_run(code)
  local out = {}
  local old = print
  print = function(...)
    local t = { ... }
    for i = 1, #t do t[i] = tostring(t[i]) end
    out[#out + 1] = table.concat(t, "\t")
  end
  local fn, err = load(code, "=capture")
  if not fn then
    print = old
    return false, "load: " .. tostring(err), out
  end
  local ok, e = pcall(fn)
  print = old
  if not ok then return false, "run: " .. tostring(e), out end
  return true, nil, out
end

local function golden(code)
  local ok, err, out = capture_run(code)
  assert(ok, "golden source failed: " .. tostring(err))
  return table.concat(out, "\n")
end

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

-- Test 1: single function with --@vm annotation
test("single function", function()
  local src = [[
--@vm
local function add(a, b)
  return a + b
end
print(add(3, 4))
]]
  local expected = golden(src)
  local opts = blank_opts()
  opts.vm_function = true
  local ok, result = with_hang_guard(function()
    return o.obfuscate_code(src, opts)
  end)
  assert(ok, "obfuscate failed: " .. tostring(result))
  local ok2, err2, out2 = capture_run(result)
  assert(ok2, "obfuscated run failed: " .. tostring(err2))
  local actual = table.concat(out2, "\n")
  assert(actual == expected, "output mismatch:\n  expected: " .. expected .. "\n  actual: " .. actual)
end)

-- Test 2: multiple functions, only annotated one gets VM
test("multiple functions selective", function()
  local src = [[
local function double(x)
  return x * 2
end
--@vm
local function square(x)
  return x * x
end
print(double(5), square(5))
]]
  local expected = golden(src)
  local opts = blank_opts()
  opts.vm_function = true
  local ok, result = with_hang_guard(function()
    return o.obfuscate_code(src, opts)
  end)
  assert(ok, "obfuscate failed: " .. tostring(result))
  local ok2, err2, out2 = capture_run(result)
  assert(ok2, "obfuscated run failed: " .. tostring(err2))
  local actual = table.concat(out2, "\n")
  assert(actual == expected, "output mismatch:\n  expected: " .. expected .. "\n  actual: " .. actual)
end)

-- Test 3: recursive function
test("recursive function", function()
  local src = [[
--@vm
local function factorial(n)
  if n <= 1 then return 1 end
  return n * factorial(n - 1)
end
print(factorial(5))
]]
  local expected = golden(src)
  local opts = blank_opts()
  opts.vm_function = true
  local ok, result = with_hang_guard(function()
    return o.obfuscate_code(src, opts)
  end)
  assert(ok, "obfuscate failed: " .. tostring(result))
  local ok2, err2, out2 = capture_run(result)
  assert(ok2, "obfuscated run failed: " .. tostring(err2))
  local actual = table.concat(out2, "\n")
  assert(actual == expected, "output mismatch:\n  expected: " .. expected .. "\n  actual: " .. actual)
end)

-- Test 4: no annotation = no VM applied
test("no annotation passthrough", function()
  local src = [[
local function plain(x)
  return x + 1
end
print(plain(10))
]]
  local opts = blank_opts()
  opts.vm_function = true
  local ok, result = with_hang_guard(function()
    return o.obfuscate_code(src, opts)
  end)
  assert(ok, "obfuscate failed: " .. tostring(result))
  -- Should not contain VM blob
  assert(not result:match("__vm_"), "VM blob found but no @vm annotation")
end)

-- Run tests
local passed, failed = 0, 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    passed = passed + 1
    print("  PASS: " .. t.name)
  else
    failed = failed + 1
    print("  FAIL: " .. t.name .. " - " .. tostring(err))
  end
end
print(string.format("\nResults: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
