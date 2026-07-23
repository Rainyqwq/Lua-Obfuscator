-- ================================================================
-- passes/instr_sub.lua
-- Instruction Substitution v3 — safe expression polymorphism
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- Only rewrites standalone atomic-op-atomic expressions.
-- An atomic operand is: identifier, number literal, or (...).
-- Never touches strings, calls, fields, or sub-expressions.

local utils = require("passes.utils")
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local is_comment = utils.is_comment
local is_empty = utils.is_empty

local M = {}

M.name    = "instruction_substitution"
M.title   = "Instruction Substitution"
M.version = "3.0.0"
M.order   = 40
M.enabled = true

------------------------------------------------------------
local function pick(t) return t[random_int(1, #t)] end

local KEYWORDS = {
  ["and"]=true, ["or"]=true, ["not"]=true, ["if"]=true, ["then"]=true,
  ["else"]=true, ["elseif"]=true, ["end"]=true, ["for"]=true, ["while"]=true,
  ["do"]=true, ["repeat"]=true, ["until"]=true, ["function"]=true,
  ["local"]=true, ["return"]=true, ["break"]=true, ["goto"]=true,
  ["in"]=true, ["nil"]=true, ["true"]=true, ["false"]=true,
}
local function is_kw(s) return KEYWORDS[s] == true end

------------------------------------------------------------
-- Protected region mask (strings + comments)
------------------------------------------------------------
local function build_mask(s)
  local mask = {}
  local i, n = 1, #s
  while i <= n do
    local c = s:byte(i)
    if c == 45 and i < n and s:byte(i+1) == 45 then
      for j = i, n do mask[j] = true end
      break
    elseif c == 91 then
      local eqs = s:match("^%[(=*)%[", i)
      if eqs then
        local close = "]" .. eqs .. "]"
        local cpos = s:find(close, i + 2 + #eqs, true) or n
        for j = i, cpos + #close - 1 do mask[j] = true end
        i = cpos + #close
      else
        i = i + 1
      end
    elseif c == 34 or c == 39 then
      mask[i] = true
      local j, qc = i + 1, c
      while j <= n do
        mask[j] = true
        local b = s:byte(j)
        if b == 92 then
          if j+1 <= n then mask[j+1] = true end
          j = j + 2
        elseif b == qc then
          j = j + 1; break
        else
          j = j + 1
        end
      end
      i = j
    else
      i = i + 1
    end
  end
  return mask
end

local function free_range(mask, a, b)
  for i = a, b do if mask[i] then return false end end
  return true
end

------------------------------------------------------------
-- Operand classification (with mask passed in)
------------------------------------------------------------
local function classify_left(line, le, mask)
  if le < 1 then return nil end
  local ch = line:sub(le, le)

  if ch == ")" then
    local depth, j = 1, le - 1
    while j >= 1 do
      local c = line:sub(j, j)
      if c == ")" then depth = depth + 1
      elseif c == "(" then
        depth = depth - 1
        if depth == 0 then
          if not free_range(mask, j, le) then return nil end
          return "parens", line:sub(j, le), j
        end
      end
      j = j - 1
    end
    return nil
  end

  if not ch:match("[%w_]") then return nil end

  -- number ending here
  if ch:match("[%da-fA-F]") then
    local ls = le
    while ls > 1 and line:sub(ls-1, ls-1):match("[%da-fA-FxX%.]") do ls = ls - 1 end
    local tok = line:sub(ls, le)
    if tok:match("^0[xX][%da-fA-F]+$") or tok:match("^%d+%.?%d*$")
        or tok:match("^%d+%.$") or tok:match("^%.%d+$") then
      if tok ~= "." and free_range(mask, ls, le) then
        return "num", tok, ls
      end
    end
  end

  -- identifier
  local ls = le
  while ls > 1 and line:sub(ls-1, ls-1):match("[%w_]") do ls = ls - 1 end
  local tok = line:sub(ls, le)
  if tok:match("^[%a_][%w_]*$") and not is_kw(tok) and free_range(mask, ls, le) then
    return "ident", tok, ls
  end
  return nil
end

local function classify_right(line, rs, n, mask)
  if rs > n then return nil end
  local ch = line:sub(rs, rs)

  if ch == "(" then
    local depth, j = 1, rs + 1
    while j <= n do
      local c = line:sub(j, j)
      if c == "(" then depth = depth + 1
      elseif c == ")" then
        depth = depth - 1
        if depth == 0 then
          if not free_range(mask, rs, j) then return nil end
          return "parens", line:sub(rs, j), j
        end
      end
      j = j + 1
    end
    return nil
  end

  if ch:match("[%a_]") then
    local re = rs
    while re < n and line:sub(re+1, re+1):match("[%w_]") do re = re + 1 end
    local tok = line:sub(rs, re)
    if not tok:match("^[%a_][%w_]*$") or is_kw(tok) then return nil end
    local k = re + 1
    while k <= n and line:byte(k) <= 32 do k = k + 1 end
    if k <= n then
      local nc = line:sub(k, k)
      if nc == "(" or nc == "[" or nc == "." or nc == ":" then return nil end
    end
    if not free_range(mask, rs, re) then return nil end
    return "ident", tok, re
  end

  if ch:match("[%d%.]") then
    if line:sub(rs, rs+1):match("^0[xX]") then
      local re = rs + 1
      while re < n and line:sub(re+1, re+1):match("[%da-fA-F]") do re = re + 1 end
      local tok = line:sub(rs, re)
      if tok:match("^0[xX][%da-fA-F]+$") and free_range(mask, rs, re) then
        return "num", tok, re
      end
      return nil
    end
    local re = rs
    while re < n and line:sub(re+1, re+1):match("%d") do re = re + 1 end
    if re < n and line:sub(re+1, re+1) == "." then
      local re2 = re + 1
      while re2 < n and line:sub(re2+1, re2+1):match("%d") do re2 = re2 + 1 end
      if re2 > re + 1 then re = re2 end
    end
    local tok = line:sub(rs, re)
    if (tok:match("^%d+$") or tok:match("^%d+%.%d+$") or tok:match("^%.%d+$"))
        and free_range(mask, rs, re) then
      return "num", tok, re
    end
  end
  return nil
end

------------------------------------------------------------
-- Boundary safety
------------------------------------------------------------
local function safe_left(line, ls)
  local p = ls - 1
  while p >= 1 and line:byte(p) and line:byte(p) <= 32 do p = p - 1 end
  if p < 1 then return true end
  local ch = line:sub(p, p)
  return ch == "(" or ch == "[" or ch == "{" or ch == "," or ch == ";"
      or ch == "=" or ch:match("[%a_]")
end

local function safe_right(line, re)
  local n = #line
  local p = re + 1
  while p <= n and line:byte(p) and line:byte(p) <= 32 do p = p + 1 end
  if p > n then return true end
  local ch = line:sub(p, p)
  return ch == ")" or ch == "]" or ch == "}" or ch == "," or ch == ";"
      or ch:match("[%a_]")
end

------------------------------------------------------------
-- Equivalent forms
------------------------------------------------------------
local FORMS = {
  -- a + b == a - (-b) == -(-a) - (-b)
  add = function(a,b) return "("..a.."-(0-("..b..")))" end,
  -- a - b == a + (-b) == (0+a) - (b+0)
  sub = function(a,b) return pick({
    "("..a.."+(0-("..b..")))",
    "((0+("..a.."))-(("..b.."+0)))",
  }) end,
  -- a * b == (0+a) * (0+b)
  mul = function(a,b) return pick({
    "(("..a..")*(0+("..b..")))",
    "((0+("..a.."))*("..b.."))",
  }) end,
  -- a / b == (0+a) / (b)
  div = function(a,b) return pick({
    "(("..a..")/("..b.."))",
    "((0+("..a.."))/("..b.."))",
  }) end,
  -- a % b == (0+a) % b
  mod = function(a,b) return pick({
    "(("..a..")%("..b.."))",
    "((0+("..a.."))%("..b.."))",
  }) end,
  eq  = function(a,b) return "(not(("..a..")~=("..b..")))" end,
  ne  = function(a,b) return "(not(("..a..")==("..b..")))" end,
  lt  = function(a,b) return "(not(("..a..")>=("..b..")))" end,
  gt  = function(a,b) return "(not(("..a..")<=("..b..")))" end,
  le  = function(a,b) return "(not(("..a..")>("..b..")))" end,
  ge  = function(a,b) return "(not(("..a..")<("..b..")))" end,
  -- a .. b == (""..a)..b == a..(""..b)
  concat = function(a,b) return pick({
    "((\"\"..("..a.."))..("..b.."))",
    "(("..a..")..(\"\"..("..b..")))",
  }) end,
  not_ = function(x) return "(not(not(not("..x.."))))" end,
}

------------------------------------------------------------
-- Scanners
------------------------------------------------------------
local function scan_ops(line, mask, pat, rewriter, budget)
  local hits, n, pos = 0, #line, 1
  while pos <= n and hits < budget do
    local s, e = line:find(pat, pos)
    if not s then break end
    if not free_range(mask, s, e) then
      pos = e + 1
    else
      local le = s - 1
      while le >= 1 and line:byte(le) and line:byte(le) <= 32 do le = le - 1 end
      local lkind, ltxt, ls = classify_left(line, le, mask)
      if not ls then
        pos = e + 1
      else
        local rs = e + 1
        while rs <= n and line:byte(rs) and line:byte(rs) <= 32 do rs = rs + 1 end
        local rkind, rtxt, re = classify_right(line, rs, n, mask)
        if not re then
          pos = e + 1
        elseif not free_range(mask, ls, re) then
          pos = e + 1
        elseif not safe_left(line, ls) or not safe_right(line, re) then
          pos = e + 1
        elseif random_int(1, 100) <= 60 then
          local repl = rewriter(ltxt, rtxt)
          line = line:sub(1, ls-1) .. repl .. line:sub(re+1)
          mask = build_mask(line)
          n = #line
          hits = hits + 1
          pos = ls + #repl
        else
          pos = e + 1
        end
      end
    end
  end
  return line, hits
end

local function scan_not(line, mask, budget)
  local hits, n, pos = 0, #line, 1
  while pos <= n and hits < budget do
    local s, e = line:find("%f[%w_]not%f[^%w_]", pos)
    if not s then break end
    if not free_range(mask, s, e) then
      pos = e + 1
    else
      local rs = e + 1
      while rs <= n and line:byte(rs) and line:byte(rs) <= 32 do rs = rs + 1 end
      local _, rtxt, re = classify_right(line, rs, n, mask)
      if not re then
        pos = e + 1
      elseif not free_range(mask, s, re) then
        pos = e + 1
      elseif not safe_right(line, re) then
        pos = e + 1
      elseif random_int(1, 100) <= 50 then
        local repl = FORMS.not_(rtxt)
        line = line:sub(1, s-1) .. repl .. line:sub(re+1)
        mask = build_mask(line)
        n = #line
        hits = hits + 1
        pos = s + #repl
      else
        pos = e + 1
      end
    end
  end
  return line, hits
end

------------------------------------------------------------
-- Main
------------------------------------------------------------
function M.apply(code, _ctx)
  if type(code) ~= "string" or code == "" then return code end
  local lines = split_lines(code)
  local out = {}
  for _, line in ipairs(lines) do
    if is_empty(line) or is_comment(line) or line:match("%d[%.%d]*[eE][%+%-]?%d") then
      out[#out+1] = line
    else
      local mask = build_mask(line)
      local total, h, max = 0, 0, 4

      local function run(pat, fn, budget)
        if total >= max or budget <= 0 then return end
        line, h = scan_ops(line, mask, pat, fn, budget)
        total = total + (h or 0)
        mask = build_mask(line)
      end

      run("%>%=", FORMS.ge,  max-total)
      run("%<%=", FORMS.le,  max-total)
      run("%~%=", FORMS.ne,  max-total)
      run("%=%=", FORMS.eq,  max-total)
      run("%>",   FORMS.gt,  max-total)
      run("%<",   FORMS.lt,  max-total)
      run("%.%.", FORMS.concat, max-total)
      run("%+",   FORMS.add, max-total)
      run("%-",   FORMS.sub, max-total)
      run("%*",   FORMS.mul, max-total)
      run("%/",   FORMS.div, max-total)
      run("%%",   FORMS.mod, max-total)

      if total < max then
        line, h = scan_not(line, mask, math.min(1, max-total))
        total = total + (h or 0)
      end

      out[#out+1] = line
    end
  end
  return join_lines(out)
end

return M
