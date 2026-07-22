-- 测试闭包upvalue支持
local x = 0
local function inc()
  x = x + 1
end

inc()
inc()
inc()
print("x should be 3, got: " .. x)

-- 测试多层闭包
local function make_counter(start)
  local count = start
  return function()
    count = count + 1
    return count
  end
end

local counter = make_counter(10)
print("counter: " .. counter())  -- 11
print("counter: " .. counter())  -- 12
print("counter: " .. counter())  -- 13

-- 测试闭包捕获多个upvalue
local a, b = 100, 200
local function get_sum()
  return a + b
end
print("sum: " .. get_sum())  -- 300

-- 测试修改upvalue
local function make_adder(n)
  return function(x)
    return n + x
  end
end

local add5 = make_adder(5)
print("5+3=" .. add5(3))  -- 8
print("5+10=" .. add5(10))  -- 15
