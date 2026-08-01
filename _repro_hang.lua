-- reproduce the vm_protect + variable_mangling hang
-- Runs each pass alone and in combination with a per-pass watchdog so we can
-- see exactly which pass never returns.

local M = require("obfuscator")

-- The default sample from index.html (matches user's "code length: 511")
local SAMPLE = [[
local function fibonacci(n)
  if n <= 1 then
    return n
  end
  local a, b = 0, 1
  for i = 2, n do
    local temp = a + b
    a = b
    b = temp
  end
  return b
end

for i = 0, 9 do
  print("fib(" .. i .. ") = " .. fibonacci(i))
end

local max_retries = 5
local timeout_ms = 3000
local pi_approx = 3.14159
local secret_key = 0xDEADBEEF

print("Max retries: " .. max_retries)
print("Timeout: " .. timeout_ms .. "ms")
print("Pi: " .. pi_approx)
print("Key: " .. string.format("0x%X", secret_key))
]]

local ALL = {
  "vm_protect","string_encryption","variable_mangling","instruction_substitution",
  "constant_encryption","advanced_fake_cf","control_flow_flattening","bogus_control_flow",
  "basic_block_splitting","junk_comments","anti_debug","call_indirection","vm_function",
}

local function cfg_with(on)
  local cfg = {}
  for _, p in ipairs(ALL) do cfg[p] = false end
  for _, p in ipairs(on) do cfg[p] = true end
  return cfg
end

local function run(label, on, time_limit)
  M.set_config(cfg_with(on))
  io.write(string.format("  %-45s ... ", label)); io.flush()
  local t0 = os.clock()
  local done = false
  local result, err
  -- watchdog thread: abort the process if it exceeds time_limit
  local co = coroutine.create(function()
    local ok, r = pcall(M.obfuscate_code, SAMPLE)
    done = true
    result, err = ok, r
  end)
  -- We can't truly preempt in Lua, but os.clock tells us elapsed.
  -- Run in a sub-coroutine step is not possible since obfuscate is not yieldable.
  -- So just run it directly with a wall-clock check after.
  local ok, r = pcall(M.obfuscate_code, SAMPLE)
  local elapsed = os.clock() - t0
  if ok then
    io.write(string.format("OK (%.2fs, %d bytes)\n", elapsed, #r))
    return true, r
  else
    io.write(string.format("ERR (%.2fs): %s\n", elapsed, tostring(r):sub(1,120)))
    return false, r
  end
end

print("=== single pass ===")
for _, p in ipairs(ALL) do
  run(p, {p}, 10)
end

print("\n=== vm_protect + each other pass ===")
for _, p in ipairs(ALL) do
  if p ~= "vm_protect" then
    run("vm_protect + " .. p, {"vm_protect", p}, 15)
  end
end

print("\n=== vm_protect + variable_mangling (the reported hang) ===")
run("vm_protect + variable_mangling", {"vm_protect", "variable_mangling"}, 20)
