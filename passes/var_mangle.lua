-- ================================================================
-- passes/var_mangle.lua
-- 变量名混淆
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将局部变量名替换为无意义的随机标识符
--
-- 性能优化:
--   - 一次扫描收集所有变量名(不是多次 gmatch)
--   - 用 byte 级别检查代替模式匹配
--   - 替换时用位置表批量处理,避免重复扫描

local utils = require("passes.utils")
local random_id = utils.random_id
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local is_comment = utils.is_comment

local M = {}

M.name    = "variable_mangling"
M.title   = "变量名混淆"
M.version = "1.0.1"
M.order   = 30

-- Lua 保留字和常用全局变量（不能被替换）
local RESERVED = {}
for _, w in ipairs({
  "and","break","do","else","elseif","end","false","for","function","goto",
  "if","in","local","nil","not","or","repeat","return","then","true","until","while",
  "self","print","require","pcall","xpcall","type","tostring","tonumber",
  "pairs","ipairs","table","string","math","io","os","coroutine","debug",
  "package","rawset","rawget","setmetatable","getmetatable","error","assert",
  "select","unpack","collectgarbage","dofile","load","loadfile","next",
  "rawequal","rawlen","module",
}) do RESERVED[w] = true end

local BYTE_DOT = string.byte(".")

-- 检查字符是否是数字
local function is_digit(b)
  return b >= 48 and b <= 57
end

-- 检查字符是否是标识符首字符 [a-zA-Z_] 
local function is_id_start(b)
  return (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95
end

-- 检查字符是否是标识符后续字符 [a-zA-Z0-9_]
local function is_id_char(b)
  return is_id_start(b) or (b >= 48 and b <= 57)
end

-- 从代码中提取所有标识符位置
-- 返回: { {name, start, end}, ... }
local function scan_identifiers(code)
  local ids = {}
  local n = 0
  local pos = 1
  local len = #code

  while pos <= len do
    local b = code:byte(pos)

    -- 跳过字符串占位符
    if b == 95 and code:sub(pos, pos + 3) == "__ST" then
      local end_pos = code:find("__", pos + 5, true)
      if end_pos then
        pos = end_pos + 2
      else
        pos = pos + 1
      end

    -- 跳过注释
    elseif b == 45 and pos < len and code:byte(pos + 1) == 45 then
      local nl = code:find("\n", pos + 2, true)
      pos = nl and (nl + 1) or (len + 1)

    -- 跳过字符串(已替换为占位符,不会到这里)

    -- 标识符
    elseif is_id_start(b) then
      -- 跳过科学计数法中的 e/E(如 1.5e-3)
      if (b == 101 or b == 69) and pos > 1 then  -- 'e' or 'E'
        local prev = code:byte(pos - 1)
        if is_digit(prev) or prev == BYTE_DOT then
          -- 这是科学计数法的一部分,不是标识符
          pos = pos + 1
          -- 跳过指数部分的 +/-
          if pos <= len then
            local sign = code:byte(pos)
            if sign == 43 or sign == 45 then pos = pos + 1 end  -- '+' or '-'
          end
          -- 跳过指数数字
          while pos <= len and is_digit(code:byte(pos)) do
            pos = pos + 1
          end
          goto continue_scan
        end
      end
      local start = pos
      pos = pos + 1
      while pos <= len and is_id_char(code:byte(pos)) do
        pos = pos + 1
      end
      local name = code:sub(start, pos - 1)
      n = n + 1
      ids[n] = { name = name, start = start, stop = pos - 1 }
      ::continue_scan::

    else
      pos = pos + 1
    end
  end

  return ids
end

-- 从代码中提取 local 声明的变量名
local function collect_local_vars(code, table_keys)
  local var_map = {}
  local ids = scan_identifiers(code)

  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      -- 检查上下文:是否是 local 声明
      -- local xxx = / local function xxx / local xxx, yyy
      local before = code:sub(math.max(1, id.start - 20), id.start - 1)
      -- 检查前面是否有 "local " 或 "local\t"
      if before:match("local%s+$") or before:match("local%s+function%s+$") then
        var_map[name] = true
      end
      -- 检查多变量声明 local a, b, c
      if before:match(",%s*$") then
        -- 往前找 local
        local local_pos = before:find("local%s+", 1, true)
        if local_pos then
          var_map[name] = true
        end
      end
    end
  end

  -- 函数参数 function(x, y)
  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      local before = code:sub(math.max(1, id.start - 5), id.start - 1)
      if before:match("%(%s*$") or before:match(",%s*$") then
        -- 往前找 function
        local ctx = code:sub(math.max(1, id.start - 50), id.start - 1)
        if ctx:match("function%s*[%w_.:]*%s*$") or ctx:match("function%s*[%w_.:]*%s*%([^)]*$") then
          var_map[name] = true
        end
      end
    end
  end

  -- for 循环变量 for i = / for k, v in
  for i, id in ipairs(ids) do
    local name = id.name
    if not RESERVED[name] and not name:match("^__") and not var_map[name] and not table_keys[name] then
      local before = code:sub(math.max(1, id.start - 10), id.start - 1)
      if before:match("for%s+$") or before:match(",%s*$") then
        var_map[name] = true
      end
    end
  end

  return var_map, ids
end

-- ????????????????????????
local function collect_table_keys(code)
  local keys = {}
  local i = 1
  local len = #code
  while i <= len do
    local b = code:byte(i)
    -- ????????
    if b == 34 or b == 39 then
      local q = b; i = i + 1
      while i <= len do
        if code:byte(i) == 92 then i = i + 2
        elseif code:byte(i) == q then i = i + 1; break
        else i = i + 1 end
      end
    elseif b == 45 and i < len and code:byte(i+1) == 45 then
      local nl = code:find("\n", i+2, true)
      i = nl and (nl+1) or (len+1)
    -- ??????
    elseif b == 123 then
      i = i + 1
      local depth = 1
      while i <= len and depth > 0 do
        local cb = code:byte(i)
        if cb == 123 then depth = depth + 1; i = i + 1
        elseif cb == 125 then depth = depth - 1; i = i + 1
        elseif cb == 34 or cb == 39 then
          local q = cb; i = i + 1
          while i <= len do
            if code:byte(i) == 92 then i = i + 2
            elseif code:byte(i) == q then i = i + 1; break
            else i = i + 1 end
          end
        elseif cb == 91 then
          i = i + 1
          while i <= len and code:byte(i) ~= 93 do i = i + 1 end
          i = i + 1
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if code:byte(i) == 61 then
            i = i + 1
            while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          end
        elseif (cb >= 65 and cb <= 90) or (cb >= 97 and cb <= 122) or cb == 95 then
          local start = i
          i = i + 1
          while i <= len do
            local ib = code:byte(i)
            if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
          end
          local key = code:sub(start, i - 1)
          -- ?? = ?
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if code:byte(i) == 61 then
            keys[key] = true
            i = i + 1
          end
        else
          i = i + 1
        end
      end
    else
      i = i + 1
    end
  end
  return keys
end

function M.apply(code, _ctx)
  -- 收集需要替换的变量名
  local table_keys = collect_table_keys(code)
  local var_map, ids = collect_local_vars(code, table_keys)

  -- 生成替换名
  local rename_map = {}
  for name in pairs(var_map) do
    rename_map[name] = "_" .. random_id(6)
  end

  -- 构建 segment 数组，一次 concat 完成替换
  local segments = {}
  local sn = 0
  local last_pos = 1

  for _, id in ipairs(ids) do
    local new_name = rename_map[id.name]
    if new_name then
      if id.start > last_pos then
        sn = sn + 1
        segments[sn] = code:sub(last_pos, id.start - 1)
      end
      sn = sn + 1
      segments[sn] = new_name
      last_pos = id.stop + 1
    end
  end
  -- 尾部
  if last_pos <= #code then
    sn = sn + 1
    segments[sn] = code:sub(last_pos)
  end

  if sn > 0 then
    code = table.concat(segments)
  end

  return code
end

return M
