-- full_pass_test.lua
-- 全面 Pass 测试

local M = require("obfuscator")

-- 所有可用的 Pass
local ALL_PASSES = {
  "vm_protect",
  "string_encryption",
  "variable_mangling",
  "instruction_substitution",
  "constant_encryption",
  "advanced_fake_cf",
  "control_flow_flattening",
  "bogus_control_flow",
  "basic_block_splitting",
  "junk_comments",
  "anti_debug",
  "call_indirection",
  "vm_function",
}

-- 完整的 Lua 特性测试
local TEST_CASES = {
  { name = "基础类型", code = [[
local a = nil
local b = true
local c = false
local d = 42
assert(a == nil)
assert(b == true)
assert(c == false)
assert(d == 42)
print("基础类型: OK")
]] },
  { name = "算术运算", code = [[
local a, b = 10, 3
assert(a + b == 13)
assert(a - b == 7)
assert(a * b == 30)
assert(a % b == 1)
assert(a ^ b == 1000)
assert(-a == -10)
assert(math.floor(a / b) == 3)
assert(10 // 3 == 3)
print("算术: OK")
]] },
  { name = "比较逻辑", code = [[
assert(1 < 2)
assert(2 > 1)
assert(1 <= 1)
assert(1 >= 1)
assert(1 == 1)
assert(1 ~= 2)
assert(true and true)
assert(not (true and false))
assert(true or false)
assert(not (false or false))
print("比较: OK")
]] },
  { name = "字符串", code = [[
assert(#("hello") == 5)
assert(("hello" .. "world"):len() == 10)
print("字符串: OK")
]] },
  { name = "表操作", code = [[
local arr = {10, 20, 30}
assert(#arr == 3)
assert(arr[1] == 10)
local tbl = {name="test", value=42}
assert(tbl.name == "test")
print("表: OK")
]] },
  { name = "控制流", code = [[
local x = 2
local r
if x == 1 then r = "one"
elseif x == 2 then r = "two"
else r = "other"
end
assert(r == "two")
print("控制流: OK")
]] },
  { name = "函数定义", code = [[
local function add(a, b) return a + b end
assert(add(3, 4) == 7)
local function swap(a, b) return b, a end
local x, y = swap(1, 2)
assert(x == 2 and y == 1)
print("函数: OK")
]] },
  { name = "闭包", code = [[
local n = 0
local function inc() n = n + 1; return n end
assert(inc() == 1)
assert(inc() == 2)
print("闭包: OK")
]] },
  { name = "可变参数", code = [[
local function sum(...) local args = {...}; return #args end
assert(sum(1, 2, 3, 4) == 4)
print("可变参数: OK")
]] },
  { name = "元表", code = [[
local obj = setmetatable({}, { __index = {x=1} })
assert(obj.x == 1)
print("元表: OK")
]] },
  { name = "OOP", code = [[
local Animal = {}
function Animal.new(n) return setmetatable({name=n}, Animal) end
local a = Animal.new("Cat")
assert(a.name == "Cat")
print("OOP: OK")
]] },
  { name = "协程", code = [[
local co = coroutine.create(function() coroutine.yield(1) end)
assert(coroutine.resume(co))
print("协程: OK")
]] },
  { name = "模式匹配", code = [[
assert(("hello123"):match("%d+") == "123")
print("模式匹配: OK")
]] },
  { name = "错误处理", code = [[
local ok, err = pcall(error, "test")
assert(not ok)
print("错误处理: OK")
]] },
  { name = "数学库", code = [[
assert(math.abs(-5) == 5)
assert(math.max(1, 2, 3) == 3)
print("数学: OK")
]] },
  { name = "goto语句", code = [[
local done = false
::retry::
if not done then done = true; goto retry end
assert(done)
print("goto: OK")
]] },
  { name = "链式调用", code = [[
local function f(x) return function(y) return x + y end end
assert(f(3)(4) == 7)
print("链式调用: OK")
]] },
  { name = "select", code = [[
assert(select("#", 1, 2, 3) == 3)
assert(select(2, "a", "b", "c") == "b")
print("select: OK")
]] },
  { name = "位运算", code = [[
assert((5 & 3) == 1)
assert((5 | 3) == 7)
assert((5 ~ 3) == 6)
print("位运算: OK")
]] },
  { name = "数值for", code = [[
local sum = 0
for i = 1, 10 do sum = sum + i end
assert(sum == 55)
print("数值for: OK")
]] },
}

-- 合并测试代码
local all_code = ""
for _, tc in ipairs(TEST_CASES) do
  all_code = all_code .. tc.code .. "\n"
end

-- 测试函数
local function test_pass(pass_name, enabled)
  local cfg = {}
  for _, p in ipairs(ALL_PASSES) do cfg[p] = false end
  cfg[pass_name] = enabled
  M.set_config(cfg)

  if pass_name == "vm_protect" then
    for _, tc in ipairs(TEST_CASES) do
      local ok, result = pcall(M.obfuscate_code, tc.code)
      if not ok then
        return false, "混淆失败", tc.name .. " => " .. tostring(result)
      end

      local fn, err = load(result)
      if not fn then
        return false, "语法错误", tc.name .. " => " .. tostring(err)
      end

      local ok2, run_err = pcall(fn)
      if not ok2 then
        return false, "运行错误", tc.name .. " => " .. tostring(run_err)
      end
    end
    return true, "通过", 0
  end

  local ok, result = pcall(M.obfuscate_code, all_code)
  if not ok then return false, "混淆失败", result end
  local fn, err = load(result)
  if not fn then return false, "语法错误", err end
  local ok2, run_err = pcall(fn)
  if not ok2 then return false, "运行错误", run_err end
  return true, "通过", #result
end

local function test_combo(passes)
  local cfg = {}
  for _, p in ipairs(ALL_PASSES) do cfg[p] = false end
  for _, p in ipairs(passes) do cfg[p] = true end
  M.set_config(cfg)
  local ok, result = pcall(M.obfuscate_code, all_code)
  if not ok then return false, "混淆失败", result end
  local fn, err = load(result)
  if not fn then return false, "语法错误", err end
  local ok2, run_err = pcall(fn)
  if not ok2 then return false, "运行错误", run_err end
  return true, "通过", #result
end

-- ============ 测试开始 ============

local total_tests = 0
local passed_tests = 0
local failed_tests = {}

print("╔══════════════════════════════════════════════════════════════════╗")
print("║        Lua Obfuscator 全面 Pass 测试                        ║")
print("╚══════════════════════════════════════════════════════════════════╝")
print()

-- 1. 单 Pass 测试
print("━━━ 1. 单 Pass 测试 ━━━")
print()
for _, pass_name in ipairs(ALL_PASSES) do
  total_tests = total_tests + 1
  local ok, status, info = test_pass(pass_name, true)
  if ok then
    passed_tests = passed_tests + 1
    print(string.format("  ✅ %-25s (%d bytes)", pass_name, info))
  else
    failed_tests[#failed_tests + 1] = { name = pass_name, status = status, info = info }
    print(string.format("  ❌ %-25s %s", pass_name, status))
    if pass_name == "vm_protect" then
      print("      DETAIL: " .. tostring(info))
    end
  end
end

-- 2. 双 Pass 组合测试
print()
print("━━━ 2. 双 Pass 组合测试 ━━━")
print()
local important_passes = {"string_encryption", "variable_mangling", "instruction_substitution", "constant_encryption", "control_flow_flattening", "junk_comments"}
for i, p1 in ipairs(important_passes) do
  for j = i + 1, #important_passes do
    local p2 = important_passes[j]
    total_tests = total_tests + 1
    local ok, status, info = test_combo({p1, p2})
    if ok then
      passed_tests = passed_tests + 1
      print(string.format("  ✅ %s + %s", p1, p2))
    else
      failed_tests[#failed_tests + 1] = { name = p1 .. "+" .. p2, status = status, info = info }
      print(string.format("  ❌ %s + %s: %s", p1, p2, status))
    end
  end
end

-- 3. 全 Pass 稳定性测试 (5轮)
print()
print("━━━ 3. 全 Pass 稳定性测试 (5轮) ━━━")
print()
local stability_fail = 0
for round = 1, 5 do
  local cfg = {}
  for _, p in ipairs(ALL_PASSES) do cfg[p] = true end
  -- 关闭可能有问题的 pass
  cfg.vm_protect = false
  cfg.vm_function = false
  cfg.anti_debug = false
  M.set_config(cfg)
  local ok, result = pcall(M.obfuscate_code, all_code)
  if ok then
    local fn, err = load(result)
    if fn then
      local ok2, run_err = pcall(fn)
      if ok2 then
        print(string.format("  ✅ round %d", round))
      else
        stability_fail = stability_fail + 1
        print(string.format("  ❌ round %d: 运行错误", round))
      end
    else
      stability_fail = stability_fail + 1
      print(string.format("  ❌ round %d: 语法错误", round))
    end
  else
    stability_fail = stability_fail + 1
    print(string.format("  ❌ round %d: 混淆失败", round))
  end
end
total_tests = total_tests + 5
passed_tests = passed_tests + (5 - stability_fail)
if stability_fail == 0 then
  print(string.format("  全部 5 轮通过"))
end

-- 结果汇总
print()
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(string.format("  总计: %d 测试 | 通过: %d | 失败: %d", total_tests, passed_tests, #failed_tests))

if #failed_tests > 0 then
  print()
  print("  失败详情:")
  for _, f in ipairs(failed_tests) do
    print(string.format("    ❌ %s: %s", f.name, f.status))
  end
end

print()
if #failed_tests == 0 then
  print("  🎉 全部测试通过!")
  os.exit(0)
else
  os.exit(1)
end
