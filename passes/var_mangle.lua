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
M.version = "1.2.0"
M.order   = 30
M.config  = {
  whitelist = {}, -- names that must not be renamed
}

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
      local is_scientific_e = false
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
          is_scientific_e = true
        end
      end
      if not is_scientific_e then
        local start = pos
        pos = pos + 1
        while pos <= len and is_id_char(code:byte(pos)) do
          pos = pos + 1
        end
        local name = code:sub(start, pos - 1)
        n = n + 1
        ids[n] = { name = name, start = start, stop = pos - 1 }
      end

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

-- 收集表键名（避免把表字段键当变量重命名）
local function collect_table_keys(code)
  -- 1. Lua metamethods: always preserve
  local keys = {
    __index=true, __newindex=true, __add=true, __sub=true, __mul=true,
    __div=true, __mod=true, __pow=true, __unm=true, __len=true,
    __eq=true, __lt=true, __le=true, __concat=true, __call=true,
    __tostring=true, __gc=true, __ipairs=true, __pairs=true,
    __len=true, __pairs=true,
  }
  local i = 1
  local len = #code
  while i <= len do
    local b = code:byte(i)
    -- Skip string placeholders
    if b == 95 and code:sub(i, i+3) == "__ST" then
      local ep = code:find("__", i+5, true)
      i = ep and (ep+2) or (i+1)
    -- Skip comments
    elseif b == 45 and i < len and code:byte(i+1) == 45 then
      local nl = code:find("\n", i+2, true)
      i = nl and (nl+1) or (len+1)
    -- Skip string literals
    elseif b == 34 or b == 39 then
      local q = b; i = i + 1
      while i <= len do
        if code:byte(i) == 92 then i = i + 2
        elseif code:byte(i) == q then i = i + 1; break
        else i = i + 1 end
      end
    -- Skip [expr] in table literals
    elseif b == 91 then
      i = i + 1
      local depth = 1
      while i <= len and depth > 0 do
        local cb = code:byte(i)
        if cb == 91 then depth = depth + 1; i = i + 1
        elseif cb == 93 then depth = depth - 1; i = i + 1
        elseif cb == 34 or cb == 39 then
          local q2 = cb; i = i + 1
          while i <= len do
            if code:byte(i) == 92 then i = i + 2
            elseif code:byte(i) == q2 then i = i + 1; break
            else i = i + 1 end
          end
        else i = i + 1 end
      end
    -- Table literal: { key = value }
    elseif b == 123 then
      i = i + 1
      local depth = 1
      while i <= len and depth > 0 do
        local cb = code:byte(i)
        if cb == 123 then depth = depth + 1; i = i + 1
        elseif cb == 125 then depth = depth - 1; i = i + 1
        elseif cb == 34 or cb == 39 then
          local q3 = cb; i = i + 1
          while i <= len do
            if code:byte(i) == 92 then i = i + 2
            elseif code:byte(i) == q3 then i = i + 1; break
            else i = i + 1 end
          end
        elseif (cb >= 65 and cb <= 90) or (cb >= 97 and cb <= 122) or cb == 95 then
          local start = i
          i = i + 1
          while i <= len do
            local ib = code:byte(i)
            if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
          end
          local key = code:sub(start, i - 1)
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if code:byte(i) == 61 then
            keys[key] = true
            i = i + 1
          end
        else i = i + 1 end
      end
    -- Dot access: xxx.fieldname
    elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
      local start = i
      i = i + 1
      while i <= len do
        local ib = code:byte(i)
        if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
      end
      local idname = code:sub(start, i-1)
      -- Skip Lua keywords
      local kw = {["local"]=1,["function"]=1,["if"]=1,["for"]=1,["while"]=1,["return"]=1,["end"]=1,["then"]=1,["do"]=1,["else"]=1,["or"]=1,["and"]=1,["not"]=1,["in"]=1,["repeat"]=1,["until"]=1,["break"]=1,["goto"]=1}
      if not kw[idname] then
        while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
        if code:byte(i) == 46 then
          i = i + 1
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if (code:byte(i) >= 65 and code:byte(i) <= 90) or (code:byte(i) >= 97 and code:byte(i) <= 122) or code:byte(i) == 95 then
            local fstart = i
            i = i + 1
            while i <= len do
              local ib = code:byte(i)
              if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
            end
            local fieldname = code:sub(fstart, i-1)
            keys[fieldname] = true
          end
        end
      end
    else
      i = i + 1
    end
  end
  return keys
end


local function normalize_whitelist(wl)
  local out = {}
  if type(wl) ~= "table" then return out end
  for k, v in pairs(wl) do
    if type(k) == "number" and type(v) == "string" and v ~= "" then
      out[v] = true
    elseif type(k) == "string" and k ~= "" and v then
      out[k] = true
    end
  end
  return out
end

function M.apply(code, ctx)
  ctx = ctx or {}
  local cfg = ctx.config or {}
  local whitelist = normalize_whitelist(cfg.whitelist)

  -- 跳过 VM 保护的代码块（vm_protect / vm_function 生成的代码不应该被混淆）
  -- 标记行：-- @vm (protected)（下一行为 -- VM Protected Code (op-pool + char-pool)，再下一行为 do）
  -- 块结束：与起始 do 配对的独立行 end（该 end 在行首，后面只有可选分号/空白）
  local vm_blocks = {}
  local vm_placeholders = {}
  local block_idx = 1

  local LINE_BREAK = string.byte("\n")
  local SPACE = string.byte(" ")
  local TAB = string.byte("\t")
  local SEMI = string.byte(";")
  local RET = string.byte("\r")

  -- 从字节位置查找下一个换行（返回行结束位置 pos；行内容为 src[line_start .. pos-1]）
  local function scan_eol(src, pos, len)
    local i = pos
    while i <= len do
      local c = src:byte(i)
      if c == LINE_BREAK then return i, i + 1 end
      if c == 13 then return i, i + 1 end  -- \r\n 或 \r
      i = i + 1
    end
    return len + 1, len + 1
  end

  -- 提取所有 VM 保护代码块
  local function extract_vm_blocks(src)
    local result = {}
    local pos = 1
    local len = #src

    -- 辅助函数：按单词边界计数关键字
    local function count_word(s, w)
      local n = 0
      local p = 1
      while p <= #s do
        local i, j = s:find(w, p, true)
        if not i then break end
        local before_ok = (i == 1) or not s:sub(i-1, i-1):match("[%w_]")
        local after_ok = (j == #s) or not s:sub(j+1, j+1):match("[%w_]")
        if before_ok and after_ok then n = n + 1 end
        p = j + 1
      end
      return n
    end

    while pos <= len do
      -- 查找标记行 "-- @vm (protected)"（行首起匹配）
      local marker_start = src:find("-- @vm (protected)", pos, true)
      if not marker_start then
        result[#result + 1] = src:sub(pos)
        break
      end

      -- 块应从标记行的行首开始（含整行）
      local bol = marker_start
      while bol > 1 and (src:byte(bol - 1) == SPACE or src:byte(bol - 1) == TAB
             or src:byte(bol - 1) == RET) do
        bol = bol - 1
      end
      if marker_start > pos then
        result[#result + 1] = src:sub(pos, bol - 1)
      end

      -- 定位到标记行行尾，从标记行的下一行开始扫描块结束
      local _, after_marker_eol = scan_eol(src, bol, len)
      local depth = 0
      local block_end = nil
      local i = after_marker_eol

      while i <= len do
        local eol, next_line = scan_eol(src, i, len)
        local line = src:sub(i, eol - 1)
        -- 去掉行首空白，便于比对内容
        local line_start = 1
        while line_start <= #line do
          local c = line:byte(line_start)
          if c == SPACE or c == TAB or c == RET then line_start = line_start + 1 else break end
        end
        local t = line:sub(line_start)

        -- 跟踪所有 Lua 块结构：计入所有创建块的 keyword
        local openers = 0
        local closers = 0

        openers = openers + count_word(t, "function")
        openers = openers + count_word(t, "for")
        openers = openers + count_word(t, "while")
        openers = openers + count_word(t, "if")
        openers = openers + count_word(t, "elseif")
        openers = openers + count_word(t, "repeat")
        -- 注意：不要 count_word(t, "do") 或 count_word(t, "then")
        -- 因为 for/while 和 if/elseif 已经各计一次，do/then 是同一块的组成部分
        -- 仅当行首只有 do 关键字时算独立块
        if t == "do" or t == "do;" then
          openers = openers + 1
        end

        closers = closers + count_word(t, "end")
        closers = closers + count_word(t, "until")

        depth = depth + openers - closers
        if closers > 0 and depth == 0 then
          block_end = eol
          break
        end
        i = next_line
      end

      if not block_end then
        -- 找不到配对 end（不完整块），原样保留剩余内容并退出
        result[#result + 1] = src:sub(bol)
        break
      end

      local vm_code = src:sub(bol, block_end - 1)
      local placeholder = "__VM_BLOCK_" .. block_idx .. "__"
      vm_blocks[placeholder] = vm_code
      vm_placeholders[#vm_placeholders + 1] = { pos = #table.concat(result) + 1, code = vm_code }

      result[#result + 1] = "\n" .. placeholder .. "\n"
      block_idx = block_idx + 1

      pos = block_end
    end

    return table.concat(result)
  end

  -- 还原 VM 代码块
  local function restore_vm_blocks(code)
    for placeholder, vm_code in pairs(vm_blocks) do
      code = code:gsub(placeholder, vm_code)
    end
    return code
  end

  -- 提取 VM 块，用占位符替换
  code = extract_vm_blocks(code)

  -- 收集需要替换的变量名
  local table_keys = collect_table_keys(code)
  local var_map, ids = collect_local_vars(code, table_keys)

  -- 白名单：不参与重命名
  for name in pairs(whitelist) do
    var_map[name] = nil
  end

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

  -- 还原 VM 代码块
  code = restore_vm_blocks(code)

  return code
end

return M
