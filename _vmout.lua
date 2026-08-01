-- @vm (protected)
-- VM Protected Code (op-pool + char-pool)
do
  local _d = {2564489,2564507,2564481,2564496,2564493,2564488,2564504,2564490,2564503,2564488,2564488,2564484,2564488,2564488,2564509,2564488,2564488,2564505,2564489,2564521,2564488,2564489,2564489,2564486,2564491,2564488,2564489,2564522,2564489,2564488,2564491,2564497,2564489,2564491,2564489,2564521,2564491,2564489,2564489,2564513,2564491,2564491,2564489,2564486,2564492,2564491,2564489,2564521,2564490,2564492,2564489,2564486,2564492,2564488,2564489,2564521,2564493,2564492,2564489,2564486,2564492,2564490,2564489,2564521,2564495,2564489,2564489,2564486,2564494,2564488,2564489,2564521,2564481,2564492,2564489,2564521,2564480,2564495,2564489,2564521,2564483,2564494,2564489,2564501,2564481,2564483,2564489,2564521,2564484,2564490,2564489,2564521,2564487,2564493,2564489,2564488,2564484,2564484,2564487,2564521,2564485,2564484,2564489,2564521,2564484,2564493,2564489,2564521,2564487,2564484,2564489,2564521,2564490,2564487,2564489,2564521,2564487,2564485,2564489,2564521,2564486,2564487,2564489,2564521,2564493,2564486,2564489,2564515,2564481,4292402812,2564489,2564521,2564486,2564493,2564489,2564513,2564486,2564491,2564489,2564489,2564489,2564491,2564480,2564506,2564497,2564511,2564495,2564507,2564480,2564499,2564499,2564497,2564488,2564488,2564509,2564488,2564488,2564485,2564488,2564488,2564484,2564491,2564492,2564486,2564481,2564497,2564507,2564496,2564491,2564493,2564506,2564497,2564511,2564487,2564491,2564493,2564508,2564491,2564490,2564491,2564489,2564484,2564489,2564488,2564489,2564527,2564489,2564491,2564489,2564486,2564488,2564490,2564489,2564486,2564491,2564493,2564489,2564486,2564490,2564492,2564489,2564521,2564493,2564488,2564489,2564521,2564492,2564491,2564489,2564521,2564495,2564490,2564489,2564501,2564493,2564487,2564489,2564481,2564481,2564495,2564489,2564486,2564480,2564494,2564489,2564521,2564483,2564494,2564489,2564486,2564482,2564481,2564489,2564481,2564485,2564491,2564489,2564521,2564484,2564494,2564489,2564490,2564485,2564491,2564491,2564521,2564487,2564480,2564489,2564521,2564486,2564483,2564489,2564521,2564505,2564482,2564489,2564521,2564504,2564485,2564489,2564519,2564487,2564487,2564504,2564521,2564480,2564487,2564489,2564490,2564481,2564491,2564491,2564515,2564493,4292402808,2564489,2564513,2564489,2564488,2564489,2564489}
  local _chars = {27,240,237,133,54,191,151,162,177,9,62,233,225,248,160,226,58,190,182,224,249,178,169,185,164,179}
  local _k = 2564489
  local _ck = 208
  local _cs_seed = 7011
  local _cs_expect = 49116

  for _i = 1, #_d do _d[_i] = _d[_i] ~ _k end

  local function _dec_str(di, len)
    local t = {}
    for i = 1, len do
      local idx = _d[di]; di = di + 1
      t[i] = string.char((_chars[idx] or 0) ~ _ck)
    end
    return table.concat(t), di
  end

  local OP_NOP = 39
  local OP_LOADK = 15
  local OP_LOADBOOL = 9
  local OP_LOADNIL = 33
  local OP_MOVE = 32
  local OP_GETGLOBAL = 8
  local OP_SETGLOBAL = 38
  local OP_GETUPVAL = 20
  local OP_SETUPVAL = 11
  local OP_GETTABLE = 21
  local OP_SETTABLE = 18
  local OP_NEWTABLE = 19
  local OP_ADD = 1
  local OP_SUB = 17
  local OP_MUL = 23
  local OP_DIV = 16
  local OP_IDIV = 30
  local OP_MOD = 0
  local OP_POW = 27
  local OP_BAND = 34
  local OP_BOR = 29
  local OP_BXOR = 5
  local OP_SHL = 12
  local OP_SHR = 10
  local OP_UNM = 4
  local OP_BNOT = 25
  local OP_NOT = 14
  local OP_LEN = 37
  local OP_CONCAT = 46
  local OP_EQ = 43
  local OP_LT = 45
  local OP_LE = 35
  local OP_JMP = 24
  local OP_TEST = 31
  local OP_TESTSET = 41
  local OP_CALL = 3
  local OP_TAILCALL = 6
  local OP_RETURN = 40
  local OP_FORPREP = 28
  local OP_FORLOOP = 42
  local OP_TFORPREP = 2
  local OP_TFORCALL = 26
  local OP_TFORLOOP = 36
  local OP_CLOSURE = 13
  local OP_VARARG = 7
  local OP_EXTRARG = 22
  local OP_SETLIST = 44

  local function decode_proto(di)
    local np = _d[di]; di = di + 1
    local ms = _d[di]; di = di + 1
    local nk = _d[di]; di = di + 1
    local nc = _d[di]; di = di + 1
    local consts = {}
    for _ci = 1, nk do
      local t = _d[di]; di = di + 1
      if t == 0 then break end
      if t == 1 then
        local sl = _d[di]; di = di + 1
        local s; s, di = _dec_str(di, sl)
        consts[#consts + 1] = tonumber(s)
      elseif t == 2 then
        local sl = _d[di]; di = di + 1
        local s; s, di = _dec_str(di, sl)
        consts[#consts + 1] = s
      elseif t == 3 then
        consts[#consts + 1] = _d[di] == 1; di = di + 1
      elseif t == 4 then
        local sub, new_di = decode_proto(di)
        consts[#consts + 1] = sub
        di = new_di + 1
      end
    end
    di = di + 1
    local code = {}
    for _ = 1, nc do
      code[#code + 1] = { op = _d[di], a = _d[di+1], b = _d[di+2], c = _d[di+3] }
      di = di + 4
    end
    local nuv = _d[di]; di = di + 1
    local upvalues = {}
    for _ = 1, nuv do
      local uv_reg = _d[di]; di = di + 1
      local name_len = _d[di]; di = di + 1
      local nm; nm, di = _dec_str(di, name_len)
      upvalues[#upvalues + 1] = { reg = uv_reg, name = nm }
    end
    return { code = code, constants = consts, numparams = np, maxstack = ms, upvalues = upvalues }, di
  end

  local _orig_pack = _G._pack

  local function exec_proto(proto, regs, base, nargs, upvals, varargs)
    _G._pack = function()
      local t = {}
      if varargs then for i = 1, #varargs do t[i] = varargs[i] end end
      return t
    end
    local code = proto.code
    local consts = proto.constants
    local pc = 1
    local A, B, C

    local H = {}

    H[OP_NOP] = function() end
    H[OP_LOADK] = function()
      regs[base + A] = consts[B]
    end
    H[OP_LOADBOOL] = function()
      regs[base + A] = B ~= 0
      if C ~= 0 then pc = pc + 1 end
    end
    H[OP_LOADNIL] = function()
      for i = 0, B do regs[base + A + i] = nil end
    end
    H[OP_MOVE] = function()
      regs[base + A] = regs[base + B]
    end
    H[OP_GETGLOBAL] = function()
      regs[base + A] = _G[consts[B]]
    end
    H[OP_SETGLOBAL] = function()
      _G[consts[B]] = regs[base + A]
    end
    H[OP_GETUPVAL] = function()
      if upvals and upvals[B + 1] then
        local uv = upvals[B + 1]
        regs[base + A] = uv[1][uv[2]]
      end
    end
    H[OP_SETUPVAL] = function()
      if upvals and upvals[B + 1] then
        local uv = upvals[B + 1]
        uv[1][uv[2]] = regs[base + A]
      end
    end
    H[OP_GETTABLE] = function()
      local t = regs[base + B]
      local k = regs[base + C]
      if type(t) == "table" then
        regs[base + A] = t[k]
      elseif type(t) == "string" and type(k) == "string" then
        regs[base + A] = string[k]
      elseif getmetatable(t) then
        local mt = getmetatable(t)
        if mt.__index then
          if type(mt.__index) == "function" then
            regs[base + A] = mt.__index(t, k)
          else
            regs[base + A] = mt.__index[k]
          end
        else
          regs[base + A] = nil
        end
      else
        regs[base + A] = nil
      end
    end
    H[OP_SETTABLE] = function()
      local t = regs[base + A]
      if type(t) == "table" then t[regs[base + B]] = regs[base + C] end
    end
    H[OP_NEWTABLE] = function()
      regs[base + A] = {}
    end
    H[OP_ADD] = function()
      local l, r = regs[base + B], regs[base + C]
      regs[base + A] = (type(l) == "number" and type(r) == "number") and (l + r) or (tonumber(l) or 0) + (tonumber(r) or 0)
    end
    H[OP_SUB] = function()
      regs[base + A] = regs[base + B] - regs[base + C]
    end
    H[OP_MUL] = function()
      regs[base + A] = regs[base + B] * regs[base + C]
    end
    H[OP_DIV] = function()
      regs[base + A] = regs[base + B] / regs[base + C]
    end
    H[OP_IDIV] = function()
      regs[base + A] = regs[base + B] // regs[base + C]
    end
    H[OP_MOD] = function()
      regs[base + A] = regs[base + B] % regs[base + C]
    end
    H[OP_POW] = function()
      regs[base + A] = regs[base + B] ^ regs[base + C]
    end
    H[OP_BAND] = function()
      regs[base + A] = regs[base + B] & regs[base + C]
    end
    H[OP_BOR] = function()
      regs[base + A] = regs[base + B] | regs[base + C]
    end
    H[OP_BXOR] = function()
      regs[base + A] = regs[base + B] ~ regs[base + C]
    end
    H[OP_SHL] = function()
      regs[base + A] = regs[base + B] << regs[base + C]
    end
    H[OP_SHR] = function()
      regs[base + A] = regs[base + B] >> regs[base + C]
    end
    H[OP_UNM] = function()
      regs[base + A] = -regs[base + B]
    end
    H[OP_BNOT] = function()
      regs[base + A] = ~regs[base + B]
    end
    H[OP_NOT] = function()
      regs[base + A] = not regs[base + B]
    end
    H[OP_LEN] = function()
      regs[base + A] = #regs[base + B]
    end
    H[OP_CONCAT] = function()
      local v = regs[base + B]
      local s = type(v) == 'string' and v or tostring(v)
      for j = B + 1, C do
        v = regs[base + j]
        s = s .. (type(v) == 'string' and v or tostring(v))
      end
      regs[base + A] = s
    end
    H[OP_EQ] = function()
      local eq = (regs[base + B] == regs[base + C])
      if (eq and A == 0) or (not eq and A == 1) then pc = pc + 1 end
    end
    H[OP_LT] = function()
      local lt = (regs[base + B] < regs[base + C])
      if (lt and A == 0) or (not lt and A == 1) then pc = pc + 1 end
    end
    H[OP_LE] = function()
      local le = (regs[base + B] <= regs[base + C])
      if (le and A == 0) or (not le and A == 1) then pc = pc + 1 end
    end
    H[OP_JMP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      pc = pc + sBx
    end
    H[OP_FORPREP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      regs[base + A] = regs[base + A] - regs[base + A + 2]
      pc = pc + sBx
    end
    H[OP_FORLOOP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      regs[base + A] = regs[base + A] + regs[base + A + 2]
      local step = regs[base + A + 2]
      local limit = regs[base + A + 1]
      local idx = regs[base + A]
      local cont = ((step > 0) and (idx <= limit)) or ((step <= 0) and (idx >= limit))
      if cont then
        regs[base + A + 3] = idx
        pc = pc + sBx
      end
    end
    H[OP_TFORLOOP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      if regs[base + A + 3] ~= nil then
        regs[base + A + 2] = regs[base + A + 3]
        pc = pc + sBx
      end
    end
    H[OP_TFORCALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local results = {fn(regs[base + A + 1], regs[base + A + 2])}
        for j = 1, C do
          regs[base + A + 2 + j] = results[j]
        end
      end
    end
    H[OP_TFORPREP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      pc = pc + sBx
    end
    H[OP_TEST] = function()
      local v = regs[base + A]
      local truthy = v and v ~= false
      if (truthy and C == 0) or (not truthy and C ~= 0) then pc = pc + 1 end
    end
    H[OP_TESTSET] = function()
      local v = regs[base + B]
      local truthy = v and v ~= false
      if (truthy and C == 0) or (not truthy and C ~= 0) then
        pc = pc + 1
      else
        regs[base + A] = v
      end
    end
    H[OP_CALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local nargs = B - 1
        local results
        if nargs <= 0 then
          results = {fn()}
        elseif nargs == 1 then
          results = {fn(regs[base + A + 1])}
        elseif nargs == 2 then
          results = {fn(regs[base + A + 1], regs[base + A + 2])}
        elseif nargs == 3 then
          results = {fn(regs[base + A + 1], regs[base + A + 2], regs[base + A + 3])}
        else
          local args = {}
          for j = 1, nargs do args[j] = regs[base + A + j] end
          results = {fn(table.unpack(args))}
        end
        if C > 0 then
          for j = 1, C - 1 do
            regs[base + A + j - 1] = results[j]
          end
        else
          regs[base + A] = results[1]
        end
      end
    end
    H[OP_TAILCALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local nargs = B - 1
        if nargs <= 0 then return "RET", {fn()}
        elseif nargs == 1 then return "RET", {fn(regs[base + A + 1])}
        elseif nargs == 2 then return "RET", {fn(regs[base + A + 1], regs[base + A + 2])}
        elseif nargs == 3 then return "RET", {fn(regs[base + A + 1], regs[base + A + 2], regs[base + A + 3])}
        else
          local args = {}
          for j = 1, nargs do args[j] = regs[base + A + j] end
          return "RET", {fn(table.unpack(args))}
        end
      end
    end
    H[OP_RETURN] = function()
      if B >= 2 then
        local results = {}
        for j = 0, B - 2 do results[j + 1] = regs[base + A + j] end
        return "RET", results
      elseif B == 1 then
        return "RET", {regs[base + A]}
      else
        return "RET", {}
      end
    end
    H[OP_CLOSURE] = function()
      local sub_proto = consts[B]
      if type(sub_proto) == "table" and sub_proto.code then
        local captured_upvals = {}
        if sub_proto.upvalues then
          for ui, uv_desc in ipairs(sub_proto.upvalues) do
            captured_upvals[ui] = { regs, base + uv_desc.reg }
          end
        end
        regs[base + A] = function(...)
          local sub_regs = {}
          local args = {...}
          local n = select("#", ...)
          for ai = 1, sub_proto.numparams do
            sub_regs[ai - 1] = args[ai]
          end
          local vargs = {}
          for vi = sub_proto.numparams + 1, n do
            vargs[#vargs + 1] = args[vi]
          end
          return exec_proto(sub_proto, sub_regs, 0, n, captured_upvals, vargs)
        end
      end
    end
    H[OP_VARARG] = function()
      if B == 0 then
        if varargs then
          for j = 1, #varargs do
            regs[base + A + j - 1] = varargs[j]
          end
        end
      else
        for j = 0, B - 2 do
          regs[base + A + j] = varargs and varargs[j + 1] or nil
        end
      end
    end
    H[OP_SETLIST] = function()
      local t = regs[base + A]
      if type(t) == "table" then
        for j = 1, C do
          t[B + j - 1] = regs[base + A + j]
        end
      end
    end
    H[OP_EXTRARG] = function() end

    -- Safety: hard step limit prevents browser hang if bytecode is corrupted
    local _steps = 0
    local _max_steps = 5000000
    while pc <= #code do
      _steps = _steps + 1
      if _steps > _max_steps then
        error("VM step limit exceeded (possible infinite loop)")
      end
      local ins = code[pc]
      local op = ins.op
      A, B, C = ins.a, ins.b, ins.c
      pc = pc + 1
      local h = H[op]
      if h then
        local tag, pack = h()
        if tag == "RET" then
          return table.unpack(pack or {})
        end
      end
    end
  end

  local _cs = _cs_seed
  for _i = 1, #_d do
    _cs = (_cs + _d[_i] * (_i + _cs_seed)) & 0xFFFF
  end
  if _cs ~= _cs_expect then
    error('integrity check failed')
  end

  local main_proto = decode_proto(1)
  local regs = {}
  exec_proto(main_proto, regs, 0, 0, nil)
  _G._pack = _orig_pack
end
