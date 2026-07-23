package.path = "./?.lua;./?/init.lua;" .. package.path
local Obfuscator = require("obfuscator")
local src = [[
print("Hello World")
print("排序前: 1, 2, 3")
local function fib(n)
  if n <= 1 then return n end
  return fib(n-1)+fib(n-2)
end
print("fib(10) = " .. fib(10))
]]
local opts = {
  variable_mangling = true,
  constant_encryption = true,
  string_encryption = true,
  control_flow_flattening = false,
  bogus_control_flow = false,
  basic_block_splitting = true,
  instruction_substitution = true,
  advanced_fake_cf = true,
  junk_comments = true,
  vm_protect = false,
  anti_debug = false,
  call_indirect = false,
}
for i = 1, 20 do
  local ok, result = pcall(Obfuscator.obfuscate_code, src, opts)
  if not ok then
    io.stderr:write("fail run " .. i .. ": " .. tostring(result) .. "\n")
    os.exit(1)
  end
  local eok, err = pcall(function()
    local f = assert(load(result))
    local old = print
    print = function() end
    f()
    print = old
  end)
  if not eok then
    io.stderr:write("exec fail run " .. i .. ": " .. tostring(err) .. "\n")
    local f = io.open("_fail_sp.lua", "w"); f:write(result); f:close()
    os.exit(1)
  end
end
print("20x obfuscate+exec OK")
