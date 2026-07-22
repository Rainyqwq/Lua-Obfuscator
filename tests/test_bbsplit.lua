-- ================================================================
-- tests/test_bbsplit.lua
-- 基本块拆分 (Basic Block Splitting) 单元测试
-- ================================================================

local PassManager = require("pass_manager")
local passes = require("passes")

local pm = PassManager.new()
passes.load_all(pm)

-- 禁用所有 Pass，只启用 bb_split
for name, _ in pairs(pm._registry) do
  pm:set_enabled(name, false)
end
pm:set_enabled("basic_block_splitting", true)

local test_code = [[
function compute(a, b)
  local r = a + b
  print(r)
  r = r * 2
  print(r)
  return r
end

function greet(name)
  print("Hello, " .. name)
  print("Welcome!")
end

compute(3, 4)
greet("World")
]]

print("=== Original ===")
print(test_code)
print("\n=== Obfuscated (bb_split only) ===")
local ok, result = pcall(pm.run, pm, test_code)
if not ok then
  print("ERROR: " .. tostring(result))
  os.exit(1)
end
print(result)

print("\n=== Compile check ===")
local fn, err = load(result)
if not fn then
  print("COMPILE FAILED: " .. tostring(err))
  os.exit(1)
end
print("Compile OK")

print("\n=== Execute check ===")
local exec_ok, exec_err = pcall(fn)
if not exec_ok then
  print("EXEC FAILED: " .. tostring(exec_err))
  os.exit(1)
end
print("Execute OK")

print("\n=== All tests passed ===")
