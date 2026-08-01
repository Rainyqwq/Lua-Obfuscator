-- Run var_mangle.apply directly on the vm output, with a timeout.
local vm = require("passes.vm")
local var_mangle = require("passes.var_mangle")

local f = io.open("_vmout.lua", "r")
local vmout = f:read("*a"); f:close()
print("vmout length:", #vmout); io.flush()

print("calling var_mangle.apply ... (60s external timeout)"); io.flush()
local ctx = { config = { whitelist = {} } }
local t0 = os.clock()
local ok, result = pcall(var_mangle.apply, vmout, ctx)
local elapsed = os.clock() - t0
if ok then
  print("var_mangle OK in", string.format("%.2fs", elapsed), "result len", #result)
else
  print("var_mangle ERR in", string.format("%.2fs", elapsed), ":", tostring(result):sub(1,200))
end
