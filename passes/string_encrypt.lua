-- ================================================================
-- passes/string_encrypt.lua
-- 字符串加密
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- 将代码中的字符串字面量替换为运行时解密调用
-- 支持 XOR、ROT13、表驱动三种编码方式，随机选择
--
-- 注意：字符串的提取/恢复由 string_pool 处理，
-- 本 Pass 仅控制是否启用加密（与 Pipeline 解耦）

local string_pool = require("passes.string_pool")

local M = {}

M.name    = "string_encryption"
M.title   = "字符串加密"
M.description = "将字符串常量替换为运行时解密调用，增加静态分析难度"
M.version = "1.0.0"
M.order   = 20

function M.apply(code, _ctx)
  -- 字符串提取+恢复由 obfuscator.lua 主流程处理
  -- 此 Pass 仅作为 Pipeline 中的占位，用于配置管理
  -- 如果禁用此 Pass，主流程将跳过字符串加密步骤
  return code
end

return M
