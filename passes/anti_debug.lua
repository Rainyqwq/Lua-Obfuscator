-- passes/anti_debug.lua
-- Anti-debugging detection pass

local M = {}

M.name = "anti_debug"
M.title = "Anti-Debug Detection"
M.version = "1.0.0"
M.order = 15
M.enabled = false

function M.apply(code, _ctx)
  local checks = {}

  -- Check debug hook
  if math.random() < 0.9 then
    checks[#checks + 1] = "(function()local h,m=debug.gethook()if h then return true end;local i=debug.getinfo(1)if not i then return true end;return false end)()"
  end

  -- Check timing anomaly
  if math.random() < 0.8 then
    checks[#checks + 1] = "(function()local s=os.clock()local sum=0;for i=1,100 do sum=sum+i end;if os.clock()-s>0.1 then return true end;return false end)()"
  end

  -- Check JIT status
  if math.random() < 0.7 then
    checks[#checks + 1] = "(function()if not jit then return false end;local st=jit.status;if st and not st()then return true end;return false end)()"
  end

  if #checks == 0 then
    return code
  end

  local block = "if " .. table.concat(checks, " or ") .. " then error('debugger detected') end"

  -- Find insertion point
  local ins = string.match(code, "^%s*(function%s+[%w_]+)")
  if not ins then
    ins = string.match(code, "^%s*(local%s+[%w_]+%s*=%s*function)")
  end
  if not ins then
    ins = string.match(code, "^%s*(local%s+[%w_]+)")
  end

  if ins then
    local pos = string.find(code, ins, 1, true)
    if pos then
      code = string.sub(code, 1, pos - 1) .. block .. "\n" .. string.sub(code, pos)
    end
  else
    code = block .. "\n" .. code
  end

  return code
end

return M
