-- ================================================================
-- passes/bb_split.lua
-- 基本块拆分 (Basic Block Splitting)
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将函数体中的顺序语句拆分为基本块，用 goto/label 连接
-- 物理顺序可打乱（仅限无局部变量的块），执行顺序通过 goto 保持不变
-- 在 goto 和 label 之间插入独立作用域的死代码块，增加 CFG 复杂度

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines

local M = {}

M.name    = "basic_block_splitting"
M.title   = "基本块拆分"
M.version = "1.0.0"
M.order   = 90
M.enabled = false

-- 修正版深度计算：else 不计为 open，elseif 行的 then 不计为 open
-- 原 utils.calc_depth 将 else 计为 +1 open，导致 if-else-end 深度不归零
local function calc_depth_safe(line)
  local trimmed = line:match("^%s*(.-)%s*$") or ""
  if trimmed == "" or trimmed:byte(1) == 45 then return 0, 0 end
  local stripped = trimmed:gsub('%b""', ''):gsub("%b''", ''):gsub('%b[]', '  ')
  local opens, closes = 0, 0
  local starts_with_elseif = trimmed:match("^elseif%s") ~= nil
  for _ in stripped:gmatch('%f[%a]function%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]do%f[%A]') do opens = opens + 1 end
  if not starts_with_elseif then
    for _ in stripped:gmatch('%f[%a]then%f[%A]') do opens = opens + 1 end
  end
  for _ in stripped:gmatch('%f[%a]repeat%f[%A]') do opens = opens + 1 end
  for _ in stripped:gmatch('{') do opens = opens + 1 end
  for _ in stripped:gmatch('%f[%a]end%f[%A]') do closes = closes + 1 end
  for _ in stripped:gmatch('%f[%a]until%f[%A]') do closes = closes + 1 end
  for _ in stripped:gmatch('}') do closes = closes + 1 end
  return opens, closes
end

local function is_func_start(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  return trimmed and (trimmed:match("^function%s") or trimmed:match("^local%s+function%s"))
end

local function extract_functions(code)
  local lines = split_lines(code)
  local functions = {}
  local current_func = nil
  local depth = 0
  for i, line in ipairs(lines) do
    if is_func_start(line) and depth == 0 then
      current_func = { start = i, lines = { line } }
      local o, c = calc_depth_safe(line)
      depth = depth + o - c
    elseif current_func then
      current_func.lines[#current_func.lines + 1] = line
      local o, c = calc_depth_safe(line)
      depth = depth + o - c
      if depth <= 0 then
        current_func.stop = i
        functions[#functions + 1] = current_func
        current_func = nil
        depth = 0
      end
    end
  end
  return functions, lines
end

-- 生成独立作用域的死代码块
local function gen_dead_block(indent)
  local v = "_d" .. random_id(3)
  local n = random_int(0, 0xFFFF)
  local ops = { "+", "-", "*" }
  local op = ops[random_int(1, #ops)]
  local m = random_int(0, 0xFF)
  return string.format("%sdo\n%s  local %s = %d\n%s  %s = %s %s %d\n%send",
    indent, indent, v, n, indent, v, v, op, m, indent)
end

-- 检查块中是否包含 local 声明
local function has_locals(block_text)
  for line in block_text:gmatch("[^\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    if trimmed:match("^local%s") then return true end
  end
  return false
end

-- 收集函数体中所有 local 变量名
local function collect_local_names(body_lines)
  local names = {}
  for _, line in ipairs(body_lines) do
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    local fn = trimmed:match("^local%s+function%s+([%a_][%w_]*)")
    if fn then
      names[fn] = true
    else
      local rest = trimmed:match("^local%s+(.+)$")
      if rest then
        local vars = rest:match("^([^=]+)")
        if vars then
          for name in vars:gmatch("([%a_][%w_]*)") do
            names[name] = true
          end
        end
      end
    end
  end
  return names
end

-- 检查文本中是否引用了某个变量名（带词边界检查）
local function references_name(text, name)
  local pos = 1
  while true do
    local s = text:find(name, pos, true)
    if not s then return false end
    local e = s + #name - 1
    local before = s > 1 and text:sub(s - 1, s - 1) or " "
    local after = e < #text and text:sub(e + 1, e + 1) or " "
    if not before:match("[%w_]") and not after:match("[%w_]") then
      return true
    end
    pos = s + 1
  end
end

-- 检查块是否引用了函数体中的 local 变量
local function references_locals(block_text, local_names)
  for name in pairs(local_names) do
    if references_name(block_text, name) then
      return true
    end
  end
  return false
end

-- 检查块是否以 return/break 终结
local function is_terminal(block_text)
  local block_lines = split_lines(block_text)
  local last = block_lines[#block_lines] or ""
  local trimmed = last:match("^%s*(.-)%s*$") or ""
  return trimmed:match("^return%s") ~= nil or
         trimmed:match("^return$") ~= nil or
         trimmed:match("^break%s*$") ~= nil
end

-- 将 return 语句包裹在 do...end 中，使其不再是 block 的最后一条语句
-- 这样 goto/label 可以跟在 return 后面而不产生语法错误
local function wrap_return_line(line)
  local ws = line:match("^(%s*)") or ""
  local trimmed = line:match("^%s*(.-)%s*$") or ""
  if trimmed:match("^return%s") or trimmed:match("^return$") then
    return ws .. "do " .. trimmed .. " end"
  end
  return line
end

function M.apply(code, _ctx)
  local functions, lines = extract_functions(code)
  if #functions == 0 then return code end

  for fi = #functions, 1, -1 do
    local func = functions[fi]
    local body_lines = {}
    for i = 2, #func.lines - 1 do
      body_lines[#body_lines + 1] = func.lines[i]
    end
    if #body_lines < 4 then goto continue end

    local local_names = collect_local_names(body_lines)

    -- 将函数体拆分为基本块
    local blocks = {}
    local current_block = {}
    local depth = 0
    for idx, line in ipairs(body_lines) do
      local o, c = calc_depth_safe(line)
      local trimmed = line:match("^%s*(.-)%s*$") or ""
      current_block[#current_block + 1] = line
      depth = depth + o - c
      if depth <= 0 and #current_block > 0 then
        local should_split = false
        if trimmed:match("^return%s") or trimmed:match("^return$") or trimmed:match("^break%s*$") then
          should_split = true
        elseif o == 0 and c == 0 and trimmed ~= "" and not trimmed:match("^%-%-") then
          if not trimmed:match("^local%s") then
            should_split = true
          end
        end
        -- 如果下一行是 elseif/else，不切分（保持 if 链完整）
        if should_split then
          local next_idx = idx + 1
          if next_idx <= #body_lines then
            local next_trimmed = body_lines[next_idx]:match("^%s*(.-)%s*$") or ""
            if next_trimmed:match("^elseif%s") or next_trimmed:match("^else%s*$") or next_trimmed:match("^else%s+[^%s]") then
              should_split = false
            end
          end
        end
        if should_split then
          blocks[#blocks + 1] = table.concat(current_block, "\n")
          current_block = {}
        end
      end
    end
    if #current_block > 0 then
      blocks[#blocks + 1] = table.concat(current_block, "\n")
    end

    if #blocks < 2 then goto continue end

    -- 从第一个块推断缩进
    local indent = "  "
    for _, bl in ipairs(split_lines(blocks[1])) do
      local m = bl:match("^(%s*)")
      if m and #m > 0 then indent = m break end
    end

    -- 判断各块是否可移动（无 local 声明且不引用 local 变量）
    local movable = {}
    for i = 1, #blocks do
      movable[i] = not has_locals(blocks[i]) and not references_locals(blocks[i], local_names)
    end

    -- 随机打乱可移动块的物理顺序（仅相邻交换）
    local phys_order = {}
    for i = 1, #blocks do phys_order[i] = i end
    local si = 1
    while si < #phys_order do
      local a = phys_order[si]
      local b = phys_order[si + 1]
      if movable[a] and movable[b] and random_int(1, 2) == 1 then
        phys_order[si] = b
        phys_order[si + 1] = a
        si = si + 2
      else
        si = si + 1
      end
    end

    local lp = "_bb" .. random_id(4)
    local end_label = lp .. "_end"

    -- 构建 goto/label 链
    local new_body = {}
    new_body[#new_body + 1] = func.lines[1]
    new_body[#new_body + 1] = string.format("%sgoto %s_%d", indent, lp, 1)

    for j = 1, #phys_order do
      local block_idx = phys_order[j]
      new_body[#new_body + 1] = string.format("%s::%s_%d::", indent, lp, block_idx)
      local blines = split_lines(blocks[block_idx])
      for bi, bl in ipairs(blines) do
        if bi == #blines then
          new_body[#new_body + 1] = wrap_return_line(bl)
        else
          new_body[#new_body + 1] = bl
        end
      end
      if block_idx < #blocks then
        if not is_terminal(blocks[block_idx]) then
          new_body[#new_body + 1] = string.format("%sgoto %s_%d", indent, lp, block_idx + 1)
          if random_int(1, 3) <= 2 then
            new_body[#new_body + 1] = gen_dead_block(indent)
          end
        end
      else
        if not is_terminal(blocks[block_idx]) then
          new_body[#new_body + 1] = string.format("%sgoto %s", indent, end_label)
        end
      end
    end

    new_body[#new_body + 1] = string.format("%s::%s::", indent, end_label)
    new_body[#new_body + 1] = func.lines[#func.lines]

    -- 替换原函数
    local new_lines = {}
    for i = 1, #lines do
      if i == func.start then
        for _, nl in ipairs(new_body) do
          new_lines[#new_lines + 1] = nl
        end
      elseif i > func.start and i <= func.stop then
        -- 跳过原函数体
      else
        new_lines[#new_lines + 1] = lines[i]
      end
    end
    lines = new_lines

    ::continue::
  end

  local result = join_lines(lines)

  -- 编译检查：无法编译则回退
  local ok, fn = pcall(load, result)
  if not ok or not fn then
    return code
  end

  return result
end

return M
