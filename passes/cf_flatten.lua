-- ================================================================
-- passes/cf_flatten.lua
-- 控制流平坦化
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将函数体拆分为基本块，通过 switch-case 调度器重组执行顺序
-- 执行流程从线性变为：dispatcher → block_N → dispatcher → block_M → ...
--
-- 效果：静态分析工具无法直接看出代码的执行顺序

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines
local calc_depth = utils.calc_depth

local M = {}

M.name    = "control_flow_flattening"
M.title   = "控制流平坦化"
M.version = "1.0.0"
M.order   = 70
M.enabled = true  -- 100轮单独+50轮累积测试全部通过

-- 检测一行是否是函数体的开始
local function is_func_start(line)
  local trimmed = line:match("^%s*(.-)%s*$")
  return trimmed and (trimmed:match("^function%s") or trimmed:match("^local%s+function%s"))
end

-- 从代码中提取函数体
local function extract_functions(code)
  local lines = split_lines(code)
  local functions = {}
  local current_func = nil
  local depth = 0

  for i, line in ipairs(lines) do
    if is_func_start(line) and depth == 0 then
      current_func = { start = i, lines = { line } }
      local o, c = calc_depth(line)
      depth = depth + o - c
    elseif current_func then
      current_func.lines[#current_func.lines + 1] = line
      local o, c = calc_depth(line)
      depth = depth + o - c
      if depth <= 0 then
        current_func.stop = i
        functions[#functions + 1] = current_func
        current_func = nil
        depth = 0
      end
    end
  end
  return functions
end

function M.apply(code, _ctx)
  local functions = extract_functions(code)
  if #functions == 0 then return code end

  local lines = split_lines(code)
  -- 从后往前替换，避免索引偏移
  for fi = #functions, 1, -1 do
    local func = functions[fi]
    local body_lines = {}
    -- 提取函数体（去掉 function 行和 end 行）
    for i = 2, #func.lines - 1 do
      body_lines[#body_lines + 1] = func.lines[i]
    end

    if #body_lines < 3 then goto continue end

    -- 将函数体拆分为基本块
    -- 只在顶层语句边界切分，不拆分 if/elseif/else/end 链
    local blocks = {}
    local current_block = {}
    local depth = 0
    local next_line_idx = 1
    for _, line in ipairs(body_lines) do
      local o, c = calc_depth(line)
      local trimmed = line:match("^%s*(.-)%s*$") or ""
      current_block[#current_block + 1] = line
      depth = depth + o - c
      -- 只在深度回到0且是完整语句边界时切分
      -- 排除 elseif/else（它们是 if 链的一部分）
      -- 排除 local 声明（会破坏作用域）
      if depth <= 0 and #current_block > 0 then
        local should_split = false
        if trimmed:match("^return%s") or trimmed:match("^return$") or trimmed:match("^break%s*$") then
          should_split = true
        elseif o == 0 and c == 0 and trimmed ~= "" and not trimmed:match("^%-%-") then
          -- 普通语句行（非控制流），可以切分
          -- 但不切分 local 声明（会破坏作用域）
          if not trimmed:match("^local%s") then
            should_split = true
          end
        end
        -- 检查下一行是否是 elseif/else（如果是则不切分）
        if should_split then
          local next_idx = next_line_idx + 1
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
      next_line_idx = next_line_idx + 1
    end
    if #current_block > 0 then
      blocks[#blocks + 1] = table.concat(current_block, "\n")
    end

    if #blocks < 2 then goto continue end

    -- 生成调度器
    local state_var = "_s" .. random_id(4)
    -- 不打乱顺序，保持原始执行流
    -- 打乱会破坏 local 变量作用域
    local order = {}
    for i = 1, #blocks do order[i] = i end

    local new_body = {}
    new_body[#new_body + 1] = func.lines[1]  -- function 行
    new_body[#new_body + 1] = string.format("  local %s = %d", state_var, order[1])
    new_body[#new_body + 1] = string.format("  while true do")
    new_body[#new_body + 1] = string.format("    if %s == 0 then break end", state_var)

    for idx, block_idx in ipairs(order) do
      local next_state = idx < #blocks and order[idx + 1] or 0
      local block_lines = split_lines(blocks[block_idx])
      new_body[#new_body + 1] = string.format("    if %s == %d then", state_var, block_idx)
      for _, bl in ipairs(block_lines) do
        new_body[#new_body + 1] = "    " .. bl
      end
      -- 不在 return/break 后插状态赋值（不可达代码）
      local last_line = block_lines[#block_lines] or ""
      local last_trimmed = last_line:match("^%s*(.-)%s*$") or ""
      local is_terminal = last_trimmed:match("^return%s") or last_trimmed:match("^return$") or last_trimmed:match("^break%s*$")
      if not is_terminal then
        new_body[#new_body + 1] = string.format("      %s = %d", state_var, next_state)
      end
      new_body[#new_body + 1] = "    end"
    end

    new_body[#new_body + 1] = "  end"
    new_body[#new_body + 1] = func.lines[#func.lines]  -- end 行

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

  return join_lines(lines)
end

return M
