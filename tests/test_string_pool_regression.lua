-- Minimal regression: string_pool hash must never throw integer representation errors
package.path = "./?.lua;./?/init.lua;" .. package.path
local sp = require("passes.string_pool")

local samples = {
  "",
  "a",
  "Hello World",
  "排序前",
  string.rep("x", 200),
  "\0\1\2\255",
  "print(\"hi\")",
  "fib(10) = ",
}

for _, s in ipairs(samples) do
  local ok, err = pcall(function()
    local code = 'print("' .. s:gsub('"', '\\"') .. '")'
    local extracted = sp.extract(code)
    local restored = sp.restore(extracted)
    assert(type(restored) == "string")
  end)
  if not ok then
    io.stderr:write("FAIL sample=[" .. tostring(s):sub(1,40) .. "]: " .. tostring(err) .. "\n")
    os.exit(1)
  end
end

-- direct hash path
local code2 = sp.extract('local s = "算法示例：快速排序" print(s)')
local out = sp.restore(code2)
assert(out:find("function") or out:find("string.char") or #out > 0)
print("string_pool regression OK")
