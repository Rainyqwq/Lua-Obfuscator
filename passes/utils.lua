-- ================================================================
-- passes/utils.lua
-- 通用工具函数库
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 供所有 Pass 共用的基础功能
--
-- 性能注意事项：
--   - split_lines / join_lines 是热路径，已做优化
--   - 高频调用的函数避免在内部创建闭包
--   - 模式匹配尽量用 %f[] 前瞻断言代替 %a/%A

local M = {}

function M.trim(s)
  return s:match("^%s*(.-)%s*$")
end

-- 分割字符串为行数组（比 gmatch 更快，减少迭代次数）
function M.split_lines(s)
  local lines = {}
  local n = 0
  local pos = 1
  local len = #s
  while pos <= len do
    local nl = s:find("\n", pos, true)
    n = n + 1
    if nl then
      lines[n] = s:sub(pos, nl - 1)
      pos = nl + 1
    else
      lines[n] = s:sub(pos)
      break
    end
  end
  -- 去掉末尾空行
  if n > 1 and lines[n] == "" then
    lines[n] = nil
  end
  return lines
end

-- 合并行为字符串
function M.join_lines(lines)
  return table.concat(lines, "\n")
end

-- 生成随机标识符（直接拼接字节，避免 string.sub 循环）
local CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
local CHAR_BYTES = {}
for i = 1, #CHARS do CHAR_BYTES[i] = CHARS:byte(i) end
local NCHARS = #CHAR_BYTES

function M.random_id(len)
  len = len or 8
  local bytes = {}
  for i = 1, len do
    bytes[i] = CHAR_BYTES[math.random(1, NCHARS)]
  end
  return string.char(table.unpack(bytes))
end

function M.random_int(min, max)
  return math.random(min, max)
end

-- 计算一行代码的嵌套深度变化
-- 返回: opens, closes
function M.calc_depth(line)
  local trimmed = M.trim(line)
  if trimmed == "" or trimmed:byte(1) == 45 then return 0, 0 end  -- '-' = 45
  -- 去掉字符串内容后再计算
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

-- 去掉字符串字面量内容，保留引号结构
function M.strip_strings_from_line(line)
  return line:gsub('%b""', '""'):gsub("%b''", "''"):gsub("%[%[.-%]%]", "[[]]")
end

-- 安全的 gsub（处理替换字符串中的特殊字符）
function M.gsub_safe(s, pattern, repl)
  local ok, result = pcall(string.gsub, s, pattern, repl)
  if ok then return result end
  return s
end

-- 快速检查一行是否是注释（避免 gmatch 开销）
function M.is_comment(line)
  local i = 1
  local len = #line
  while i <= len do
    local b = line:byte(i)
    if b == 32 or b == 9 then  -- 空格或tab
      i = i + 1
    elseif b == 45 and i < len and line:byte(i + 1) == 45 then  -- '--'
      return true
    else
      return false
    end
  end
  return false
end

-- 快速检查一行是否为空
function M.is_empty(line)
  return line:match("^%s*$") ~= nil
end

return M
