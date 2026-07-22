-- ================================================================
-- tests/test_anti_debug.lua
-- 反调试功能测试
-- ================================================================

local tests = {
  {
    name = "基本反调试检测",
    code = [[
function hello()
  print("hello")
end
hello()
]],
    expected_behavior = "生成包含 os.clock/debug.gethook 检测的代码",
  },
  {
    name = "无函数代码",
    code = [[print("hello")]],
    expected_behavior = "不生成检测代码（无函数可检测）",
  },
}

local passed = 0
local failed = 0

print("━━━ 反调试测试 ━━━")

for _, test in ipairs(tests) do
  local ok, result = pcall(function()
    -- 加载 obfuscator
    package.path = "./?.lua;" .. package.path
    local pm = require("pass_manager").new()
    require("passes").load_all(pm)

    -- 启用反调试
    local anti_debug = pm:get("anti_debug")
    if anti_debug then
      anti_debug.enabled = true
    end

    -- 运行
    local output = pm:run(test.code, {})

    -- 验证输出包含检测代码
    if output:match("debug%.gethook") or output:match("os%.clock") then
      return "PASS"
    else
      return "FAIL: 缺少检测代码"
    end
  end)

  if ok and result == "PASS" then
    print("  ✅ " .. test.name)
    passed = passed + 1
  else
    print("  ❌ " .. test.name .. (result and ": " .. tostring(result) or ""))
    failed = failed + 1
  end
end

print("")
print("结果: " .. passed .. "/" .. (passed + failed) .. " 通过")
if failed > 0 then os.exit(1) end
