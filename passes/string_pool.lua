-- ================================================================
-- passes/string_pool.lua
-- 字符串池：提取和恢复代码中的字符串字面量
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
--
-- 工作流程：
--   1. extract: 扫描代码，将字符串替换为 __STR0__, __STR1__... 占位符
--   2. 各 Pass 处理不含字符串的安全代码
--   3. restore: 将占位符还原为加密后的字符串表达式
--
-- 性能优化：
--   - 使用 find + sub 代替 gmatch 回调（减少闭包创建）
--   - 批量替换占位符（一次性 gsub，不是逐个替换）

local utils = require("passes.utils")
local random_int = utils.random_int
local random_id = utils.random_id

local M = {}

M.pool = {}

-- 处理 Lua 转义序列（恢复字符串时调用）
function M.process_escapes(s)
  local result = {}
  local n = 0
  local i = 1
  local len = #s
  while i <= len do
    local c = s:byte(i)
    if c == 92 and i < len then  -- '\\'
      local nc = s:byte(i + 1)
      n = n + 1
      if nc == 110 then result[n] = "\n"       -- 'n'
      elseif nc == 116 then result[n] = "\t"    -- 't'
      elseif nc == 114 then result[n] = "\r"    -- 'r'
      elseif nc == 92 then result[n] = "\\"     -- '\\'
      elseif nc == 34 then result[n] = '"'      -- '"'
      elseif nc == 39 then result[n] = "'"      -- "'"
      elseif nc == 48 then result[n] = "\0"     -- '0'
      else result[n] = string.char(92, nc) end
      i = i + 2
    else
      n = n + 1
      result[n] = string.char(c)
      i = i + 1
    end
  end
  return table.concat(result)
end

-- XOR 编码（最快）
function M.encode_xor(str)
  local key = random_int(1, 255)
  local bytes = {}
  local n = #str
  for i = 1, n do
    bytes[i] = str:byte(i) ~ key
  end
  return string.format(
    '(function() local _k=%d; local _d={%s}; local _r={}; for _i=1,#_d do _r[_i]=string.char(_d[_i]~_k) end; return table.concat(_r) end)()',
    key, table.concat(bytes, ",")
  )
end

-- ROT13 + char code
function M.encode_rot13(str)
  local parts = {}
  local n = #str
  for i = 1, n do
    local b = str:byte(i)
    local a = random_int(1, 200)
    parts[i] = string.format("string.char(%d-%d)", b + a, a)
  end
  return "(" .. table.concat(parts, "..") .. ")"
end

-- 表驱动解码
function M.encode_table(str)
  local key = random_int(1, 255)
  local bytes = {}
  local n = #str
  for i = 1, n do
    bytes[i] = str:byte(i) ~ key
  end
  local fn = "_d" .. random_id(3)
  return string.format(
    '(function() local %s={%s}; local _k=%d; local _r={}; for _i=1,#%s do _r[_i]=string.char(%s[_i]~_k) end; return table.concat(_r) end)()',
    fn, table.concat(bytes, ","), key, fn, fn
  )
end

-- 从代码中提取字符串字面量
function M.extract(code)
  M.pool = {}
  local idx = 0

  -- 长字符串 [[ ... ]]（先处理，避免被短字符串匹配干扰）
  code = code:gsub("%[%[(.-)%]%]", function(s)
    local key = "__STR" .. idx .. "__"
    M.pool[key] = { raw = s, kind = "long" }
    idx = idx + 1
    return key
  end)

  -- 双引号（手动扫描处理转义引号）
  do
    local result = {}
    local pos = 1
    local len = #code
    local last_end = 1
    while pos <= len do
      local q = code:find('"', pos, true)
      if not q then break end
      -- 找到字符串结束位置（处理转义引号）
      local j = q + 1
      while j <= len do
        local c = code:byte(j)
        if c == 92 then j = j + 2  -- 跳过转义字符
        elseif c == 34 then j = j + 1; break  -- 找到结束引号
        else j = j + 1 end
      end
      local s = code:sub(q + 1, j - 2)
      -- 跳过已提取的占位符
      if not s:find("__STR%d+__") then
        local key = "__STR" .. idx .. "__"
        M.pool[key] = { raw = s, kind = "double" }
        result[#result + 1] = code:sub(last_end, q - 1)
        result[#result + 1] = key
        last_end = j
        idx = idx + 1
      end
      pos = j
    end
    if #result > 0 then
      result[#result + 1] = code:sub(last_end)
      code = table.concat(result)
    end
  end

  -- 单引号（手动扫描处理转义引号）
  do
    local result = {}
    local pos = 1
    local len = #code
    local last_end = 1
    while pos <= len do
      local q = code:find("'", pos, true)
      if not q then break end
      local j = q + 1
      while j <= len do
        local c = code:byte(j)
        if c == 92 then j = j + 2
        elseif c == 39 then j = j + 1; break
        else j = j + 1 end
      end
      local s = code:sub(q + 1, j - 2)
      if not s:find("__STR%d+__") then
        local key = "__STR" .. idx .. "__"
        M.pool[key] = { raw = s, kind = "single" }
        result[#result + 1] = code:sub(last_end, q - 1)
        result[#result + 1] = key
        last_end = j
        idx = idx + 1
      end
      pos = j
    end
    if #result > 0 then
      result[#result + 1] = code:sub(last_end)
      code = table.concat(result)
    end
  end

  return code
end

-- 将占位符替换为加密后的字符串表达式
-- 使用一次性 gsub 代替逐个替换
function M.restore(code)
  if not next(M.pool) then return code end

  -- 构建替换表
  local replacements = {}
  for key, info in pairs(M.pool) do
    local processed = M.process_escapes(info.raw)
    local method = random_int(1, 3)
    local encrypted
    if method == 1 then
      encrypted = M.encode_xor(processed)
    elseif method == 2 then
      encrypted = M.encode_rot13(processed)
    else
      encrypted = M.encode_table(processed)
    end
    replacements[key] = encrypted
  end

  -- 一次性替换所有占位符
  -- 按 key 长度降序排序，避免短 key 匹配到长 key 的前缀
  local keys = {}
  for k in pairs(replacements) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return #a > #b end)

  for _, key in ipairs(keys) do
    local safe_key = key:gsub("(%W)", "%%%1")
    code = code:gsub(safe_key, replacements[key])
  end

  return code
end

-- 将占位符替换为原始字符串（不加密）
function M.restore_raw(code)
  if not next(M.pool) then return code end

  local keys = {}
  for k in pairs(M.pool) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return #a > #b end)

  for _, key in ipairs(keys) do
    local info = M.pool[key]
    local safe_key = key:gsub("(%W)", "%%%1")
    local quote = info.kind == "double" and '"' or "'"
    -- 转义替换字符串中的 % 字符
    local escaped = info.raw:gsub("%%", "%%%%")
    code = code:gsub(safe_key, quote .. escaped .. quote)
  end

  return code
end

return M
