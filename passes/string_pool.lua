-- ================================================================
-- passes/string_pool.lua
-- Enhanced string protection (Fengari / Lua 5.3 / 5.4 safe)
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- Pipeline:
--   extract(code)  -> replace string literals with unique tokens
--   restore(code)  -> tokens become runtime decrypt IIFEs
--   restore_raw()  -> tokens become original literals (no encrypt)
--
-- Design goals:
--   1. No bitwise ops / no string.format("%X") (Fengari integer traps)
--   2. Unique pool keys (no hash collision overwrite)
--   3. No global math.randomseed pollution
--   4. Correct round-trip for common Lua string escapes
--   5. Compact polymorphic decrypt expressions
--

local utils = require("passes.utils")
local random_int = utils.random_int

local M = {}
M.pool = {}
M._seq = 0

------------------------------------------------------------
-- 32-bit integer helpers (IEEE-754 / Fengari safe)
------------------------------------------------------------
local TWO16 = 65536
local TWO32 = 4294967296

local function to_u32(x)
  x = tonumber(x)
  if not x or x ~= x then return 0 end
  if x == math.huge or x == -math.huge then return 0 end
  if x >= 0 then
    x = math.floor(x)
  else
    x = math.ceil(x)
  end
  x = x % TWO32
  if x < 0 then x = x + TWO32 end
  -- Rebuild from 16-bit halves so host never keeps a fractional residue
  local lo = math.floor(x % TWO16)
  local hi = math.floor(x / TWO16) % TWO16
  return hi * TWO16 + lo
end

local function mul_u32(a, b)
  a = to_u32(a)
  b = to_u32(b)
  local a_lo, a_hi = a % TWO16, math.floor(a / TWO16)
  local b_lo, b_hi = b % TWO16, math.floor(b / TWO16)
  local lo = a_lo * b_lo
  local mid = a_lo * b_hi + a_hi * b_lo
  return to_u32(lo + (mid % TWO16) * TWO16)
end

local function xor_u32(a, b)
  a, b = to_u32(a), to_u32(b)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local ai, bi = a % 2, b % 2
    if ai ~= bi then r = r + bit end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit = bit * 2
  end
  return to_u32(r)
end

local function and_u32(a, b)
  a, b = to_u32(a), to_u32(b)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local ai, bi = a % 2, b % 2
    if ai == 1 and bi == 1 then r = r + bit end
    a = math.floor(a / 2)
    b = math.floor(b / 2)
    bit = bit * 2
  end
  return to_u32(r)
end

local function xor_byte(v, k)
  return and_u32(xor_u32(v, k), 255)
end

-- Local LCG: does NOT touch math.randomseed
local function lcg_next(state)
  -- Numerical Recipes LCG constants, 32-bit
  return to_u32(mul_u32(state, 1664525) + 1013904223)
end

local function prng16(seed)
  return lcg_next(to_u32(seed)) % TWO16
end

-- FNV-1a style 31-bit seed
local function derive_seed(str)
  local h = to_u32(2166136261)
  local MASK = 2147483647
  for i = 1, #str do
    local x = xor_u32(h, str:byte(i) or 0)
    x = mul_u32(x, 16777619)
    h = and_u32(x, MASK)
  end
  return h
end

local HEX = "0123456789ABCDEF"
local function to_hex8(n)
  n = to_u32(n)
  local t = {}
  for i = 8, 1, -1 do
    local d = math.floor(n % 16)
    t[i] = HEX:sub(d + 1, d + 1)
    n = math.floor(n / 16)
  end
  return table.concat(t)
end

-- Fisher-Yates with local LCG (no global RNG side effects)
local function shuffle(t, seed)
  local state = to_u32(seed == 0 and 1 or seed)
  for i = #t, 2, -1 do
    state = lcg_next(state)
    local j = (state % i) + 1
    t[i], t[j] = t[j], t[i]
  end
end

------------------------------------------------------------
-- Escape processing (source literal -> raw bytes string)
------------------------------------------------------------
function M.process_escapes(s)
  if not s or s == "" then return s or "" end
  local out = {}
  local n = 0
  local i = 1
  local len = #s
  while i <= len do
    local c = s:byte(i)
    if c == 92 and i < len then -- backslash
      local nc = s:byte(i + 1)
      n = n + 1
      if nc == 97 then out[n] = "\a"; i = i + 2          -- \a
      elseif nc == 98 then out[n] = "\b"; i = i + 2      -- \b
      elseif nc == 102 then out[n] = "\f"; i = i + 2     -- \f
      elseif nc == 110 then out[n] = "\n"; i = i + 2     -- \n
      elseif nc == 114 then out[n] = "\r"; i = i + 2     -- \r
      elseif nc == 116 then out[n] = "\t"; i = i + 2     -- \t
      elseif nc == 118 then out[n] = "\v"; i = i + 2     -- \v
      elseif nc == 92 then out[n] = "\\"; i = i + 2      -- \\
      elseif nc == 34 then out[n] = "\""; i = i + 2      -- \"
      elseif nc == 39 then out[n] = "'"; i = i + 2       -- \'
      elseif nc == 10 then out[n] = "\n"; i = i + 2      -- \<newline> line continue -> newline
      elseif nc == 13 then                                 -- \r optional \n
        if i + 2 <= len and s:byte(i + 2) == 10 then
          out[n] = "\n"; i = i + 3
        else
          out[n] = "\n"; i = i + 2
        end
      elseif nc == 120 then -- \xHH
        local h1 = i + 2 <= len and s:sub(i + 2, i + 2) or ""
        local h2 = i + 3 <= len and s:sub(i + 3, i + 3) or ""
        if h1:match("[%da-fA-F]") and h2:match("[%da-fA-F]") then
          out[n] = string.char(tonumber(h1 .. h2, 16) or 0)
          i = i + 4
        else
          out[n] = string.char(nc); i = i + 2
        end
      elseif nc >= 48 and nc <= 57 then -- \ddd decimal (up to 3 digits)
        local j = i + 1
        local digits = {}
        while j <= len and #digits < 3 do
          local b = s:byte(j)
          if b >= 48 and b <= 57 then
            digits[#digits + 1] = string.char(b)
            j = j + 1
          else
            break
          end
        end
        local val = tonumber(table.concat(digits), 10) or 0
        if val > 255 then val = 255 end
        out[n] = string.char(val)
        i = j
      elseif nc == 122 then -- \z skip whitespace
        i = i + 2
        n = n - 1 -- cancel the slot; no output char
        while i <= len do
          local b = s:byte(i)
          if b == 32 or b == 9 or b == 10 or b == 13 or b == 12 then
            i = i + 1
          else
            break
          end
        end
      else
        -- unknown escape: keep the escaped char (Lua behavior for many cases)
        out[n] = string.char(nc)
        i = i + 2
      end
    else
      n = n + 1
      out[n] = string.char(c)
      i = i + 1
    end
  end
  return table.concat(out)
end

------------------------------------------------------------
-- Encrypt: XOR + optional slice shuffle
------------------------------------------------------------
local function encrypt_bytes(str, seed)
  local key = and_u32(xor_u32(prng16(seed), prng16(math.floor(seed / 256) + 1)), 255)
  if key == 0 then key = 1 end

  local bytes = {}
  -- Keystream-ish XOR: key rotates with index (stronger than fixed single-byte)
  local k = key
  for i = 1, #str do
    local b = str:byte(i) or 0
    bytes[i] = xor_byte(b, k)
    k = and_u32(k + 1 + (i % 7), 255)
    if k == 0 then k = 1 end
  end

  -- Pack into 4-byte slices with original positions, then shuffle storage
  local slices = {}
  local si, orig = 1, 1
  while si <= #bytes do
    local slice = {}
    for j = 0, 3 do
      if si + j <= #bytes then
        slice[#slice + 1] = bytes[si + j]
      end
    end
    slices[#slices + 1] = { pos = orig, data = slice }
    orig = orig + 1
    si = si + 4
  end

  shuffle(slices, xor_u32(seed, key * 31337))
  return { key = key, slices = slices }
end

local function make_unique_key(str)
  M._seq = M._seq + 1
  -- content hash + monotonic seq => unique even on collisions / identical strings
  return "__SH_" .. to_hex8(derive_seed(str)) .. "_" .. tostring(M._seq) .. "__"
end

------------------------------------------------------------
-- Generate runtime decrypt expression (pure arithmetic XOR)
------------------------------------------------------------
local function slices_to_lua(slices)
  local parts = {}
  for _, s in ipairs(slices) do
    local elems = { "p=" .. tostring(s.pos or 0) }
    for _, b in ipairs(s.data or {}) do
      elems[#elems + 1] = tostring(and_u32(b or 0, 255))
    end
    parts[#parts + 1] = "{" .. table.concat(elems, ",") .. "}"
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- Shared XOR body (byte-safe, no bitops): inlined into generated code
-- Reconstructs bytes in order of pos, then applies reverse keystream.
local function build_decode_expr(enc, style)
  local key = and_u32(enc.key, 255)
  local cstr = slices_to_lua(enc.slices)
  -- Keystream reverse must match encrypt_bytes
  -- encrypt: k0=key; for i=1..n: out=xor(in,k); k=(k+1+(i%7))%256; if k==0 then k=1
  -- So for decrypt we rebuild flat ordered bytes first, then run same k sequence.

  if style == 1 then
    return table.concat({
      "(function()",
      "local k=", tostring(key), ";",
      "local c=", cstr, ";",
      "table.sort(c,function(a,b)return(a.p or 0)<(b.p or 0)end);",
      "local f={};",
      "for _,s in ipairs(c) do for i=1,#s do f[#f+1]=s[i]%256 end end;",
      "local t={}; local kk=k;",
      "for i=1,#f do",
      " local x=f[i]; local y=kk%256; local r=0; local p=1; local xx,yy=x,y;",
      " for _=1,8 do local xi=xx%2; local yi=yy%2; if xi~=yi then r=r+p end; xx=(xx-xi)/2; yy=(yy-yi)/2; p=p*2 end;",
      " t[i]=string.char(r);",
      " kk=(kk+1+(i%7))%256; if kk==0 then kk=1 end;",
      "end;",
      "return table.concat(t)",
      "end)()",
    })
  elseif style == 2 then
    -- same logic, different control-flow shape
    return table.concat({
      "(function()",
      "local K=", tostring(key), ";local C=", cstr, ";",
      "table.sort(C,function(u,v)return(u.p or 0)<(v.p or 0)end);",
      "local B,I={},1;",
      "for _,S in ipairs(C) do for j=1,#S do B[I]=S[j]%256;I=I+1 end end;",
      "local O,kk={},K;",
      "for i=1,#B do",
      " local x,y=B[i],kk%256; local r,p,xx,yy=0,1,x,y;",
      " for _=1,8 do local xi=xx%2;local yi=yy%2;if xi~=yi then r=r+p end;xx=(xx-xi)/2;yy=(yy-yi)/2;p=p*2 end;",
      " O[i]=string.char(r); kk=(kk+1+(i%7))%256; if kk==0 then kk=1 end;",
      "end;return table.concat(O)",
      "end)()",
    })
  else
    -- reverse accumulate then reverse back (polymorphism)
    return table.concat({
      "(function()",
      "local k=", tostring(key), ";local c=", cstr, ";",
      "table.sort(c,function(a,b)return(a.p or 0)<(b.p or 0)end);",
      "local f={}; for _,s in ipairs(c) do for i=1,#s do f[#f+1]=s[i]%256 end end;",
      "local t,kk={},k;",
      "for i=1,#f do",
      " local x,y=f[i],kk%256; local r,p,xx,yy=0,1,x,y;",
      " for _=1,8 do local xi=xx%2;local yi=yy%2;if xi~=yi then r=r+p end;xx=(xx-xi)/2;yy=(yy-yi)/2;p=p*2 end;",
      " t[i]=string.char(r); kk=(kk+1+(i%7))%256; if kk==0 then kk=1 end;",
      "end;",
      "local o={}; for i=#t,1,-1 do o[#o+1]=t[i] end;",
      "local p={}; for i=#o,1,-1 do p[#p+1]=o[i] end;",
      "return table.concat(p)",
      "end)()",
    })
  end
end

------------------------------------------------------------
-- Extract string literals
------------------------------------------------------------
local function should_skip_quote(code, q)
  -- skip length operator #"..." or #'...'
  if q > 1 and code:byte(q - 1) == 35 then return true end -- #
  -- skip already-tokenized
  return false
end

local function extract_quoted(code, quote_byte)
  local quote_char = string.char(quote_byte)
  local result = {}
  local pos, last = 1, 1
  local len = #code
  local changed = false

  while pos <= len do
    local q = code:find(quote_char, pos, true)
    if not q then break end

    -- crude comment skip: if this line has -- before quote and not in prior string... hard.
    -- Skip line comments: if we see -- before quote on same line without being part of string we started
    local line_start = (code:sub(1, q):find("\n[^\n]*$") or 0)
    -- simpler: check for -- between previous newline and q
    local prev_nl = 0
    for i = q - 1, 1, -1 do
      if code:byte(i) == 10 then prev_nl = i; break end
    end
    local prefix = code:sub(prev_nl + 1, q - 1)
    local comment_pos = prefix:find("%-%-")
    if comment_pos then
      -- treat as not a string; advance past quote char
      pos = q + 1
    else
      local j = q + 1
      while j <= len do
        local c = code:byte(j)
        if c == 92 then
          j = j + 2 -- skip escape
        elseif c == quote_byte then
          j = j + 1
          break
        else
          j = j + 1
        end
      end
      local s = code:sub(q + 1, j - 2)
      if not should_skip_quote(code, q) and not s:find("__SH_", 1, true) then
        local hk = make_unique_key(s)
        M.pool[hk] = {
          raw = s,
          kind = (quote_byte == 34) and "double" or "single",
        }
        result[#result + 1] = code:sub(last, q - 1)
        result[#result + 1] = hk
        last = j
        changed = true
      end
      pos = j
    end
  end

  if changed then
    result[#result + 1] = code:sub(last)
    return table.concat(result)
  end
  return code
end

local function extract_long(code)
  -- support [[...]] and [=[...]=] ... up to a few = signs
  local result = {}
  local pos, last = 1, 1
  local len = #code
  local changed = false

  while pos <= len do
    local s = code:find("%[", pos)
    if not s then break end
    local eqs = code:match("^%[(=*)%[", s)
    if not eqs then
      pos = s + 1
    else
      -- check comment --[[
      local is_comment = false
      if s > 2 and code:sub(s - 2, s - 1) == "--" then
        is_comment = true
      end
      local close = "]" .. eqs .. "]"
      local cstart = s + 2 + #eqs
      local cpos = code:find(close, cstart, true)
      if not cpos then
        pos = s + 1
      else
        if is_comment then
          pos = cpos + #close
        else
          local content = code:sub(cstart, cpos - 1)
          if not content:find("__SH_", 1, true) then
            local hk = make_unique_key(content)
            M.pool[hk] = { raw = content, kind = "long", long_eq = eqs }
            result[#result + 1] = code:sub(last, s - 1)
            result[#result + 1] = hk
            last = cpos + #close
            changed = true
          end
          pos = cpos + #close
        end
      end
    end
  end

  if changed then
    result[#result + 1] = code:sub(last)
    return table.concat(result)
  end
  return code
end

function M.extract(code)
  M.pool = {}
  M._seq = 0
  if type(code) ~= "string" or code == "" then return code end

  -- long strings first (so quotes inside [[ ]] are not touched)
  code = extract_long(code)
  code = extract_quoted(code, 34) -- "
  code = extract_quoted(code, 39) -- '
  return code
end

------------------------------------------------------------
-- Restore
------------------------------------------------------------
function M.restore(code)
  if type(code) ~= "string" or not next(M.pool) then return code end

  local replacements = {}
  for hk, info in pairs(M.pool) do
    local raw_str = info.kind == "long" and (info.raw or "") or M.process_escapes(info.raw or "")
    local seed = derive_seed(raw_str .. "\0" .. hk) -- include key for uniqueness
    local enc = encrypt_bytes(raw_str, seed)
    local style = random_int(1, 3)
    replacements[hk] = build_decode_expr(enc, style)
  end

  -- tokens look like __SH_XXXXXXXX_123__
  code = code:gsub("__SH_[0-9A-Fa-f]+_%d+__", function(k)
    return replacements[k] or k
  end)
  -- backward-compat older token form without seq
  code = code:gsub("__SH_[0-9A-Fa-f]+__", function(k)
    return replacements[k] or k
  end)

  return code
end

function M.restore_raw(code)
  if type(code) ~= "string" or not next(M.pool) then return code end

  local function restore_one(k)
    local info = M.pool[k]
    if not info then return k end
    if info.kind == "long" then
      local eq = info.long_eq or ""
      return "[" .. eq .. "[" .. (info.raw or "") .. "]" .. eq .. "]"
    end
    local q = info.kind == "single" and "'" or '"'
    return q .. (info.raw or "") .. q
  end

  code = code:gsub("__SH_[0-9A-Fa-f]+_%d+__", restore_one)
  code = code:gsub("__SH_[0-9A-Fa-f]+__", restore_one)
  return code
end

return M
