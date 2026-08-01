-- Isolate: run vm_protect, save its output, then run var_mangle on it with
-- progress instrumentation to find the infinite loop.

local M = require("obfuscator")
local utils = require("passes.utils")
local vm = require("passes.vm")

local SAMPLE = [=[
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
]=]

-- Produce vm_protect output directly
print("vm.protect ..."); io.flush()
local vmout = assert(vm.protect(SAMPLE))
print("vm output length:", #vmout)
io.flush()

-- Write it out for inspection
local f = io.open("_vmout.lua", "w"); f:write(vmout); f:close()
print("wrote _vmout.lua")

-- Now load var_mangle module fresh and call its internal pieces.
-- var_mangle doesn't expose internals, so we require it and instrument by
-- copying the apply logic with prints. Instead, simplest: call M.apply via
-- the pass manager with only these two passes, but add a step counter by
-- monkey-patching scan_identifiers? Can't reach locals.
--
-- Instead: just run var_mangle on vmout with a hard timeout via alarm.
print("running var_mangle on vm output (10s alarm)...")
io.flush()

-- Lua 5.5 has no alarm. We'll rely on external timeout. But we want to know
-- WHERE it loops. Let's grep vmout for the markers var_mangle cares about.
print("\n-- @vm (protected) markers in vm output:", (select(2, vmout:gsub("-- @vm %(protected%)", ""))))
print("-- @ markers in vm output:", (select(2, vmout:gsub("\n-- @", ""))))
print("__VM_BLOCK placeholders:", (select(2, vmout:gsub("__VM_BLOCK_%d+__", ""))))
print("__ST string placeholders:", (select(2, vmout:gsub("__ST", ""))))

-- Check: does vmout contain a line that starts with "-- @" anywhere?
for line in vmout:gmatch("[^\n]*") do
  if line:match("^%s*%-%- @") then
    print("  found --@ line:", line:sub(1,80))
  end
end
