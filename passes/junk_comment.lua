-- ================================================================
-- passes/junk_comment.lua
-- 垃圾注释注入
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 在代码中插入大量无意义的注释，增加文件体积和阅读噪音
-- 注释内容为随机生成的「看似有意义」的文本

local utils = require("passes.utils")
local random_id = utils.random_id
local random_int = utils.random_int
local split_lines = utils.split_lines
local join_lines = utils.join_lines

local M = {}

M.name    = "junk_comments"
M.title   = "垃圾注释注入"
M.version = "1.0.0"
M.order   = 100

-- 看起来像正常注释的模板
local TEMPLATES = {
  "-- TODO: refactor this later",
  "-- FIXME: potential edge case",
  "-- HACK: workaround for %s",
  "-- NOTE: do not remove",
  "-- XXX: this is suspicious",
  "-- REVIEW: check performance",
  "-- BUG: intermittent failure in %s",
  "-- OPTIMIZE: can be improved",
  "-- DEPRECATED: use %s instead",
  "-- SEE: %s",
  "-- WARNING: side effect",
  "-- %s initialized",
  "-- %s v%d.%d.%d",
  "-- called from %s",
  "-- %s: %dms timeout",
  "-- retry count: %d",
  "-- buffer size: %d",
  "-- %s handler registered",
  "-- offset: 0x%X",
  "-- magic: 0x%X",
}

local WORDS = {
  "handler", "callback", "buffer", "stream", "context",
  "manager", "service", "worker", "scheduler", "dispatcher",
  "adapter", "proxy", "factory", "builder", "validator",
  "parser", "encoder", "decoder", "cache", "pool",
}

local function random_comment()
  local tpl = TEMPLATES[random_int(1, #TEMPLATES)]
  local word = WORDS[random_int(1, #WORDS)]
  local ok, result = pcall(string.format, tpl, word, random_int(1,9), random_int(0,9), random_int(0,99), random_int(0,0xFFFF))
  if ok then return result end
  return "-- " .. random_id(12)
end

function M.apply(code, _ctx)
  local lines = split_lines(code)
  local result = {}
  local depth = 0

  for _, line in ipairs(lines) do
    result[#result + 1] = line

    -- 在顶层语句之间插入注释
    local trimmed = line:match("^%s*(.-)%s*$") or ""
    if trimmed ~= "" and not trimmed:match("^%-%-") then
      if random_int(1, 3) == 1 then
        result[#result + 1] = random_comment()
      end
    end
  end

  return join_lines(result)
end

return M
