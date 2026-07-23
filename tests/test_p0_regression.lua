-- tests/test_p0_regression.lua
-- P0: single-pass + combo + semantic golden + hang guard
-- Run: lua tests/test_p0_regression.lua  (from repo root with package.path)

package.path = "./?.lua;./?/init.lua;" .. package.path

local o = require("obfuscator")

local PASS_NAMES = {
  "string_encryption",
  "variable_mangling",
  "instruction_substitution",
  "constant_encryption",
  "advanced_fake_cf",
  "control_flow_flattening",
  "bogus_control_flow",
  "basic_block_splitting",
  "junk_comments",
  "call_indirection",
  -- anti_debug / vm_protect intentionally optional (side effects / heavy)
}

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

local FIXTURES = {
  {
    name = "fib",
    code = [[
local function fibonacci(n)
  if n <= 1 then return n end
  local a, b = 0, 1
  for i = 2, n do
    local t = a + b
    a = b
    b = t
  end
  return b
end
for i = 0, 9 do
  print("fib(" .. i .. ")=" .. fibonacci(i))
end
]],
  },
  {
    name = "tables_and_keys",
    -- triggers var_mangle collect_table_keys paths
    code = [[
local KEYWORDS = { ["and"]=true, ["or"]=true, foo=1 }
local t = { a = 1, b = 2, c = { x = 3 } }
local s = 0
for k, v in pairs({n=10, m=20}) do
  if type(v) == "number" then s = s + v end
end
print(t.a + t.b + t.c.x)
print(s)
print(KEYWORDS.foo)
]],
  },
  {
    name = "closures_concat",
    code = [[
local function make(x)
  return function(y) return x + y end
end
print(make(10)(32))
print(("a" .. "b") .. "c")
local arr = {3,1,2}
table.sort(arr)
print(table.concat(arr, ","))
]],
  },
  {
    name = "numeric_for_steps",
    code = [[
local t = {"a","b","c"}
local o = {}
for i = #t, 1, -1 do o[#o+1] = t[i] end
print(table.concat(o))
local s = 0
for i = 1, 5 do s = s + i end
print(s)
]],
  },
}

local total, pass, fail = 0, 0, 0
local failures = {}

local function record(ok, label, detail)
  total = total + 1
  if ok then
    pass = pass + 1
    io.write("  OK  ", label, "\n")
  else
    fail = fail + 1
    failures[#failures + 1] = label .. ": " .. tostring(detail)
    io.write("  FAIL ", label, " :: ", tostring(detail):sub(1, 120), "\n")
  end
  io.stdout:flush()
end

print("=== P0 regression ===")
print("fixtures:", #FIXTURES, "passes:", #PASS_NAMES)

-- 1) single pass x fixtures (no hang, loadable, semantic match)
for _, fx in ipairs(FIXTURES) do
  local g = golden(fx.code)
  for _, pn in ipairs(PASS_NAMES) do
    local opts = blank_opts()
    opts[pn] = true
    local label = string.format("single/%s/%s", fx.name, pn)
    local ok, res = with_hang_guard(function()
      return o.obfuscate_code(fx.code, opts)
    end, 20000)
    if not ok then
      record(false, label, res)
    else
      local rok, rerr, out = capture_run(res)
      if not rok then
        record(false, label, rerr)
      else
        local got = table.concat(out, "\n")
        record(got == g, label, got ~= g and ("semantic mismatch got=[" .. got:sub(1,80) .. "]") or nil)
      end
    end
  end
end

-- 2) all default-like (no vm / no anti_debug)
do
  local opts = blank_opts()
  for _, pn in ipairs(PASS_NAMES) do opts[pn] = true end
  for _, fx in ipairs(FIXTURES) do
    local g = golden(fx.code)
    local label = "combo/all_text/" .. fx.name
    local ok, res = with_hang_guard(function()
      return o.obfuscate_code(fx.code, opts)
    end, 60000)
    if not ok then
      record(false, label, res)
    else
      local rok, rerr, out = capture_run(res)
      if not rok then
        record(false, label, rerr)
      else
        local got = table.concat(out, "\n")
        record(got == g, label, got ~= g and ("semantic mismatch") or nil)
      end
    end
  end
end

-- 3) stress file: real instr_sub.lua if present (obfuscate only + hang guard)
do
  local path = "passes/instr_sub.lua"
  local f = io.open(path, "rb")
  if f then
    local code = f:read("*a")
    f:close()
    if code:sub(1,3) == string.char(0xEF,0xBB,0xBF) then code = code:sub(4) end
    local opts = blank_opts()
    for _, pn in ipairs(PASS_NAMES) do opts[pn] = true end
    local label = "stress/instr_sub.lua/all_text"
    local t0 = os.clock()
    local ok, res = with_hang_guard(function()
      return o.obfuscate_code(code, opts)
    end, 60000)
    local ms = (os.clock() - t0) * 1000
    -- P0: must finish without hang; self-obfuscated pass source need not load-clean
    if not ok then
      record(false, label, res)
    else
      record(type(res) == "string" and #res > 0,
        label .. string.format(" (%.0fms, %d bytes)", ms, #res),
        "empty output")
    end
  else
    print("  skip stress/instr_sub.lua (not found)")
  end
end

-- 4) vm alone on small fixture (optional, should finish)
do
  local fx = FIXTURES[1]
  local g = golden(fx.code)
  local opts = blank_opts()
  opts.vm_protect = true
  local label = "single/fib/vm_protect"
  local ok, res = with_hang_guard(function()
    return o.obfuscate_code(fx.code, opts)
  end, 30000)
  if not ok then
    record(false, label, res)
  else
    local rok, rerr, out = capture_run(res)
    if not rok then
      record(false, label, rerr)
    else
      record(table.concat(out, "\n") == g, label, rerr)
    end
  end
end

print(string.format("=== result: %d total, %d pass, %d fail ===", total, pass, fail))
if fail > 0 then
  print("failures:")
  for _, e in ipairs(failures) do print(" -", e:sub(1, 160)) end
  os.exit(1)
end
print("P0 regression OK")
os.exit(0)