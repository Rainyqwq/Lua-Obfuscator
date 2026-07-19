#!/usr/bin/env lua
--[[
  Lua Obfuscator v2.4
  功能：
    1. 控制流平坦化 (Control Flow Flattening)
    2. 常量数字加密 (Constant Number Encryption)
    3. BCF 虚假控制流块 (Bogus Control Flow)
    4. 变量名混淆 (Variable Name Mangling)
    5. 字符串加密 (String Encryption)
    6. 垃圾注释 (Junk Comments)
    7. 指令替换 (Instruction Substitution)       ← NEW
    8. 虚假控制流增强 (Advanced Fake Control Flow) ← NEW
    9. 基本块拆分 (Basic Block Splitting)         ← NEW
]]

local VERSION = "2.4.0"

------------------------------------------------------------
-- 工具函数
------------------------------------------------------------
local function trim(s)
  return s:match("^%s*(.-)%s*$")
end

local function split_lines(s)
  local lines = {}
  for line in s:gmatch("([^\n]*)\n?") do
    lines[#lines + 1] = line
  end
  if lines[#lines] == "" and #lines > 1 then
    table.remove(lines)
  end
  return lines
end

local function join_lines(lines)
  return table.concat(lines, "\n")
end

local function random_id(len)
  len = len or 8
  local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  local id = ""
  for i = 1, len do
    local r = math.random(1, #chars)
    id = id .. chars:sub(r, r)
  end
  return id
end

local function random_int(min, max)
  return math.random(min, max)
end

-- 嵌套深度跟踪（通用）
local function calc_depth(line)
  local trimmed = trim(line)
  if trimmed == "" or trimmed:match("^%-%-") then return 0, 0 end
  local stripped = trimmed:gsub('%b""', ''):gsub("%b''", ''):gsub('%b[]', '  ')
  local opens, closes = 0, 0
  for _ in stripped:gmatch('%f[%a]function%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]do%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]then%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]else%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]repeat%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('{') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]end%f[%A]') do closes = closes + 1 end
  for _ in stripped:gmatch('%f[%a]until%f[%A]') do closes = closes + 1 end
  for _ in stripped:gmatch('}') do closes = closes + 1 end
  return opens, closes
end

-- 提取字符串字面量的正则安全版本
local function strip_strings_from_line(line)
  return line:gsub('%b""', '""'):gsub("%b''", "''"):gsub("%[%[.-%]%]", "[[]]")
end

------------------------------------------------------------
-- 编码/加密工具
------------------------------------------------------------

-- 数字加密：将数字 n 转换为等价的数学表达式
local function encrypt_number(n)
  if n == 0 then return "(0x0|0)" end
  if n == 1 then return "(0x1&0x1)" end
  if n == -1 then return "(~0x0)" end

  -- Float numbers: split into integer + fractional, obfuscate separately
  -- Multiplication/division by powers of 2 is lossless in IEEE 754
  if n ~= math.floor(n) then
    local int_part = math.floor(n)
    local frac = n - int_part
    local shift = 2 ^ random_int(1, 8)
    -- Obfuscate integer part with XOR (same as integer path)
    local int_enc
    if int_part == 0 then
      int_enc = "(0x0|0)"
    else
      local abs_int = math.abs(int_part)
      local sign = int_part < 0 and "-" or ""
      local a = random_int(1, 0xFFFF)
      local b = a ~ abs_int
      int_enc = string.format("%s(0x%X~0x%X)", sign, a, b)
    end
    -- Fractional part: multiply/divide by power of 2 (lossless)
    return string.format("(%s+%.15g*%d/%d)", int_enc, frac, shift, shift)
  end

  local abs_n = math.abs(n)
  local sign = n < 0 and "-" or ""
  local method = random_int(1, 5)

  if method == 1 then
    local a = random_int(1, 0xFFFF)
    local b = a ~ abs_n
    return string.format("%s(0x%X~0x%X)", sign, a, b)
  elseif method == 2 then
    local a = random_int(1, 0xFFFF)
    local b = abs_n + a
    return string.format("%s(0x%X-0x%X)", sign, b, a)
  elseif method == 3 and abs_n > 1 then
    local shift = random_int(1, 4)
    local base = abs_n << shift
    return string.format("%s(0x%X>>%d)", sign, base, shift)
  elseif method == 4 and abs_n > 2 and abs_n < 10000 then
    for f = 2, math.min(abs_n - 1, 100) do
      if abs_n % f == 0 then
        return string.format("%s(0x%X*0x%X)", sign, f, abs_n // f)
      end
    end
    local a = random_int(0, 0xFFFF)
    return string.format("%s(0x%X~0x%X)", sign, abs_n ~ a, a)
  else
    local a = random_int(1, 0xFFFF)
    local b = a ~ abs_n
    return string.format("%s(0x%X~0x%X)", sign, a, b)
  end
end

-- XOR 编码字符串
local function encode_string_xor(str)
  local key = random_int(1, 255)
  local encoded = {}
  for i = 1, #str do
    encoded[i] = string.byte(str, i) ~ key
  end
  local tbl_str = table.concat(encoded, ",")
  return string.format(
    '(function() local _k=%d; local _d={%s}; local _r={}; for _i=1,#_d do _r[_i]=string.char(_d[_i]~_k) end; return table.concat(_r) end)()',
    key, tbl_str
  )
end

-- ROT13 + char code 编码字符串（第二层加密）
local function encode_string_rot13(str)
  local parts = {}
  for i = 1, #str do
    local b = string.byte(str, i)
    -- 用算术表达式替代直接字节值
    local a = random_int(1, 200)
    local c = b + a
    parts[i] = string.format("string.char(%d-%d)", c, a)
  end
  return "(" .. table.concat(parts, "..") .. ")"
end

-- Base64 风格编码（表驱动解码）
local function encode_string_table(str)
  local key = random_int(1, 255)
  local bytes = {}
  for i = 1, #str do
    bytes[i] = string.byte(str, i) ~ key
  end
  local byte_str = table.concat(bytes, ",")
  local fn = "_dec" .. random_id(4)
  return string.format(
    '(function() local %s={%s}; local _k=%d; local _r={}; for _i=1,#%s do _r[_i]=string.char(%s[_i]~_k) end; return table.concat(_r) end)()',
    fn, byte_str, key, fn, fn
  )
end

------------------------------------------------------------
-- 混淆器配置
------------------------------------------------------------
local Config = {
  control_flow_flattening = true,
  constant_encryption = true,
  bogus_control_flow = true,
  variable_mangling = true,
  string_encryption = true,
  junk_comments = true,
  instruction_substitution = true,   -- 指令替换
  advanced_fake_cf = true,           -- 虚假控制流增强
  basic_block_splitting = true,      -- 基本块拆分
  vm_protect = false,                 -- VM 字节码虚拟化（默认关闭，需手动开启）
}

------------------------------------------------------------
-- 字符串保护
------------------------------------------------------------
local StringPool = {}

-- 处理Lua字符串转义序列
local function process_escapes(s)
  local result = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" and i < #s then
      local nc = s:sub(i+1, i+1)
      if nc == "n" then result[#result+1] = "\n"
      elseif nc == "t" then result[#result+1] = "\t"
      elseif nc == "r" then result[#result+1] = "\r"
      elseif nc == "\\" then result[#result+1] = "\\"
      elseif nc == '"' then result[#result+1] = '"'
      elseif nc == "'" then result[#result+1] = "'"
      elseif nc == "0" then result[#result+1] = "\0"
      else result[#result+1] = "\\" .. nc end
      i = i + 2
    else
      result[#result+1] = c
      i = i + 1
    end
  end
  return table.concat(result)
end

local function extract_strings(code)
  StringPool = {}
  local idx = 0
  local result = {}
  local i = 1
  local len = #code
  while i <= len do
    local c = code:sub(i, i)
    if c == "[" and code:sub(i+1, i+1) == "[" then
      local close = code:find("]]", i+2, true)
      if close then
        idx = idx + 1
        local ph = "__STR_" .. idx .. "__"
        StringPool[ph] = { raw = code:sub(i+2, close-1), q = "long" }
        result[#result+1] = ph
        i = close + 2
      else
        result[#result+1] = c; i = i + 1
      end
    elseif c == '"' then
      local j = i + 1
      while j <= len do
        local sc = code:sub(j, j)
        if sc == '\\' and j < len then j = j + 2
        elseif sc == '"' then j = j + 1; break
        else j = j + 1 end
      end
      idx = idx + 1
      local ph = "__STR_" .. idx .. "__"
      local raw = code:sub(i+1, j-2)
      if raw == "" then
        -- Skip empty strings, keep them as-is
        idx = idx - 1
        result[#result+1] = code:sub(i, j-1)
      else
        StringPool[ph] = { raw = raw, q = '"' }
        result[#result+1] = '"' .. ph .. '"'
      end
      i = j
    elseif c == "'" then
      local j = i + 1
      while j <= len do
        local sc = code:sub(j, j)
        if sc == '\\' and j < len then j = j + 2
        elseif sc == "'" then j = j + 1; break
        else j = j + 1 end
      end
      idx = idx + 1
      local ph = "__STR_" .. idx .. "__"
      local raw = code:sub(i+1, j-2)
      if raw == "" then
        idx = idx - 1
        result[#result+1] = code:sub(i, j-1)
      else
        StringPool[ph] = { raw = raw, q = "'" }
        result[#result+1] = "'" .. ph .. "'"
      end
      i = j
    elseif c == '-' and code:sub(i+1, i+1) == '-' then
      local nl = code:find('\n', i, true)
      if nl then result[#result+1] = code:sub(i, nl-1); i = nl
      else result[#result+1] = code:sub(i); i = len + 1 end
    else
      result[#result+1] = c; i = i + 1
    end
  end
  return table.concat(result)
end

-- Escape special chars for Lua string literal

-- Escape % for gsub replacement strings
local function gsub_safe(s)
  return s:gsub("%%", "%%%%")
end


local function restore_strings(code)
  for placeholder, info in pairs(StringPool) do
    local safe_ph = placeholder  -- no escaping needed, placeholder has no pattern chars
    if Config.string_encryption then
      local method = random_int(1, 3)
      local encoded
      local enc_raw = info.source or info.raw
      if method == 1 then encoded = encode_string_xor(enc_raw)
      elseif method == 2 then encoded = encode_string_rot13(enc_raw)
      else encoded = encode_string_table(enc_raw) end
      local enc_safe = gsub_safe(encoded)
      if info.q == "long" then
        code = code:gsub(safe_ph, enc_safe)
      else
        code = code:gsub(info.q .. safe_ph .. info.q, enc_safe)
      end
    else
      if info.q == "long" then
        local level = 0
        while info.raw:find("]" .. string.rep("=", level) .. "]", 1, true) do
          level = level + 1
        end
        local eq = string.rep("=", level)
        code = code:gsub(safe_ph, "[" .. eq .. "[" .. info.raw .. "]" .. eq .. "]")
      else
        local _s = info.q .. safe_ph .. info.q
        local _r = gsub_safe(info.q .. info.raw .. info.q)
        local _nc = code:gsub(_s, _r)
        if _nc == code then io.stderr:write("[MISS] "..placeholder.." s=[".._s:sub(1,30).."]\n") end
        code = _nc
      end
    end
  end
  return code
end


local function obfuscate_numbers(code)
  local num_pool = {}
  local num_idx = 0
  local result_parts = {}
  local pos = 1
  local len = #code

  while pos <= len do
    local c = code:sub(pos, pos)
    local matched = false

    -- Skip string literals
    if c == '"' or c == "'" then
      local quote = c
      local j = pos + 1
      while j <= len do
        local sc = code:sub(j, j)
        if sc == '\\' then j = j + 2
        elseif sc == quote then j = j + 1; break
        else j = j + 1 end
      end
      result_parts[#result_parts+1] = code:sub(pos, j - 1)
      pos = j
      matched = true

    -- Skip placeholders
    elseif code:sub(pos, pos+5) == "__NUM" then
      local ph_end = code:find("__", pos + 4, true)
      if ph_end then
        result_parts[#result_parts+1] = code:sub(pos, ph_end + 1)
        pos = ph_end + 2
        matched = true
      end
    elseif code:sub(pos, pos+6) == "__STR_" then
      local ph_end = code:find("__", pos + 5, true)
      if ph_end then
        result_parts[#result_parts+1] = code:sub(pos, ph_end + 1)
        pos = ph_end + 2
        matched = true
      end
    end

    if not matched then
      local prev = code:sub(pos - 1, pos - 1)

      -- Skip if inside identifier
      if prev:match("[%w_]") then
        result_parts[#result_parts+1] = c
        pos = pos + 1
      else
        -- Try number patterns in order: hex > float > scientific > integer
        local num_str = nil

        -- Hex
        num_str = code:match("^0[xX][%da-fA-F]+", pos)
        -- Float
        if not num_str then num_str = code:match("^%d+%.%d+[eE][+-]?%d+", pos) end
          if not num_str then num_str = code:match("^%d+%.%d+", pos) end
        -- Scientific notation
        if not num_str then num_str = code:match("^%d+[eE][+-]?%d+", pos) end
        -- Integer
        if not num_str then num_str = code:match("^%d+", pos) end

        if num_str then
          -- Make sure we're not matching inside an identifier (e.g. _0xABC)
          if code:match("^%w", pos + #num_str) then
            result_parts[#result_parts+1] = c
            pos = pos + 1
          else
            local n = tonumber(num_str)
            if n and n ~= 0 then
              num_idx = num_idx + 1
              local placeholder = "__NUM" .. num_idx .. "__"
              num_pool[placeholder] = n
              result_parts[#result_parts+1] = placeholder
              pos = pos + #num_str
            else
              result_parts[#result_parts+1] = num_str
              pos = pos + #num_str
            end
          end
        else
          result_parts[#result_parts+1] = c
          pos = pos + 1
        end
      end
    end
  end

  code = table.concat(result_parts)

  for placeholder, n in pairs(num_pool) do
    code = code:gsub(placeholder, encrypt_number(n))
  end

  return code
end


------------------------------------------------------------
-- 指令替换 (Instruction Substitution)
------------------------------------------------------------
local function substitute_instructions(code)
  local lines = split_lines(code)
  local result = {}
  for _, line in ipairs(lines) do
    local trimmed = trim(line)
    local modified = line
    if trimmed ~= "" and not trimmed:match("^%-%-") and
       not trimmed:match("^::") and not trimmed:match("^goto ") then
      local stripped = strip_strings_from_line(trimmed)
      -- a == b -> not(a ~= b)
      if stripped:match("[%a_][%w_]*%s*==%s*[%a_][%w_]*") and not stripped:match("not%(") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("([%a_][%w_%.]*)%s*==(%s*[%a_][%w_%.]*)", function(a, b)
            return string.format("not(%s~= %s)", a, b)
          end)
        end
      end
      -- a ~= b -> not(a == b)
      if stripped:match("[%a_][%w_]*%s*~=%s*[%a_][%w_]*") and not stripped:match("not%(") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("([%a_][%w_%.]*)%s*~=(%s*[%a_][%w_%.]*)", function(a, b)
            return string.format("not(%s== %s)", a, b)
          end)
        end
      end
      -- a > b -> (a - b) > 0
      if stripped:match("[%a_][%w_]*%s*>%s*[%a_][%w_]*") and not stripped:match(">>") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("([%a_][%w_%.]*)%s*>(%s*[%a_][%w_%.]*)", function(a, b)
            return string.format("(%s-%s)>0", a, b)
          end)
        end
      end
      -- a < b -> (b - a) > 0
      if stripped:match("[%a_][%w_]*%s*<%s*[%a_][%w_]*") and not stripped:match("<<") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("([%a_][%w_%.]*)%s*(<)%s*([%a_][%w_%.]*)", function(a, op, b)
            return string.format("(%s-%s)>0", b, a)
          end)
        end
      end
      -- a >= b -> not((b - a) > 0)
      if stripped:match("[%a_][%w_]*%s*>=%s*[%a_][%w_]*") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("([%a_][%w_%.]*)%s*>=(%s*[%a_][%w_%.]*)", function(a, b)
            return string.format("not((%s-%s)>0)", b, a)
          end)
        end
      end
      -- a <= b -> not((a - b) > 0)
      if stripped:match("[%a_][%w_]*%s*<=%s*[%a_][%w_]*") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("([%a_][%w_%.]*)%s<=(%s*[%a_][%w_%.]*)", function(a, b)
            return string.format("not((%s-%s)>0)", a, b)
          end)
        end
      end
      -- a = a + 1 -> a = a - (~0)
      if stripped:match("^[%w_]+%s*=%s*[%w_]+%s*%+%s*1$") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("^(%s*[%w_]+%s*=%s*[%w_]+%s*)%+(%s*1%s*)$", function(l, o) return l .. "-(~0)" end)
        end
      end
      -- a = a - 1 -> a = a + (~0)
      if stripped:match("^[%w_]+%s*=%s*[%w_]+%s*%-%s*1$") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("^(%s*[%w_]+%s*=%s*[%w_]+%s*)%-(%s*1%s*)$", function(l, o) return l .. "+(~0)" end)
        end
      end
      -- a = a * 2 -> a = a << 1
      if stripped:match("^[%w_]+%s*=%s*[%w_]+%s*%*%s*2$") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("^(%s*[%w_]+%s*=%s*[%w_]+%s*)%*(%s*2%s*)$", function(l, o) return l .. "<<1" end)
        end
      end
      -- a = a / 2 -> a = a >> 1
      if stripped:match("^[%w_]+%s*=%s*[%w_]+%s*/%s*2$") then
        if random_int(1, 2) == 1 then
          modified = modified:gsub("^(%s*[%w_]+%s*=%s*[%w_]+%s*)/(%s*2%s*)$", function(l, o) return l .. ">>1" end)
        end
      end
    end
    result[#result + 1] = modified
  end
  return join_lines(result)
end

------------------------------------------------------------
-- 虚假控制流增强 (Advanced Fake Control Flow)
------------------------------------------------------------
local function generate_advanced_predicate()
  local kind = random_int(1, 12)
  if kind == 1 then
    local a, b = random_int(2, 50), random_int(2, 50)
    return string.format("%d==%d", (a+b)*(a+b)-(a-b)*(a-b), 4*a*b), true
  elseif kind == 2 then
    local a, b = random_int(1, 0xFFF), random_int(1, 0xFFF)
    return string.format("0x%X==0x%X", (a|b)+(a&b), a+b), true
  elseif kind == 3 then
    local s = string.rep("x", random_int(1, 20))
    return string.format('#"%s"==%d', s, #s), true
  elseif kind == 4 then
    return string.format("not(%d and not %d)", random_int(1,999), random_int(1,999)), true
  elseif kind == 5 then
    local x = random_int(1, 9999)
    return string.format("(%d or not %d)", x, x), true
  elseif kind == 6 then
    local x = random_int(1, 9999)
    return string.format("(%d and not %d)", x, x), false
  elseif kind == 7 then
    return 'type("")~="number"', true
  elseif kind == 8 then
    return string.format("#tostring(%d)>=1", random_int(1, 9999)), true
  elseif kind == 9 then
    return "(not not nil)", false
  elseif kind == 10 then
    return string.format("#{%d,%d,%d}==3", random_int(1,99), random_int(1,99), random_int(1,99)), true
  elseif kind == 11 then
    return string.format("math.type(%d)==\"integer\"", random_int(1, 9999)), true
  else
    return 'string.find("","")==1', true
  end
end

local function generate_advanced_fake_code()
  local bt = random_int(1, 10)
  local v = "_f" .. random_id(4)
  local lines = {}
  if bt == 1 then
    local arr = "_a" .. random_id(3)
    lines[#lines+1] = string.format("local %s={%d,%d,%d}", arr, random_int(1,99), random_int(1,99), random_int(1,99))
    lines[#lines+1] = string.format("for %s=1,#%s do", v, arr)
    lines[#lines+1] = string.format("  for _%s=%s+1,#%s do", v, v, arr)
    lines[#lines+1] = string.format("    if %s[%s]>%s[_%s] then", arr, v, arr, v)
    lines[#lines+1] = string.format("      %s[%s],%s[_%s]=%s[_%s],%s[%s]", arr, v, arr, v, arr, v, arr, v)
    lines[#lines+1] = "    end"; lines[#lines+1] = "  end"; lines[#lines+1] = "end"
  elseif bt == 2 then
    lines[#lines+1] = string.format("local %s=0x%X", v, random_int(1, 0xFFFF))
    lines[#lines+1] = string.format("for _%s=1,%d do", v, random_int(5, 20))
    lines[#lines+1] = string.format("  %s=((%s<<5)+%s)~(_%s)", v, v, v, v)
    lines[#lines+1] = string.format("  %s=%s&0xFFFFFFFF", v, v)
    lines[#lines+1] = "end"
  elseif bt == 3 then
    local s = "_s" .. random_id(3)
    lines[#lines+1] = string.format("local %s=tostring(0x%X)", s, random_int(0x10000, 0xFFFFF))
    lines[#lines+1] = string.format("local %s=0", v)
    lines[#lines+1] = string.format("for _%s=1,#%s do", v, s)
    lines[#lines+1] = string.format("  %s=%s+string.byte(%s,_%s)", v, v, s, v)
    lines[#lines+1] = "end"
  elseif bt == 4 then
    local fn = "_fn" .. random_id(3)
    lines[#lines+1] = string.format("local function %s(%s)", fn, v)
    lines[#lines+1] = string.format("  if %s<=0 then return 1 end", v)
    lines[#lines+1] = string.format("  return %s(%s-1)*%s", fn, v, v)
    lines[#lines+1] = "end"
  elseif bt == 5 then
    local m = "_m" .. random_id(3)
    lines[#lines+1] = string.format("local %s={}", m)
    lines[#lines+1] = string.format("for %s=0,7 do", v)
    lines[#lines+1] = string.format("  %s[%s+1]=((0x%X>>%s)&1)", m, v, random_int(1, 0xFF), v)
    lines[#lines+1] = "end"
  elseif bt == 6 then
    local a, b = "_fa"..random_id(3), "_fb"..random_id(3)
    lines[#lines+1] = string.format("local %s,%s=0,1", a, b)
    lines[#lines+1] = string.format("for %s=1,%d do", v, random_int(10, 30))
    lines[#lines+1] = string.format("  %s,%s=%s,%s+%s", a, b, b, a, b)
    lines[#lines+1] = "end"
  elseif bt == 7 then
    lines[#lines+1] = string.format("local %s=0xFFFFFFFF", v)
    lines[#lines+1] = string.format("for _%s=0,7 do", v)
    lines[#lines+1] = string.format("  %s=%s~(_%s&0xFF)", v, v, v)
    lines[#lines+1] = "end"
  elseif bt == 8 then
    local tbl = "_t" .. random_id(3)
    lines[#lines+1] = string.format("local %s={}", tbl)
    lines[#lines+1] = string.format("for %s=1,%d do", v, random_int(5, 15))
    lines[#lines+1] = string.format("  %s[%s]=string.char(%d+%s)", tbl, v, random_int(65, 90), v)
    lines[#lines+1] = "end"
  elseif bt == 9 then
    lines[#lines+1] = string.format("local %s=math.sqrt(0x%X)", v, random_int(4, 10000))
    lines[#lines+1] = string.format("%s=math.floor(%s*%d)", v, v, random_int(100, 9999))
    lines[#lines+1] = string.format("%s=%s%%0x%X", v, v, random_int(256, 0xFFFF))
  else
    local a, b, c = "_x"..random_id(3), "_y"..random_id(3), "_z"..random_id(3)
    lines[#lines+1] = string.format("local %s,%s,%s=0x%X,0x%X,0x%X", a, b, c, random_int(1,0xFFFF), random_int(1,0xFFFF), random_int(1,0xFFFF))
    lines[#lines+1] = string.format("%s,%s=%s~%s,%s~%s", a, b, a, b, b, a)
    lines[#lines+1] = string.format("%s,%s=%s~%s,%s~%s", b, c, b, c, c, b)
    lines[#lines+1] = string.format("%s,%s=%s~%s,%s~%s", c, a, c, a, a, c)
  end
  return join_lines(lines)
end

local function inject_advanced_fake_cf(code)
  local lines = split_lines(code)
  local result = {}
  local depth = 0
  local brace_depth = 0  -- track table constructor depth separately
  local insert_every = math.max(4, random_int(4, 8))
  local counter = 0
  for _, line in ipairs(lines) do
    result[#result + 1] = line
    local trimmed = trim(line)
    local opens, closes = calc_depth(line)
    -- Track brace depth separately from control structure depth
    local stripped = trimmed:gsub('%b""', ''):gsub("%b''", ''):gsub('%b[]', '  ')
    for _ in stripped:gmatch('{') do brace_depth = brace_depth + 1 end
    for _ in stripped:gmatch('}') do brace_depth = brace_depth - 1 end
    if brace_depth < 0 then brace_depth = 0 end
    depth = depth + opens - closes
    if depth < 0 then depth = 0 end
    counter = counter + 1
    if depth <= 0 and brace_depth == 0 and counter >= insert_every and trimmed ~= "" and
       not trimmed:match("^%-%-") and
       not trimmed:match("^end") and not trimmed:match("^else") and
       not trimmed:match("^elseif") and not trimmed:match("^local ") and
       not trimmed:match("^::") and not trimmed:match("^goto ") and
       not trimmed:match("^break") and not trimmed:match("^return") and
       not trimmed:match("^while ") and not trimmed:match("^if ") and
       not trimmed:match("^for ") then
      local pred, is_true = generate_advanced_predicate()
      local fake_code = generate_advanced_fake_code()
      if random_int(1, 2) == 1 then
        result[#result + 1] = "if " .. pred .. " then"
        for fl in fake_code:gmatch("[^\n]+") do result[#result + 1] = "  " .. fl end
        local ip, it = generate_advanced_predicate()
        local ifc = generate_advanced_fake_code()
        if it then
          result[#result + 1] = "  if " .. ip .. " then"
          for fl in ifc:gmatch("[^\n]+") do result[#result + 1] = "    " .. fl end
          result[#result + 1] = "  end"
        else
          result[#result + 1] = "  if " .. ip .. " then else"
          for fl in ifc:gmatch("[^\n]+") do result[#result + 1] = "    " .. fl end
          result[#result + 1] = "  end"
        end
        result[#result + 1] = "end"
      else
        if is_true then
          result[#result + 1] = "if " .. pred .. " then"
          for fl in fake_code:gmatch("[^\n]+") do result[#result + 1] = "  " .. fl end
          result[#result + 1] = "end"
        else
          result[#result + 1] = "if " .. pred .. " then else"
          for fl in fake_code:gmatch("[^\n]+") do result[#result + 1] = "  " .. fl end
          result[#result + 1] = "end"
        end
      end
      counter = 0
      insert_every = math.max(4, random_int(4, 8))
    end
  end
  return join_lines(result)
end

------------------------------------------------------------
-- 基本块拆分 (Basic Block Splitting)
------------------------------------------------------------
local function split_basic_blocks(code)
  local lines = split_lines(code)
  local result = {}
  local depth = 0
  local block_lines = {}
  local label_prefix = "_BB" .. random_id(3)
  local in_function = false

  local function flush_block()
    if #block_lines == 0 then return end
    if not in_function or #block_lines <= 2 then
      for _, l in ipairs(block_lines) do result[#result + 1] = l end
      block_lines = {}
      return
    end
    local split_pos = random_int(2, #block_lines - 1)
    local next_label = label_prefix .. random_id(4)
    for i = 1, split_pos do result[#result + 1] = block_lines[i] end
    result[#result + 1] = "goto " .. next_label
    result[#result + 1] = "::" .. next_label .. "::"
    for i = split_pos + 1, #block_lines do result[#result + 1] = block_lines[i] end
    block_lines = {}
  end

  for _, line in ipairs(lines) do
    local trimmed = trim(line)
    local opens, closes = calc_depth(line)
    local prev_depth = depth
    depth = depth + opens - closes
    if depth < 0 then depth = 0 end
    if trimmed:match("^local%s+function%s+") or trimmed:match("^function%s") then
      in_function = true
    end
    if in_function and depth == 0 and closes > 0 then
      in_function = false
    end
    if in_function and depth >= 1 and prev_depth >= 1 and
       trimmed ~= "" and not trimmed:match("^%-%-") and
       not trimmed:match("^::") and not trimmed:match("^goto ") and
       not trimmed:match("^end") and not trimmed:match("^else") and
       not trimmed:match("^elseif") and not trimmed:match("^if ") and
       not trimmed:match("^for ") and not trimmed:match("^while ") and
       not trimmed:match("^repeat ") and not trimmed:match("^return") and
       not trimmed:match("^break") and not trimmed:match("^local%s+function") and
       not trimmed:match("^local%s+[%a_][%w_]*%s*,") then
      block_lines[#block_lines + 1] = line
    else
      flush_block()
      result[#result + 1] = line
    end
  end
  flush_block()
  return join_lines(result)
end

------------------------------------------------------------
-- 控制流平坦化辅助
------------------------------------------------------------
local function split_top_level(code)
  local lines = split_lines(code)
  local statements = {}
  local cur = {}
  local depth = 0
  for _, line in ipairs(lines) do
    local trimmed = trim(line)
    cur[#cur + 1] = line
    if trimmed == "" or trimmed:match("^%-%-") then
    else
      local opens, closes = calc_depth(line)
      local prev_depth = depth
      depth = depth + opens - closes
      if prev_depth == 0 and depth == 0 then
        statements[#statements + 1] = join_lines(cur)
        cur = {}
      elseif depth <= 0 and prev_depth > 0 then
        depth = 0
        statements[#statements + 1] = join_lines(cur)
        cur = {}
      end
    end
  end
  if #cur > 0 then statements[#statements + 1] = join_lines(cur) end
  return statements
end

local function flatten_control_flow(code)
  local dispatch_var = "_S" .. random_id(6)
  local statements = split_top_level(code)

  if #statements < 3 then return code end

  local hoisted = {}
  local remaining = {}

  for i, stmt in ipairs(statements) do
    local first_code = stmt
    for line in stmt:gmatch("[^\n]+") do
      local t = trim(line)
      if t ~= "" and not t:match("^%-%-") then
        first_code = t
        break
      end
    end

    -- Hoist ALL local declarations (single, multi-var, function)
    -- These are safe to hoist because they're pure declarations at top level
    -- (for/while/repeat blocks are captured as single statements, not split)
    if first_code:match("^local%s+") then
      hoisted[#hoisted + 1] = stmt
    else
      remaining[#remaining + 1] = stmt
    end
  end

  if #remaining < 3 then return code end

  local state_nums = {}
  for i = 1, #remaining do
    state_nums[i] = random_int(10000, 99999)
  end

  local ml = {}
  local ind = "  "
  local label = "_L" .. random_id(4)

  for _, h in ipairs(hoisted) do
    for line in h:gmatch("[^\n]+") do ml[#ml + 1] = line end
  end

  ml[#ml + 1] = "local " .. dispatch_var .. " = " .. state_nums[1]
  ml[#ml + 1] = "::" .. label .. "::"
  ml[#ml + 1] = "while true do"

  for i, stmt in ipairs(remaining) do
    ml[#ml + 1] = ind .. "if " .. dispatch_var .. " == " .. state_nums[i] .. " then"
    for line in stmt:gmatch("[^\n]+") do
      ml[#ml + 1] = ind .. "  " .. line
    end
    if i < #remaining then
      ml[#ml + 1] = ind .. "  " .. dispatch_var .. " = " .. state_nums[i + 1]
      ml[#ml + 1] = ind .. "  goto " .. label
    else
      ml[#ml + 1] = ind .. "  break"
    end
    ml[#ml + 1] = ind .. "end"
  end

  ml[#ml + 1] = "end"
  return join_lines(ml)
end

------------------------------------------------------------
-- BCF 虚假控制流块（原有）
------------------------------------------------------------
local function generate_opaque_predicate()
  local kind = random_int(1, 8)
  if kind == 1 then
    local x = random_int(1, 999)
    return string.format("(%d*%d)>=0", x, x), true
  elseif kind == 2 then
    local x = random_int(1, 9999)
    return string.format("(0x%X|0)==0x%X", x, x), true
  elseif kind == 3 then
    local x = random_int(1, 9999)
    return string.format("(0x%X&0x%X)==0x%X", x, x, x), true
  elseif kind == 4 then
    local x = random_int(1, 9999)
    return string.format("(0x%X~0x%X)==0", x, x), true
  elseif kind == 5 then
    return '#("")~=#("x")', true
  elseif kind == 6 then
    return 'type(nil)=="nil"', true
  elseif kind == 7 then
    return 'not true', false
  else
    local x = random_int(1, 999) * 2
    return string.format("(0x%X%%2==0)and(0x%X%%2~=0)", x, x), false
  end
end

local function generate_bcf_code()
  local bt = random_int(1, 6)
  local v = "_j" .. random_id(4)
  local lines = {}

  if bt == 1 then
    lines[#lines + 1] = string.format("local %s = 0", v)
    lines[#lines + 1] = string.format("while %s > 0 do", v)
    lines[#lines + 1] = string.format("  %s = %s - 1", v, v)
    lines[#lines + 1] = string.format("  %s = %s + %s", v, v, v)
    lines[#lines + 1] = "end"
  elseif bt == 2 then
    local fn = "_fn" .. random_id(4)
    lines[#lines + 1] = string.format("local function %s(%s)", fn, v)
    lines[#lines + 1] = string.format("  if %s == nil then return 0 end", v)
    lines[#lines + 1] = string.format("  return %s + %s(%s - 1)", v, fn, v)
    lines[#lines + 1] = "end"
  elseif bt == 3 then
    local tbl = "_t" .. random_id(4)
    lines[#lines + 1] = string.format("local %s = {}", tbl)
    lines[#lines + 1] = string.format("for %s = 1, %d do", v, random_int(3, 10))
    lines[#lines + 1] = string.format("  %s[%s] = %s * %d", tbl, v, v, random_int(2, 99))
    lines[#lines + 1] = "end"
  elseif bt == 4 then
    local a = "_a" .. random_id(4)
    local b = "_b" .. random_id(4)
    lines[#lines + 1] = string.format("local %s, %s = 0x%X, 0x%X", a, b, random_int(1,9999), random_int(1,9999))
    lines[#lines + 1] = string.format("%s = (%s ~ %s) + (%s & %s)", a, a, b, a, b)
    lines[#lines + 1] = string.format("%s = (%s | %s) - (%s ~ %s)", b, a, b, a, b)
  elseif bt == 5 then
    local s = "_s" .. random_id(4)
    lines[#lines + 1] = string.format("local %s = tostring(0x%X)", s, random_int(1, 99999))
    lines[#lines + 1] = string.format("%s = %s .. %s", s, s, s)
    lines[#lines + 1] = string.format("%s = #%s", s, s)
  else
    lines[#lines + 1] = string.format("local _x%d, _y%d, _z%d = 0x%X, 0x%X, 0x%X",
      random_int(1,999), random_int(1,999), random_int(1,999),
      random_int(1,0xFFFF), random_int(1,0xFFFF), random_int(1,0xFFFF))
  end

  return join_lines(lines)
end

local function inject_bcf(code)
  local lines = split_lines(code)
  local result = {}
  local insert_every = math.max(3, random_int(3, 7))
  local counter = 0
  local depth = 0
  local brace_depth = 0

  for _, line in ipairs(lines) do
    result[#result + 1] = line
    local trimmed = trim(line)

    local opens, closes = calc_depth(line)
    -- Track brace depth separately
    local stripped = trimmed:gsub('%b""', ''):gsub("%b''", ''):gsub('%b[]', '  ')
    for _ in stripped:gmatch('{') do brace_depth = brace_depth + 1 end
    for _ in stripped:gmatch('}') do brace_depth = brace_depth - 1 end
    if brace_depth < 0 then brace_depth = 0 end
    depth = depth + opens - closes
    if depth < 0 then depth = 0 end

    counter = counter + 1

    -- Only inject at top level, not inside table constructors
    if depth <= 0 and brace_depth == 0 and counter >= insert_every and trimmed ~= "" and
       not trimmed:match("^%-%-") and
       not trimmed:match("^end") and not trimmed:match("^else") and
       not trimmed:match("^elseif") and not trimmed:match("^local ") and
       not trimmed:match("^::") and not trimmed:match("^goto ") and
       not trimmed:match("^break") and not trimmed:match("^return") and
       not trimmed:match("^while ") and
       not trimmed:match("^if ") then

      local pred, is_true = generate_opaque_predicate()
      local bcf = generate_bcf_code()

      if is_true then
        result[#result + 1] = "if " .. pred .. " then"
        for bl in bcf:gmatch("[^\n]+") do result[#result + 1] = "  " .. bl end
        result[#result + 1] = "else"
        result[#result + 1] = "  -- pass"
        result[#result + 1] = "end"
      else
        result[#result + 1] = "if " .. pred .. " then"
        result[#result + 1] = "  -- pass"
        result[#result + 1] = "else"
        for bl in bcf:gmatch("[^\n]+") do result[#result + 1] = "  " .. bl end
        result[#result + 1] = "end"
      end

      counter = 0
      insert_every = math.max(3, random_int(3, 7))
    end
  end

  return join_lines(result)
end

------------------------------------------------------------
-- 变量名混淆
------------------------------------------------------------
local LUA_KEYWORDS = {
  ["and"]=true, ["break"]=true, ["do"]=true, ["else"]=true, ["elseif"]=true,
  ["end"]=true, ["false"]=true, ["for"]=true, ["function"]=true, ["goto"]=true,
  ["if"]=true, ["in"]=true, ["local"]=true, ["nil"]=true, ["not"]=true,
  ["or"]=true, ["repeat"]=true, ["return"]=true, ["then"]=true, ["true"]=true,
  ["until"]=true, ["while"]=true,
}

local BUILTIN_NAMES = {
  ["print"]=true, ["type"]=true, ["tostring"]=true, ["tonumber"]=true,
  ["pairs"]=true, ["ipairs"]=true, ["next"]=true, ["select"]=true,
  ["unpack"]=true, ["require"]=true, ["pcall"]=true, ["xpcall"]=true,
  ["error"]=true, ["assert"]=true, ["setmetatable"]=true, ["getmetatable"]=true,
  ["rawget"]=true, ["rawset"]=true, ["rawequal"]=true, ["rawlen"]=true,
  ["collectgarbage"]=true, ["dofile"]=true, ["load"]=true, ["loadfile"]=true,
  ["module"]=true, ["setfenv"]=true, ["getfenv"]=true,
  ["string"]=true, ["table"]=true, ["math"]=true, ["io"]=true,
  ["os"]=true, ["debug"]=true, ["coroutine"]=true, ["package"]=true,
  ["_G"]=true, ["_ENV"]=true, ["self"]=true, ["arg"]=true,
  ["__index"]=true, ["__newindex"]=true, ["__add"]=true, ["__sub"]=true,
  ["__mul"]=true, ["__div"]=true, ["__mod"]=true, ["__pow"]=true,
  ["__unm"]=true, ["__concat"]=true, ["__len"]=true, ["__eq"]=true,
  ["__lt"]=true, ["__le"]=true, ["__call"]=true, ["__tostring"]=true,
  ["__gc"]=true, ["__mode"]=true, ["__metatable"]=true,
}

local function mangle_variables(code)
  local var_map = {}
  local used_names = {}

  for name in code:gmatch("[%a_][%w_]*") do used_names[name] = true end

  for name in code:gmatch("local%s+([%a_][%w_]*)") do
    if not LUA_KEYWORDS[name] and not BUILTIN_NAMES[name] and not var_map[name] then
      local new_name
      repeat new_name = "_0x" .. random_id(6) until not used_names[new_name]
      var_map[name] = new_name
      used_names[new_name] = true
    end
  end

  for name in code:gmatch("local%s+function%s+([%a_][%w_]*)") do
    if not LUA_KEYWORDS[name] and not BUILTIN_NAMES[name] and not var_map[name] then
      local new_name
      repeat new_name = "_0x" .. random_id(6) until not used_names[new_name]
      var_map[name] = new_name
      used_names[new_name] = true
    end
  end

  for params in code:gmatch("function%s*%(([^)]*)%)") do
    for param in params:gmatch("([%a_][%w_]*)") do
      if not LUA_KEYWORDS[param] and not BUILTIN_NAMES[param] and param ~= "self" and not var_map[param] then
        local new_name
        repeat new_name = "_0x" .. random_id(6) until not used_names[new_name]
        var_map[param] = new_name
        used_names[new_name] = true
      end
    end
  end

  for name in code:gmatch("for%s+([%a_][%w_]*)%s*=") do
    if not LUA_KEYWORDS[name] and not BUILTIN_NAMES[name] and not var_map[name] then
      local new_name
      repeat new_name = "_0x" .. random_id(6) until not used_names[new_name]
      var_map[name] = new_name
      used_names[new_name] = true
    end
  end

  for old_name, new_name in pairs(var_map) do
    -- Use Lua frontier patterns for proper word boundary matching
    -- %f[%a_] matches position where prev char is NOT [%a_] and next char IS [%a_]
    -- %f[%A_] matches position where prev char is NOT [%A_] (i.e., IS word char)
    local escaped = old_name:gsub(".", function(c)
      if c:match("[%a_%d]") then return c else return "%" .. c end
    end)
    -- Left frontier: %f[%a_%d] prevents matching after digits (hex numbers)
    -- Right frontier: %f[%A_] prevents matching before letters/underscores
    local pattern = "%f[%a_%d]" .. escaped .. "%f[%A_]"
    code = code:gsub(pattern, new_name)
  end

  return code
end

------------------------------------------------------------
-- 垃圾注释注入
------------------------------------------------------------
local function inject_junk_comments(code)
  local junk = {
    "-- TODO: optimize this later",
    "-- FIXME: potential issue here",
    "-- HACK: temporary workaround",
    "-- NOTE: do not remove",
    "-- BUG: investigate when possible",
    "-- REVIEW: check performance",
    "-- DEPRECATED: will be removed",
    "-- COMPAT: lua 5.1+ required",
    "-- INTERNAL: auto-generated",
    "-- RESERVED: for future use",
    "-- HOTFIX: patch applied",
    "-- REFACTOR: needs cleanup",
    "-- PERF: benchmark pending",
    "-- TEST: coverage needed",
  }

  local lines = split_lines(code)
  local result = {}
  local counter = 0
  local depth = 0

  for _, line in ipairs(lines) do
    result[#result + 1] = line
    local trimmed = trim(line)

    local opens, closes = calc_depth(line)
    depth = depth + opens - closes
    if depth < 0 then depth = 0 end

    counter = counter + 1
    if depth <= 1 and counter >= random_int(4, 10) and trimmed ~= "" then
      -- 随机插入 1-2 条注释
      result[#result + 1] = junk[random_int(1, #junk)]
      if random_int(1, 3) == 1 then
        result[#result + 1] = junk[random_int(1, #junk)]
      end
      counter = 0
    end
  end

  return join_lines(result)
end

------------------------------------------------------------
-- 混淆头部
------------------------------------------------------------
local function add_header(code)
  local header = string.format([=[
-- ============================================================
-- Obfuscated by Lua Obfuscator v%s
-- Features: CFE | NumEnc | BCF | VarMangle | StrEnc
--          | InstrSub | AdvFakeCF | BBSplit
-- Date: %s
-- ============================================================
-- WARNING: This code has been obfuscated.
-- Reverse engineering is discouraged.
-- ============================================================

]=], VERSION, os.date("%Y-%m-%d %H:%M:%S"))
  return header .. code
end

------------------------------------------------------------
-- 主混淆流程
------------------------------------------------------------
local function obfuscate(code, vm_module)
  -- Random seed: use os.time+os.clock if available, fallback to math.random
  local ok_t, t = pcall(os.time)
  local ok_c, c = pcall(os.clock)
  if ok_t and ok_c then
    math.randomseed(math.floor(t + c * 1000))
  else
    math.randomseed(42)
  end

  -- VM 字节码虚拟化（最先执行，将源码编译为加密字节码）
  -- 其他混淆只作用于 VM 包装代码，不影响字节码
  local vm_applied = false
  if Config.vm_protect then
    local vm = vm_module or dofile("vm_protect.lua")
    local result, vm_err = vm.protect(code)
    if result then
      code = result
      vm_applied = true
    else
      if io.stderr then io.stderr:write("VM保护失败: " .. tostring(vm_err) .. "\n") end
    end
  end

  -- 保护字符串
  code = extract_strings(code)

  -- 变量名混淆
  if Config.variable_mangling then
    code = mangle_variables(code)
  end

  -- 指令替换
  if Config.instruction_substitution then
    code = substitute_instructions(code)
  end

  -- 常量数字加密
  if Config.constant_encryption then
    code = obfuscate_numbers(code)
  end

  -- 虚假控制流增强（在平坦化之前注入，会被平坦化一并处理）
  if Config.advanced_fake_cf then
    code = inject_advanced_fake_cf(code)
  end

  -- 控制流平坦化
  if Config.control_flow_flattening then
    code = flatten_control_flow(code)
  end

  -- BCF 虚假控制流
  if Config.bogus_control_flow then
    code = inject_bcf(code)
  end

  -- 基本块拆分（在函数体内做，平坦化后函数体不受影响）
  if Config.basic_block_splitting then
    code = split_basic_blocks(code)
  end

  -- 恢复字符串
  code = restore_strings(code)

  -- 垃圾注释
  if Config.junk_comments then
    code = inject_junk_comments(code)
  end

  -- 头部
  code = add_header(code)

  return code
end

------------------------------------------------------------
-- 控制台交互
------------------------------------------------------------
local feature_names = {
  [1] = { key = "control_flow_flattening",  name = "控制流平坦化",        desc = "CFE" },
  [2] = { key = "constant_encryption",      name = "常量数字加密",        desc = "NumEnc" },
  [3] = { key = "bogus_control_flow",       name = "BCF 虚假块",         desc = "BCF" },
  [4] = { key = "variable_mangling",        name = "变量名混淆",         desc = "VarMangle" },
  [5] = { key = "string_encryption",        name = "字符串加密",         desc = "StrEnc" },
  [6] = { key = "junk_comments",            name = "垃圾注释",           desc = "Junk" },
  [7] = { key = "instruction_substitution", name = "指令替换",           desc = "InstrSub" },
  [8] = { key = "advanced_fake_cf",         name = "虚假控制流增强",     desc = "AdvFakeCF" },
  [9] = { key = "basic_block_splitting",    name = "基本块拆分",         desc = "BBSplit" },
  [10] = { key = "vm_protect",              name = "VM 字节码虚拟化",   desc = "VM" },
}

local function print_banner()
  print([[
╔══════════════════════════════════════════════════════════╗
║             Lua Obfuscator v]] .. VERSION .. [[                          ║
║                                                          ║
║  功能列表：                                              ║
║    1. 控制流平坦化 (Control Flow Flattening)              ║
║    2. 常量数字加密 (Constant Number Encryption)           ║
║    3. BCF 虚假控制流块 (Bogus Control Flow)               ║
║    4. 变量名混淆 (Variable Name Mangling)                ║
║    5. 字符串加密 (String Encryption)                      ║
║    6. 垃圾注释注入 (Junk Comments)                        ║
║    7. 指令替换 (Instruction Substitution)                 ║
║    8. 虚假控制流增强 (Advanced Fake Control Flow)         ║
║    9. 基本块拆分 (Basic Block Splitting)                  ║
║   10. VM 字节码虚拟化 (VM Bytecode Protection)           ║
╚══════════════════════════════════════════════════════════╝
]])
end

local function print_status()
  print("\n┌───────────────────────────────────────────────┐")
  print("│              当前功能状态                      │")
  print("├─────┬──────────────────────┬──────────┬────────┤")
  print("│ 编号 │ 功能名称              │ 标识     │ 状态   │")
  print("├─────┼──────────────────────┼──────────┼────────┤")
  for i, feat in ipairs(feature_names) do
    local status = Config[feat.key] and "✅ ON " or "❌ OFF"
    print(string.format("│  %d  │ %-20s │ %-8s │ %s │", i, feat.name, feat.desc, status))
  end
  print("└─────┴──────────────────────┴──────────┴────────┘")
end

local function toggle_feature(num)
  local feat = feature_names[num]
  if feat then
    Config[feat.key] = not Config[feat.key]
    local status = Config[feat.key] and "开启 ✅" or "关闭 ❌"
    print(string.format("\n  [%s] 已%s", feat.name, status))
  else
    print("\n  无效的编号！")
  end
end

local function enable_all()
  for _, feat in ipairs(feature_names) do Config[feat.key] = true end
  print("\n  所有功能已开启 ✅")
end

local function disable_all()
  for _, feat in ipairs(feature_names) do Config[feat.key] = false end
  print("\n  所有功能已关闭 ❌")
end

local function read_file(path)
  local f, err = io.open(path, "r")
  if not f then return nil, "无法打开文件: " .. tostring(err) end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_file(path, content)
  local f, err = io.open(path, "w")
  if not f then return nil, "无法写入文件: " .. tostring(err) end
  f:write(content)
  f:close()
  return true
end

local function do_obfuscate(input_path, output_path)
  print("\n  读取输入文件: " .. input_path)
  local code, err = read_file(input_path)
  if not code then print("  ❌ " .. err); return end

  print("  原始代码长度: " .. #code .. " 字节")
  print("  开始混淆...")

  local ok, result = pcall(obfuscate, code)
  if not ok then print("  ❌ 混淆失败: " .. tostring(result)); return end

  print("  混淆后长度: " .. #result .. " 字节")
  print("  膨胀比: " .. string.format("%.1fx", #result / #code))

  local wok, werr = write_file(output_path, result)
  if not wok then print("  ❌ " .. werr); return end

  print("  ✅ 输出已保存到: " .. output_path)
end

local function interactive_input()
  print("\n  请输入 Lua 代码（输入 'END' 结束）：")
  print("  ─────────────────────────────────────")
  local lines = {}
  while true do
    io.write("  > ")
    local line = io.read()
    if not line or line == "END" then break end
    lines[#lines + 1] = line
  end
  if #lines == 0 then print("  ❌ 未输入任何代码"); return end
  local code = join_lines(lines)
  print("\n  混淆中...\n")
  local ok, result = pcall(obfuscate, code)
  if not ok then print("  ❌ 混淆失败: " .. tostring(result)); return end
  print("  ═══════════════ 混淆结果 ═══════════════")
  print(result)
  print("  ════════════════════════════════════════")
end

local function run_demo()
  print("\n  🎯 运行演示模式...\n")

  local demo_code = [[
-- 示例：斐波那契数列
local function fibonacci(n)
  if n <= 1 then
    return n
  end
  local a, b = 0, 1
  for i = 2, n do
    local temp = a + b
    a = b
    b = temp
  end
  return b
end

-- 计算前 10 个斐波那契数
for i = 0, 9 do
  local result = fibonacci(i)
  print("fib(" .. i .. ") = " .. result)
end

-- 一些常量计算
local max_retries = 5
local timeout_ms = 3000
local pi_approx = 3.14159
local secret_key = 0xDEADBEEF

print("Max retries: " .. max_retries)
print("Timeout: " .. timeout_ms .. "ms")
print("Pi: " .. pi_approx)
print("Key: " .. string.format("0x%X", secret_key))
]]

  print("  ═══════════════ 原始代码 ═══════════════")
  print(demo_code)
  print("  ════════════════════════════════════════\n")

  print_status()
  print("\n  开始混淆...\n")

  local ok, result = pcall(obfuscate, demo_code)
  if not ok then print("  ❌ 混淆失败: " .. tostring(result)); return end

  print("  原始长度: " .. #demo_code .. " 字节")
  print("  混淆后长度: " .. #result .. " 字节")
  print("  膨胀比: " .. string.format("%.1fx", #result / #demo_code))
  print("\n  ═══════════════ 混淆结果 ═══════════════")
  print(result)
  print("  ════════════════════════════════════════")

  local out_path = "demo_output.lua"
  write_file(out_path, result)
  print("\n  ✅ 演示结果已保存到: " .. out_path)
end

------------------------------------------------------------
-- CLI
------------------------------------------------------------
local function print_help()
  print([[Lua Obfuscator v]] .. VERSION .. [[

用法:
  lua obfuscator.lua                      交互式控制台
  lua obfuscator.lua -i input.lua         文件模式（输出到 input_obf.lua）
  lua obfuscator.lua -i in.lua -o out.lua 指定输入输出
  lua obfuscator.lua --demo               运行演示
  lua obfuscator.lua -h                   显示帮助

CLI 选项（禁用特定功能）:
  --no-cfe      禁用控制流平坦化
  --no-num      禁用常量数字加密
  --no-bcf      禁用 BCF 虚假块
  --no-var      禁用变量名混淆
  --no-str      禁用字符串加密
  --no-junk     禁用垃圾注释
  --no-instr    禁用指令替换
  --no-advbcf   禁用虚假控制流增强
  --no-bbsplit  禁用基本块拆分
  --vm          启用 VM 字节码虚拟化
]])
end

------------------------------------------------------------
-- 交互式主循环
------------------------------------------------------------
local function interactive_loop()
  print_banner()
  print_status()

  while true do
    io.write([[
┌─────────────────────────────────────────┐
│  命令：                                  │
│    1-10: 切换对应功能                     │
│    a   : 开启全部功能                     │
│    d   : 禁用全部功能                     │
│    s   : 查看当前状态                     │
│    f   : 混淆文件                         │
│    e   : 输入代码并混淆                   │
│    demo: 运行演示                         │
│    q   : 退出                             │
└─────────────────────────────────────────┘
> ]])

    local cmd = io.read()
    if not cmd then break end
    cmd = trim(cmd)

    if cmd == "q" or cmd == "quit" or cmd == "exit" then
      print("\n  👋 再见！")
      break
    elseif cmd == "a" or cmd == "all" then
      enable_all(); print_status()
    elseif cmd == "d" or cmd == "disable" then
      disable_all(); print_status()
    elseif cmd == "s" or cmd == "status" then
      print_status()
    elseif cmd == "f" or cmd == "file" then
      io.write("\n  输入文件路径: ")
      local input_path = io.read()
      if input_path and input_path ~= "" then
        local output_path = input_path:gsub("%.lua$", "") .. "_obf.lua"
        io.write("  输出文件路径 [" .. output_path .. "]: ")
        local custom = io.read()
        if custom and custom ~= "" then output_path = custom end
        do_obfuscate(input_path, output_path)
      end
    elseif cmd == "e" or cmd == "edit" or cmd == "input" then
      interactive_input()
    elseif cmd == "demo" then
      run_demo()
    elseif tonumber(cmd) and tonumber(cmd) >= 1 and tonumber(cmd) <= #feature_names then
      toggle_feature(tonumber(cmd)); print_status()
    else
      print("\n  ❓ 未知命令: " .. cmd)
    end
  end
end

------------------------------------------------------------
-- 入口
------------------------------------------------------------
local function main()
  local args = {}
  for i = 1, #arg do args[#args + 1] = arg[i] end

  local opts = { mode = "interactive", input = nil, output = nil }

  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "-h" or a == "--help" then
      opts.mode = "help"
    elseif a == "-i" or a == "--input" then
      i = i + 1; opts.input = args[i]; opts.mode = "file"
    elseif a == "-o" or a == "--output" then
      i = i + 1; opts.output = args[i]
    elseif a == "--demo" then
      opts.mode = "demo"
    elseif a == "--no-cfe" then Config.control_flow_flattening = false
    elseif a == "--no-num" then Config.constant_encryption = false
    elseif a == "--no-bcf" then Config.bogus_control_flow = false
    elseif a == "--no-var" then Config.variable_mangling = false
    elseif a == "--no-str" then Config.string_encryption = false
    elseif a == "--no-junk" then Config.junk_comments = false
    elseif a == "--no-instr" then Config.instruction_substitution = false
    elseif a == "--no-advbcf" then Config.advanced_fake_cf = false
    elseif a == "--no-bbsplit" then Config.basic_block_splitting = false
    elseif a == "--vm" then Config.vm_protect = true
    end
    i = i + 1
  end

  if opts.mode == "help" then
    print_help()
  elseif opts.mode == "demo" then
    run_demo()
  elseif opts.mode == "file" then
    if not opts.input then print("❌ 请指定输入文件: -i <input.lua>"); os.exit(1) end
    local output = opts.output or (opts.input:gsub("%.lua$", "") .. "_obf.lua")
    do_obfuscate(opts.input, output)
  else
    interactive_loop()
  end
end

------------------------------------------------------------
-- 模块 API（供 Web 端通过 Fengari 调用）
------------------------------------------------------------
local M = {}

--- 混淆代码（字符串输入/输出）
-- @param code string 源代码
-- @param options table|nil 可选配置覆盖，如 {vm_protect=true, variable_mangling=false}
-- @param vm_module table|nil 可选 vm_protect 模块（避免 dofile）
-- @return string 混淆后的代码
function M.obfuscate_code(code, options, vm_module)
  -- 保存原始 Config
  local saved = {}
  for k, v in pairs(Config) do saved[k] = v end

  -- 应用选项覆盖
  if options then
    for k, v in pairs(options) do
      if Config[k] ~= nil then Config[k] = v end
    end
  end

  local ok, result = pcall(obfuscate, code, vm_module)

  -- 恢复 Config
  for k, v in pairs(saved) do Config[k] = v end

  if not ok then error(result) end
  return result
end

--- 获取当前配置
function M.get_config()
  local c = {}
  for k, v in pairs(Config) do c[k] = v end
  return c
end

--- 设置配置
function M.set_config(options)
  for k, v in pairs(options) do
    if Config[k] ~= nil then Config[k] = v end
  end
end

M.VERSION = VERSION

-- 当被 require 时返回模块，当直接运行时执行 main()
-- 通过检查是否有 -i 参数判断是否为 CLI 模式
local _is_cli = false
if arg then
  for _, v in ipairs(arg) do
    if v == "-i" or v == "--input" or v == "--help" or v == "-h" or v == "--demo" then
      _is_cli = true
      break
    end
  end
end

if _is_cli then
  main()
end

return M
