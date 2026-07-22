  -- Decode prototype from data (recursive for nested sub-protos)
  local function decode_proto(di)
    local np = _d[di]; di = di + 1
    local ms = _d[di]; di = di + 1
    local nk = _d[di]; di = di + 1
    local nc = _d[di]; di = di + 1
    local consts = {}
    for _ = 1, nk do
      local t = _d[di]; di = di + 1
      if t == 1 then  -- number
        local sl = _d[di]; di = di + 1
        local s = ""
        for _ = 1, sl do s = s .. string.char(_d[di]); di = di + 1 end
        consts[#consts + 1] = tonumber(s)
      elseif t == 2 then  -- string
        local sl = _d[di]; di = di + 1
        local s = ""
        for _ = 1, sl do s = s .. string.char(_d[di]); di = di + 1 end
        consts[#consts + 1] = s
      elseif t == 3 then  -- boolean
        consts[#consts + 1] = _d[di] == 1; di = di + 1
      elseif t == 4 then  -- sub-proto (recursive)
        local sub, new_di = decode_proto(di)
        consts[#consts + 1] = sub
        di = new_di
      end
    end
    di = di + 1  -- skip end-of-constants marker (0)
    local code = {}
    for _ = 1, nc do
      code[#code + 1] = { op = _d[di], a = _d[di+1], b = _d[di+2], c = _d[di+3] }
      di = di + 4
    end
    return { code = code, constants = consts, numparams = np, maxstack = ms }, di
  end

  -- VM execution
  local function exec_proto(proto, regs, base, nargs, upvals)
    local code = proto.code
    local consts = proto.constants
    local pc = 1

    while pc <= #code do
      local ins = code[pc]
      local op, A, B, C = ins.op, ins.a, ins.b, ins.c
      pc = pc + 1

      if op == OP_NOP then
      elseif op == OP_LOADK then
        regs[base + A] = consts[B]
      elseif op == OP_LOADBOOL then
        regs[base + A] = B ~= 0
        if C ~= 0 then pc = pc + 1 end
      elseif op == OP_LOADNIL then
        for i = 0, B do regs[base + A + i] = nil end
      elseif op == OP_MOVE then
        regs[base + A] = regs[base + B]
      elseif op == OP_GETGLOBAL then
        local key = consts[B]
        regs[base + A] = _G[key]
      elseif op == OP_SETGLOBAL then
        _G[consts[B]] = regs[base + A]
      elseif op == OP_GETTABLE then
        local t = regs[base + B]
        local k = regs[base + C]
        if type(t) == "table" then
          regs[base + A] = t[k]
        else
          regs[base + A] = nil
        end
      elseif op == OP_SETTABLE then
        local t = regs[base + A]
        local k = regs[base + B]
        local v = regs[base + C]
        if type(t) == "table" then t[k] = v end
      elseif op == OP_NEWTABLE then
        regs[base + A] = {}
      elseif op == OP_ADD then
        local l, r = regs[base + B], regs[base + C]
        regs[base + A] = (type(l) == "number" and type(r) == "number") and (l + r) or (tonumber(l) or 0) + (tonumber(r) or 0)
      elseif op == OP_SUB then
        local l, r = regs[base + B], regs[base + C]
        regs[base + A] = l - r
      elseif op == OP_MUL then
        local l, r = regs[base + B], regs[base + C]
        regs[base + A] = l * r
      elseif op == OP_DIV then
        local l, r = regs[base + B], regs[base + C]
        regs[base + A] = l / r
      elseif op == OP_MOD then
        local l, r = regs[base + B], regs[base + C]
        regs[base + A] = l %% r
      elseif op == OP_POW then
        regs[base + A] = regs[base + B] ^ regs[base + C]
      elseif op == OP_BAND then
        regs[base + A] = regs[base + B] & regs[base + C]
      elseif op == OP_BOR then
        regs[base + A] = regs[base + B] | regs[base + C]
      elseif op == OP_BXOR then
        regs[base + A] = regs[base + B] ~ regs[base + C]
      elseif op == OP_SHL then
        regs[base + A] = regs[base + B] << regs[base + C]
      elseif op == OP_SHR then
        regs[base + A] = regs[base + B] >> regs[base + C]
      elseif op == OP_UNM then
        regs[base + A] = -regs[base + B]
      elseif op == OP_BNOT then
        regs[base + A] = ~regs[base + B]
      elseif op == OP_NOT then
        regs[base + A] = not regs[base + B]
      elseif op == OP_LEN then
        regs[base + A] = #regs[base + B]
      elseif op == OP_CONCAT then
        local s = tostring(regs[base + B])
        for j = B + 1, C do s = s .. tostring(regs[base + j]) end
        regs[base + A] = s
      elseif op == OP_EQ then
        local l, r = regs[base + B], regs[base + C]
        local eq = (l == r)
        if (eq and A == 0) or (not eq and A ~= 0) then
          pc = pc + 1
        end
      elseif op == OP_LT then
        local l, r = regs[base + B], regs[base + C]
        local lt = (l < r)
        if (lt and A == 0) or (not lt and A ~= 0) then
          pc = pc + 1
        end
      elseif op == OP_LE then
        local l, r = regs[base + B], regs[base + C]
        local le = (l <= r)
        if (le and A == 0) or (not le and A ~= 0) then
          pc = pc + 1
        end
      elseif op == OP_JMP then
        -- B is sBx (signed offset)
        local sBx = B
        if sBx > 32767 then sBx = sBx - 65536 end
        pc = pc + sBx
      elseif op == OP_TEST then
        local v = regs[base + A]
        local truthy = v and v ~= nil and v ~= false
        if (truthy and C == 0) or (not truthy and C ~= 0) then
          pc = pc + 1
        end
      elseif op == OP_TESTSET then
        local v = regs[base + B]
        local truthy = v and v ~= nil and v ~= false
        if (truthy and C == 0) or (not truthy and C ~= 0) then
          pc = pc + 1
        else
          regs[base + A] = v
        end
      elseif op == OP_CALL then
        local fn = regs[base + A]
        if type(fn) == "function" then
          local args = {}
          for j = 1, B - 1 do args[j] = regs[base + A + j] end
          local results = {fn(table.unpack(args))}
          if C > 0 then
            for j = 1, C - 1 do
              regs[base + A + j - 1] = results[j]
            end
          else
            regs[base + A] = results[1]
          end
        end
      elseif op == OP_TAILCALL then
        local fn = regs[base + A]
        if type(fn) == "function" then
          local args = {}
          for j = 1, B - 1 do args[j] = regs[base + A + j] end
          return fn(table.unpack(args))
        end
      elseif op == OP_RETURN then
        if B >= 2 then
          local results = {}
          for j = 0, B - 2 do results[j + 1] = regs[base + A + j] end
          return table.unpack(results)
        elseif B == 1 then
          return regs[base + A]
        else
          return
        end
      elseif op == OP_CLOSURE then
        local sub_proto = consts[B]
        if type(sub_proto) == "table" and sub_proto.code then
          regs[base + A] = function(...)
            local sub_regs = {}
            local args = {...}
            for ai = 1, sub_proto.numparams do
              sub_regs[ai - 1] = args[ai]
            end
            return exec_proto(sub_proto, sub_regs, 0, select("#", ...), nil)
          end
        end
      elseif op == OP_VARARG then
        -- Simplified: varargs not fully supported
        if B > 0 then
          for j = 0, B - 1 do regs[base + A + j] = nil end
        end
      elseif op == OP_EXTRAARG then
        -- Extra argument, skip
      end
    end
  end

  -- Decode and run
  local main_proto = decode_proto(1)
  local regs = {}
  exec_proto(main_proto, regs, 0, 0, nil)

end
