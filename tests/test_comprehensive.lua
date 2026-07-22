-- tests/test_comprehensive.lua
-- 全面测试：覆盖所有 Lua 特性，验证混淆后代码功能正确性
--
-- 测试策略：
--   1. 单 Pass 测试：每个 Pass 单独启用，验证输出可执行
--   2. 累积 Pass 测试：逐步叠加 Pass，验证组合效果
--   3. 全 Pass 测试：所有 Pass 同时启用
--   4. 每轮验证：语法检查 + 执行结果比对

local M = require("obfuscator")

-- ============================================================
-- 测试用例：覆盖所有 Lua 特性
-- ============================================================

local TEST_CASES = {
  -- 1. 基础类型和字面量
  {
    name = "基础类型",
    code = [=[
local a = nil
local b = true
local c = false
local d = 42
local e = 3.14
local f = -1
local g = 0xFF
local h = 255
local i = 1e10
local j = 1.5e-3
local k = "hello"
local l = 'world'
assert(a == nil)
assert(b == true)
assert(c == false)
assert(d == 42)
assert(e == 3.14)
assert(f == -1)
assert(g == 255)
assert(h == 255)
assert(i == 1e10)
assert(j == 1.5e-3)
assert(k == "hello")
assert(l == "world")
print("基础类型: OK")
]=],
  },

  -- 2. 算术运算
  {
    name = "算术运算",
    code = [=[
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
]=],
  },

  -- 3. 比较和逻辑
  {
    name = "比较逻辑",
    code = [=[
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
print("比较逻辑: OK")
]=],
  },

  -- 4. 字符串操作
  {
    name = "字符串操作",
    code = [=[
assert(#"hello" == 5)
assert("hello" .. " " .. "world" == "hello world")
assert(string.len("abc") == 3)
assert(string.sub("hello", 2, 4) == "ell")
assert(string.rep("ab", 3) == "ababab")
assert(string.reverse("abc") == "cba")
assert(string.upper("hello") == "HELLO")
assert(string.lower("HELLO") == "hello")
assert(string.byte("A") == 65)
assert(string.char(65) == "A")
assert(string.find("hello world", "world") == 7)
assert(string.format("%s=%d", "x", 42) == "x=42")
print("字符串: OK")
]=],
  },

  -- 5. 表操作
  {
    name = "表操作",
    code = [=[
local arr = {10, 20, 30}
assert(#arr == 3)
assert(arr[1] == 10)
assert(arr[3] == 30)
local tbl = {name="test", value=42}
assert(tbl.name == "test")
assert(tbl["value"] == 42)
table.insert(arr, 40)
assert(#arr == 4)
assert(arr[4] == 40)
assert(table.remove(arr, 4) == 40)
table.sort(arr, function(a, b) return a > b end)
assert(arr[1] == 30)
assert(arr[3] == 10)
assert(table.concat(arr, ",") == "30,20,10")
print("表: OK")
]=],
  },

  -- 6. 控制流
  {
    name = "控制流",
    code = [=[
local x = 2
local r
if x == 1 then r = "one"
elseif x == 2 then r = "two"
elseif x == 3 then r = "three"
else r = "other"
end
assert(r == "two")
local sum = 0
for i = 1, 100 do sum = sum + i end
assert(sum == 5050)
sum = 0
local i = 1
while i <= 10 do
  sum = sum + i
  i = i + 1
end
assert(sum == 55)
print("控制流: OK")
]=],
  },

  -- 7. 函数
  {
    name = "函数",
    code = [=[
local function add(a, b) return a + b end
assert(add(3, 4) == 7)
local function swap(a, b) return b, a end
local x, y = swap(1, 2)
assert(x == 2 and y == 1)
local function fact(n)
  if n <= 1 then return 1 end
  return n * fact(n - 1)
end
assert(fact(5) == 120)
local function apply(fn, x) return fn(x) end
assert(apply(function(x) return x * 2 end, 5) == 10)
print("函数: OK")
]=],
  },

  -- 8. 闭包
  {
    name = "闭包",
    code = [=[
local function counter()
  local n = 0
  return function() n = n + 1; return n end
end
local c = counter()
assert(c() == 1)
assert(c() == 2)
assert(c() == 3)
local function make_pair()
  local shared = 0
  local function inc() shared = shared + 1; return shared end
  local function get() return shared end
  return inc, get
end
local inc, get = make_pair()
assert(get() == 0)
assert(inc() == 1)
assert(inc() == 2)
assert(get() == 2)
print("闭包: OK")
]=],
  },

  -- 9. 可变参数
  {
    name = "可变参数",
    code = [=[
local function count_args(...)
  return select("#", ...)
end
assert(count_args(1, 2, 3) == 3)
assert(count_args() == 0)
local function sum(...)
  local args = {...}
  local s = 0
  for _, v in ipairs(args) do s = s + v end
  return s
end
assert(sum(1, 2, 3, 4) == 10)
assert(sum() == 0)
print("可变参数: OK")
]=],
  },

  -- 10. 元表
  {
    name = "元表",
    code = [=[
local proto = { greet = "hello" }
local obj = setmetatable({}, { __index = proto })
assert(obj.greet == "hello")
local log = {}
local mt = {
  __newindex = function(t, k, v)
    rawset(t, k, v)
    log[#log + 1] = k .. "=" .. tostring(v)
  end
}
local t = setmetatable({}, mt)
t.x = 1
t.y = 2
assert(#log == 2)
assert(log[1] == "x=1")
local box = setmetatable({val=42}, {
  __tostring = function(self) return "Box(" .. self.val .. ")" end
})
assert(tostring(box) == "Box(42)")
print("元表: OK")
]=],
  },

  -- 11. 面向对象
  {
    name = "面向对象",
    code = [=[
local Animal = {}
Animal.__index = Animal
function Animal.new(name, sound)
  return setmetatable({name=name, sound=sound}, Animal)
end
function Animal:speak()
  return self.name .. " says " .. self.sound
end
local a = Animal.new("Cat", "Meow")
assert(a:speak() == "Cat says Meow")
local Dog = setmetatable({}, { __index = Animal })
Dog.__index = Dog
function Dog.new(name)
  local self = Animal.new(name, "Woof")
  setmetatable(self, Dog)
  return self
end
local d = Dog.new("Rex")
assert(d:speak() == "Rex says Woof")
print("OOP: OK")
]=],
  },

  -- 12. 协程
  {
    name = "协程",
    code = [=[
local co = coroutine.create(function()
  coroutine.yield(1)
  coroutine.yield(2)
  return 3
end)
assert(coroutine.resume(co))
local ok, val = coroutine.resume(co)
assert(ok and val == 2)
ok, val = coroutine.resume(co)
assert(ok and val == 3)
assert(coroutine.status(co) == "dead")
print("协程: OK")
]=],
  },

  -- 13. 模式匹配
  {
    name = "模式匹配",
    code = [=[
assert(("hello123"):match("%a+") == "hello")
assert(("hello123"):match("%d+") == "123")
local year, month, day = ("2025-07-22"):match("(%d+)-(%d+)-(%d+)")
assert(year == "2025" and month == "07" and day == "22")
print("模式匹配: OK")
]=],
  },

  -- 14. 错误处理
  {
    name = "错误处理",
    code = [=[
local ok, err = pcall(function() error("test error") end)
assert(not ok)
assert(err:find("test error"))
assert(pcall(function() return 42 end))
local ok2, err2 = pcall(function() assert(false, "assert msg") end)
assert(not ok2)
assert(err2:find("assert msg"))
print("错误处理: OK")
]=],
  },

  -- 15. 数学库
  {
    name = "数学库",
    code = [=[
assert(math.abs(-5) == 5)
assert(math.max(1, 2, 3) == 3)
assert(math.min(1, 2, 3) == 1)
assert(math.floor(3.7) == 3)
assert(math.ceil(3.2) == 4)
assert(math.sqrt(9) == 3)
assert(math.sin(0) == 0)
assert(math.cos(0) == 1)
assert(math.pi > 3.14 and math.pi < 3.15)
print("数学: OK")
]=],
  },

  -- 16. goto
  {
    name = "goto",
    code = [=[
local done = false
::retry::
if not done then
  done = true
  goto retry
end
assert(done)
print("goto: OK")
]=],
  },

  -- 17. 链式调用
  {
    name = "链式调用",
    code = [=[
local function f(x) return function(y) return x + y end end
assert(f(3)(4) == 7)
local Builder = {}
Builder.__index = Builder
function Builder.new() return setmetatable({parts={}}, Builder) end
function Builder:add(s) self.parts[#self.parts+1] = s; return self end
function Builder:build() return table.concat(self.parts) end
local r = Builder.new():add("hello"):add(" "):add("world"):build()
assert(r == "hello world")
print("链式调用: OK")
]=],
  },

  -- 18. 闭包深度
  {
    name = "闭包深度",
    code = [=[
local function make_chain(n)
  local fns = {}
  for i = 1, n do
    fns[i] = function() return i end
  end
  return fns
end
local chain = make_chain(5)
for i = 1, 5 do assert(chain[i]() == i) end
local events = {}
local function on(name, fn) events[name] = fn end
on("click", function(x, y) return x + y end)
assert(events.click(3, 4) == 7)
print("闭包深度: OK")
]=],
  },

  -- 19. select
  {
    name = "select",
    code = [=[
local function count(...)
  return select("#", ...)
end
assert(count(1, 2, 3) == 3)
assert(count() == 0)
local function get_nth(n, ...)
  return select(n, ...)
end
assert(get_nth(2, "a", "b", "c") == "b")
print("select: OK")
]=],
  },

  -- 20. 特殊字符
  {
    name = "特殊字符",
    code = [=[
local s = "abc\0def"
assert(#s == 7)
assert(s:byte(4) == 0)
assert(tonumber("42") == 42)
assert(tonumber("3.14") == 3.14)
assert(tonumber("0xFF") == 255)
print("特殊字符: OK")
]=],
  },
}

-- ============================================================
-- Pass 配置
-- ============================================================

local ALL_PASSES = {
  "string_encryption",
  "variable_mangling",
  "instruction_substitution",
  "constant_encryption",
  "control_flow_flattening",
  "junk_comments",
}

local function make_config(overrides)
  local cfg = {
    vm_protect = false,
    string_encryption = false,
    variable_mangling = false,
    instruction_substitution = false,
    constant_encryption = false,
    advanced_fake_cf = false,
    control_flow_flattening = false,
    bogus_control_flow = false,
    basic_block_splitting = false,
    junk_comments = false,
  }
  if overrides then
    for k, v in pairs(overrides) do cfg[k] = v end
  end
  return cfg
end

local function run_test(code, config)
  M.set_config(config)
  local ok, result = pcall(M.obfuscate_code, code)
  if not ok then return false, "混淆失败: " .. tostring(result) end

  local fn, err = load(result)
  if not fn then return false, "语法错误: " .. tostring(err) end

  local run_ok, run_err = pcall(fn)
  if not run_ok then return false, "运行错误: " .. tostring(run_err) end

  return true, #result
end

-- ============================================================
-- 执行测试
-- ============================================================

local total = 0
local pass = 0
local fail = 0
local fail_details = {}

-- 合并所有测试代码
local all_code_parts = {}
for _, tc in ipairs(TEST_CASES) do
  all_code_parts[#all_code_parts + 1] = tc.code
end
local all_code = table.concat(all_code_parts, "\n")

print(string.format("╔══════════════════════════════════════════════╗"))
print(string.format("║  全面混淆测试                                ║"))
print(string.format("║  测试用例: %d 个 Lua 特性模块              ║", #TEST_CASES))
print(string.format("║  Pass 数量: %d 个                           ║", #ALL_PASSES))
print(string.format("╚══════════════════════════════════════════════╝"))
print()

-- 阶段1：单 Pass 测试
print("━━━ 阶段1: 单 Pass 测试 ━━━")
for _, pass_name in ipairs(ALL_PASSES) do
  local cfg = make_config({ [pass_name] = true })
  local ok, info = run_test(all_code, cfg)
  total = total + 1
  if ok then
    pass = pass + 1
    print(string.format("  ✅ %s (%d bytes)", pass_name, info))
  else
    fail = fail + 1
    fail_details[#fail_details + 1] = { name = pass_name, err = info }
    print(string.format("  ❌ %s: %s", pass_name, info:sub(1, 60)))
  end
end
print()

-- 阶段2：累积 Pass 测试
print("━━━ 阶段2: 累积 Pass 测试 ━━━")
local cumulative_cfg = make_config()
local cumulative_names = {}
for _, pass_name in ipairs(ALL_PASSES) do
  cumulative_cfg[pass_name] = true
  cumulative_names[#cumulative_names + 1] = pass_name
  local ok, info = run_test(all_code, cumulative_cfg)
  total = total + 1
  if ok then
    pass = pass + 1
    print(string.format("  ✅ [%d] %s", info, pass_name))
  else
    fail = fail + 1
    fail_details[#fail_details + 1] = { name = pass_name, err = info }
    print(string.format("  ❌ +%s: %s", pass_name, info:sub(1, 60)))
    cumulative_cfg[pass_name] = false
  end
end
print()

-- 阶段3：全 Pass 多轮稳定性测试
print("━━━ 阶段3: 全 Pass 稳定性测试 ━━━")
local full_cfg = make_config()
for _, p in ipairs(ALL_PASSES) do full_cfg[p] = true end
local stability_rounds = 30
local stability_fail = 0
for i = 1, stability_rounds do
  local ok, info = run_test(all_code, full_cfg)
  total = total + 1
  if ok then
    pass = pass + 1
  else
    fail = fail + 1
    stability_fail = stability_fail + 1
    if stability_fail <= 3 then
      print(string.format("  ❌ round %d: %s", i, info:sub(1, 60)))
    end
  end
end
if stability_fail == 0 then
  print(string.format("  ✅ %d 轮全部通过", stability_rounds))
else
  print(string.format("  ❌ %d/%d 轮失败", stability_fail, stability_rounds))
end
print()

-- 阶段4：性能基准
print("━━━ 阶段4: 性能基准 ━━━")
run_test(all_code, full_cfg)  -- 预热
local bench_rounds = 20
local t0 = os.clock()
local last_size = 0
for i = 1, bench_rounds do
  local ok, info = run_test(all_code, full_cfg)
  if ok then last_size = info end
end
local elapsed = os.clock() - t0
print(string.format("  %d 轮: %.1fms (平均 %.1fms/轮)", bench_rounds, elapsed * 1000, elapsed / bench_rounds * 1000))
print(string.format("  输入: %d bytes → 输出: %d bytes (%.1fx)", #all_code, last_size, last_size / #all_code))
print(string.format("  吞吐量: %.0f KB/sec", #all_code * bench_rounds / elapsed / 1024))
print()

-- ============================================================
-- 汇总
-- ============================================================
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(string.format("  总计: %d | 通过: %d | 失败: %d", total, pass, fail))

if fail > 0 then
  print()
  print("  失败详情:")
  for _, d in ipairs(fail_details) do
    print(string.format("    ❌ %s: %s", d.name, d.err:sub(1, 60)))
  end
  print()
  os.exit(1)
else
  print("  🎉 全部通过!")
  print()
  os.exit(0)
end
