#!/usr/bin/env lua
-- ================================================================
-- vm.lua
-- VM 字节码编译器/解释器
--
-- Author: Rainy_qwq
-- URL:    https://github.com/Rainyqwq/Lua-Obfuscator
-- License: MIT
-- ================================================================
-- Lua version compatibility check
if _VERSION then
  local ver = tonumber(_VERSION:match("Lua (%d+%.%d+)") or "0")
  if ver < 5.3 then
    local ok, bit_lib = pcall(require, "bit") or pcall(require, "bit32")
    if ok and bit_lib then
      rawset(_G, "_bxor", bit_lib.bxor)
      rawset(_G, "_band", bit_lib.band)
      rawset(_G, "_bor",  bit_lib.bor)
      rawset(_G, "_bnot", bit_lib.bnot)
      rawset(_G, "_shl",  bit_lib.lshift)
      rawset(_G, "_shr",  bit_lib.rshift)
    end
  end
end

local VERSION = "2.8.2"

------------------------------------------------------------
-- 自定义指令集定义
------------------------------------------------------------
local OPC = {
  NOP      = 0,
  LOADK    = 1,   -- R[A] = K[Bx]
  LOADBOOL = 2,   -- R[A] = B; if C then pc++
  LOADNIL  = 3,   -- R[A..A+B] = nil
  MOVE     = 4,   -- R[A] = R[B]
  GETGLOBAL= 5,   -- R[A] = G[K[Bx]]
  SETGLOBAL= 6,   -- G[K[Bx]] = R[A]
  GETTABLE = 7,   -- R[A] = R[B][R[C]]
  SETTABLE = 8,   -- R[A][R[B]] = R[C]
  NEWTABLE = 9,   -- R[A] = {}
  ADD      = 10,  -- R[A] = R[B] + R[C]
  SUB      = 11,  -- R[A] = R[B] - R[C]
  MUL      = 12,  -- R[A] = R[B] * R[C]
  DIV      = 13,  -- R[A] = R[B] / R[C]
  IDIV     = 55,  -- R[A] = R[B] // R[C]
  MOD      = 14,  -- R[A] = R[B] % R[C]
  POW      = 15,  -- R[A] = R[B] ^ R[C]
  BAND     = 16,  -- R[A] = R[B] & R[C]
  BOR      = 17,  -- R[A] = R[B] | R[C]
  BXOR     = 18,  -- R[A] = R[B] ~ R[C]
  SHL      = 19,  -- R[A] = R[B] << R[C]
  SHR      = 20,  -- R[A] = R[B] >> R[C]
  UNM      = 21,  -- R[A] = -R[B]
  BNOT     = 22,  -- R[A] = ~R[B]
  NOT      = 23,  -- R[A] = not R[B]
  LEN      = 24,  -- R[A] = #R[B]
  CONCAT   = 25,  -- R[A] = R[B] .. R[C]
  EQ       = 26,  -- if (R[A]==R[B]) ~= C then pc++
  LT       = 27,  -- if (R[A]<R[B]) ~= C then pc++
  LE       = 28,  -- if (R[A]<=R[B]) ~= C then pc++
  JMP      = 29,  -- pc += sBx
  TEST     = 30,  -- if R[A] == C then pc++
  TESTSET  = 31,  -- if R[B]==C then pc++ else R[A]=R[B]
  CALL     = 32,  -- R[A..A+C-2] = R[A](R[A+1..A+B-1])
  TAILCALL = 33,  -- return R[A](R[A+1..A+B-1])
  RETURN   = 34,  -- return R[A..A+B-2]
  FORPREP  = 35,  -- R[A] -= R[A+2]; setup for loop
  FORLOOP  = 36,  -- R[A] += R[A+2]; if in range goto sBx
  TFORPREP = 37,  -- prepare generic for
  TFORCALL = 38,  -- R[A+3..A+2+C] = R[A](R[A+1], R[A+2])
  TFORLOOP = 39,  -- if R[A+3] ~= nil then R[A+2]=R[A+3] else pc++
  SETLIST  = 40,  -- R[A][B] = R[A+1..A+C]
  CLOSURE  = 41,  -- R[A] = closure(proto[Bx])
  VARARG   = 42,  -- R[A..A+B-2] = ...
  GETUPVAL = 44,  -- R[A] = upvalues[B]
  SETUPVAL = 45,  -- upvalues[B] = R[A]
  EXTRARG  = 43,  -- extra argument for previous instruction
}

------------------------------------------------------------
-- 简单递归下降解析器
------------------------------------------------------------
local Parser = {}
Parser.__index = Parser

function Parser.new(source)
  return setmetatable({
    source = source,
    pos = 1,
    len = #source,
    tokens = {},
    token_pos = 1,
  }, Parser)
end

-- Tokenizer
function Parser:peek()
  self:skip_ws()
  if self.token_pos <= #self.tokens then
    return self.tokens[self.token_pos]
  end
  -- Tokenize next
  self:skip_ws()
  if self.pos > self.len then
    return { type = "EOF", value = "" }
  end
  local c = self.source:sub(self.pos, self.pos)
  
  -- Number
  if c:match("[%d]") then
    local num = self.source:match("^0[xX][%da-fA-F]+", self.pos) or
                self.source:match("^%d+%.%d+[eE][+-]?%d+", self.pos) or
                self.source:match("^%d+%.%d+", self.pos) or
                self.source:match("^%d+[eE][+-]?%d+", self.pos) or
                self.source:match("^%d+", self.pos)
    if num then
      local tok = { type = "NUMBER", value = num }
      self.tokens[#self.tokens + 1] = tok
      return tok
    end
  end
  
  -- String
  if c == '"' or c == "'" then
    local j = self.pos + 1
    while j <= self.len do
      local sc = self.source:sub(j, j)
      if sc == '\\' then j = j + 2
      elseif sc == c then j = j + 1; break
      else j = j + 1 end
    end
    local tok = { type = "STRING", value = self.source:sub(self.pos, j-1) }
    self.tokens[#self.tokens + 1] = tok
    return tok
  end
  
  -- Identifier / keyword
  if c:match("[%a_]") then
    local id = self.source:match("^[%a_][%w_]*", self.pos)
    local tok = { type = "IDENT", value = id }
    if id == "local" or id == "function" or id == "if" or id == "then" or
       id == "else" or id == "elseif" or id == "end" or id == "for" or
       id == "while" or id == "do" or id == "repeat" or id == "until" or
       id == "return" or id == "break" or id == "nil" or id == "true" or
       id == "false" or id == "and" or id == "or" or id == "not" or
       id == "in" or id == "goto" then
      tok.type = "KEYWORD"
    end
    self.tokens[#self.tokens + 1] = tok
    return tok
  end
  
  -- Long string: [=...[...]...=]
  if c == '[' then
    local eq_start = self.pos + 1
    local eq_count = 0
    while eq_start + eq_count <= self.len and self.source:sub(eq_start + eq_count, eq_start + eq_count) == '=' do
      eq_count = eq_count + 1
    end
    if eq_start + eq_count <= self.len and self.source:sub(eq_start + eq_count, eq_start + eq_count) == '[' then
      local close_pat = ']' .. string.rep('=', eq_count) .. ']'
      local close = self.source:find(close_pat, eq_start + eq_count + 1, true)
      if close then
        local tok = { type = "STRING", value = self.source:sub(self.pos, close + #close_pat - 1) }
        self.tokens[#self.tokens + 1] = tok
        return tok
      end
    end
  end

  -- Operators
  local ops = {
    ["+"] = "+", ["-"] = "-", ["*"] = "*", ["/"] = "/",
    ["%"] = "%", ["^"] = "^", ["#"] = "#", ["("] = "(",
    [")"] = ")", ["{"] = "{", ["}"] = "}", ["["] = "[",
    ["]"] = "]", [";"] = ";", [","] = ",", ["."] = ".",
    [":"] = ":", ["~"] = "~", ["="] = "=", [">"] = ">", ["<"] = "<",
    ["&"] = "&", ["|"] = "|",
  }
  
  if c == '<' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '<' then
      local tok = { type = 'OP', value = '<<' }
      self.tokens[#self.tokens + 1] = tok
      return tok
  elseif c == '>' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '>' then
      local tok = { type = 'OP', value = '>>' }
      self.tokens[#self.tokens + 1] = tok
      return tok
  elseif c == '/' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '/' then
      local tok = { type = 'OP', value = '//' }
      self.tokens[#self.tokens + 1] = tok
      return tok
  elseif c == '=' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '=' then
    local tok = { type = "OP", value = "==" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == '~' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '=' then
    local tok = { type = "OP", value = "~=" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == '<' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '=' then
    local tok = { type = "OP", value = "<=" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == '>' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '=' then
    local tok = { type = "OP", value = ">=" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == '.' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '.' then
    if self.pos + 1 < self.len and self.source:sub(self.pos+2, self.pos+2) == '.' then
      local tok = { type = "OP", value = "..." }
      self.tokens[#self.tokens + 1] = tok
      return tok
    end
    local tok = { type = "OP", value = ".." }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif c == ':' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == ':' then
    local tok = { type = "OP", value = "::" }
    self.tokens[#self.tokens + 1] = tok
    return tok
  elseif ops[c] then
    local tok = { type = "OP", value = c }
    self.tokens[#self.tokens + 1] = tok
    return tok
  end
  
  -- Unknown, skip
  local tok = { type = "UNKNOWN", value = c }
  self.tokens[#self.tokens + 1] = tok
  return tok
end

function Parser:advance()
  local tok = self:peek()
  self.token_pos = self.token_pos + 1
  -- Advance source position past the token
  if tok.type == "NUMBER" then
    self.pos = self.pos + #tok.value
  elseif tok.type == "STRING" then
    self.pos = self.pos + #tok.value
  elseif tok.type == "IDENT" or tok.type == "KEYWORD" then
    self.pos = self.pos + #tok.value
  elseif tok.type == "OP" then
    self.pos = self.pos + #tok.value
  else
    self.pos = self.pos + 1
  end
  self:skip_ws()
  return tok
end

function Parser:skip_ws()
  while self.pos <= self.len do
    local c = self.source:sub(self.pos, self.pos)
    if c == ' ' or c == '\t' or c == '\r' then
      self.pos = self.pos + 1
    elseif c == '\n' then
      self.pos = self.pos + 1
    elseif c == '-' and self.pos < self.len and self.source:sub(self.pos+1, self.pos+1) == '-' then
      -- Comment: check for long comment --[=...[...]...=]
      if self.pos + 2 <= self.len and self.source:sub(self.pos+2, self.pos+2) == '[' then
        local eq_start = self.pos + 3
        local eq_count = 0
        while eq_start + eq_count <= self.len and self.source:sub(eq_start + eq_count, eq_start + eq_count) == '=' do
          eq_count = eq_count + 1
        end
        if eq_start + eq_count <= self.len and self.source:sub(eq_start + eq_count, eq_start + eq_count) == '[' then
          local close_pat = ']' .. string.rep('=', eq_count) .. ']'
          local close = self.source:find(close_pat, eq_start + eq_count + 1, true)
          if close then
            self.pos = close + #close_pat
          else
            self.pos = self.len + 1
          end
        else
          -- Single-line comment
          local nl = self.source:find('\n', self.pos + 2)
          if nl then self.pos = nl + 1
          else self.pos = self.len + 1 end
        end
      else
        -- Single-line comment
        local nl = self.source:find('\n', self.pos + 2)
        if nl then self.pos = nl + 1
        else self.pos = self.len + 1 end
      end
    else
      break
    end
  end
end

function Parser:expect(type, value)
  local tok = self:advance()
  if tok.type ~= type or (value and tok.value ~= value) then
    error(string.format("Expected %s '%s', got %s '%s' at pos %d",
      type, value or "", tok.type, tok.value, self.pos))
  end
  return tok
end

function Parser:match(type, value)
  local tok = self:peek()
  if tok.type == type and (not value or tok.value == value) then
    return self:advance()
  end
  return nil
end

-- AST Node constructors
local function ast_block(stmts) return { type = "block", stmts = stmts } end
local function ast_assign(targets, values) return { type = "assign", targets = targets, values = values } end
local function ast_local(names, values) return { type = "local", names = names, values = values } end
local function ast_call(func, args) return { type = "call", func = func, args = args } end
local function ast_if(cond, then_block, else_block) return { type = "if", cond = cond, then_block = then_block, else_block = else_block } end
local function ast_while(cond, body) return { type = "while", cond = cond, body = body } end
local function ast_for_num(name, init, limit, step, body) return { type = "for_num", name = name, init = init, limit = limit, step = step, body = body } end
local function ast_for_in(names, iter_expr, body) return { type = "for_in", names = names, iter_expr = iter_expr, body = body } end
local function ast_return(values) return { type = "return", values = values } end
local function ast_break() return { type = "break" } end
local function ast_func_def(params, body, is_local, name) return { type = "func_def", params = params, body = body, is_local = is_local, name = name } end
local function ast_table(fields) return { type = "table", fields = fields } end
local function ast_index(obj, key) return { type = "index", obj = obj, key = key } end
local function ast_binop(op, left, right) return { type = "binop", op = op, left = left, right = right } end
local function ast_unop(op, expr) return { type = "unop", op = op, expr = expr } end
local function ast_number(val) return { type = "number", value = val } end
local function ast_string(val) return { type = "string", value = val } end
local function ast_ident(name) return { type = "ident", name = name } end
local function ast_bool(val) return { type = "bool", value = val } end
local function ast_nil() return { type = "nil" } end
local function ast_vararg() return { type = "vararg" } end
local function ast_do_block(body) return { type = "do_block", body = body } end
local function ast_repeat(body, cond) return { type = "repeat", body = body, cond = cond } end
local function ast_goto(label) return { type = "goto", label = label } end
local function ast_label(name) return { type = "label", name = name } end

function Parser:parse_block()
  local stmts = {}
  while true do
    local tok = self:peek()
    if tok.type == "EOF" or (tok.type == "KEYWORD" and
       (tok.value == "end" or tok.value == "else" or tok.value == "elseif" or
        tok.value == "until")) then
      break
    end
    local stmt = self:parse_stmt()
    if stmt then
      stmts[#stmts + 1] = stmt
    end
  end
  return ast_block(stmts)
end

function Parser:parse_stmt()
  local tok = self:peek()
  
  -- Empty / comment
  if tok.type == "EOF" then return nil end
  
  -- Local declaration
  if tok.type == "KEYWORD" and tok.value == "local" then
    self:advance()
    local next_tok = self:peek()
    if next_tok.type == "KEYWORD" and next_tok.value == "function" then
      self:advance()
      local name = self:expect("IDENT").value
      self:expect("OP", "(")
      local params = self:parse_param_list()
      self:expect("OP", ")")
      local body = self:parse_block()
      self:expect("KEYWORD", "end")
      return ast_func_def(params, body, true, name)
    else
      local names = {}
      repeat
        names[#names + 1] = self:expect("IDENT").value
        -- Skip Lua 5.4 attribute: <const> or <close>
        if self:match("OP", "<") then
          self:advance()  -- skip attribute name (const/close)
          self:expect("OP", ">")
        end
      until not self:match("OP", ",")
      local values = nil
      if self:match("OP", "=") then
        values = self:parse_expr_list()
      end
      return ast_local(names, values)
    end
  end
  
  -- Function definition
  if tok.type == "KEYWORD" and tok.value == "function" then
    self:advance()
    local name = self:expect("IDENT").value
    -- Support dotted names: function M.protect(code)
    -- Support method names: function M:method(code)
    local name_parts = {name}
    while true do
      local peek_tok = self:peek()
      if peek_tok.type == "OP" and (peek_tok.value == "." or peek_tok.value == ":") then
        local sep = self:advance().value
        name_parts[#name_parts + 1] = sep
        name_parts[#name_parts + 1] = self:expect("IDENT").value
      else
        break
      end
    end
    local full_name = table.concat(name_parts)
    self:expect("OP", "(")
    local params = self:parse_param_list()
    self:expect("OP", ")")
    local body = self:parse_block()
    self:expect("KEYWORD", "end")
    return ast_assign({ast_ident(full_name)}, {ast_func_def(params, body, false)})
  end
  
  -- If statement
  if tok.type == "KEYWORD" and tok.value == "if" then
    self:advance()
    local cond = self:parse_expr()
    self:expect("KEYWORD", "then")
    local then_block = self:parse_block()
    local else_block = nil
    if self:match("KEYWORD", "elseif") then
      -- Parse the entire elseif/else/end chain as a nested if
      -- Use a helper function to handle the recursion
      local function parse_elseif_chain()
        local ec = self:parse_expr()
        self:expect("KEYWORD", "then")
        local eb = self:parse_block()
        local ee = nil
        if self:match("KEYWORD", "elseif") then
          ee = parse_elseif_chain()
        elseif self:match("KEYWORD", "else") then
          ee = self:parse_block()
          self:expect("KEYWORD", "end")
        else
          self:expect("KEYWORD", "end")
        end
        return ast_block({ast_if(ec, eb, ee)})
      end
      else_block = parse_elseif_chain()
    elseif self:match("KEYWORD", "else") then
      else_block = self:parse_block()
      self:expect("KEYWORD", "end")
    else
      self:expect("KEYWORD", "end")
    end
    return ast_if(cond, then_block, else_block)
  end
  
  -- While loop
  if tok.type == "KEYWORD" and tok.value == "while" then
    self:advance()
    local cond = self:parse_expr()
    self:expect("KEYWORD", "do")
    local body = self:parse_block()
    self:expect("KEYWORD", "end")
    return ast_while(cond, body)
  end
  
  -- For loop
  if tok.type == "KEYWORD" and tok.value == "for" then
    self:advance()
    local name = self:expect("IDENT").value
    if self:match("OP", "=") then
      -- Numeric for
      local init = self:parse_expr()
      self:expect("OP", ",")
      local limit = self:parse_expr()
      local step = nil
      if self:match("OP", ",") then
        step = self:parse_expr()
      end
      self:expect("KEYWORD", "do")
      local body = self:parse_block()
      self:expect("KEYWORD", "end")
      return ast_for_num(name, init, limit, step, body)
    else
      -- Generic for: for k, v, ... in iter_expr do body end
      local names = {name}
      while self:match("OP", ",") do
        names[#names + 1] = self:expect("IDENT").value
      end
      self:expect("KEYWORD", "in")
      local iter_expr = self:parse_expr_list()
      self:expect("KEYWORD", "do")
      local body = self:parse_block()
      self:expect("KEYWORD", "end")
      return ast_for_in(names, iter_expr, body)
    end
  end
  
  -- Return
  if tok.type == "KEYWORD" and tok.value == "return" then
    self:advance()
    local values = nil
    local nk = self:peek()
    if nk.type ~= "KEYWORD" and nk.type ~= "EOF" then
      values = self:parse_expr_list()
    elseif nk.type == "KEYWORD" and (nk.value == "function" or nk.value == "nil" or nk.value == "true" or nk.value == "false" or nk.value == "not") then
      values = self:parse_expr_list()
    end
    return ast_return(values)
  end
  
  -- Standalone do...end block
  if tok.type == "KEYWORD" and tok.value == "do" then
    self:advance()
    local body = self:parse_block()
    self:expect("KEYWORD", "end")
    return ast_do_block(body)
  end

  -- Repeat...until loop
  if tok.type == "KEYWORD" and tok.value == "repeat" then
    self:advance()
    local body = self:parse_block()
    self:expect("KEYWORD", "until")
    local cond = self:parse_expr()
    return ast_repeat(body, cond)
  end

  -- Break
  if tok.type == "KEYWORD" and tok.value == "break" then
    self:advance()
    return ast_break()
  end

  -- Goto label
  if tok.type == "KEYWORD" and tok.value == "goto" then
    self:advance()
    local label = self:expect("IDENT").value
    return ast_goto(label)
  end

  -- Label ::name::
  if tok.type == "OP" and tok.value == "::" then
    self:advance()
    local name = self:expect("IDENT").value
    self:expect("OP", "::")
    return ast_label(name)
  end
  
  -- Expression statement (assignment or call)
  local targets = {self:parse_expr()}
  while self:match("OP", ",") do
    targets[#targets + 1] = self:parse_expr()
  end
  if self:match("OP", "=") then
    local values = self:parse_expr_list()
    return ast_assign(targets, values)
  end
  -- Must be a call (single expression)
  return targets[1]
end

function Parser:parse_param_list()
  local params = {}
  local tok = self:peek()
  if tok.type == "IDENT" then
    params[#params + 1] = self:advance().value
    while self:match("OP", ",") do
      local next_tok = self:peek()
      if next_tok.type == "OP" and next_tok.value == "..." then
        self:advance()
        params[#params + 1] = "..."
        break
      end
      params[#params + 1] = self:expect("IDENT").value
    end
  elseif tok.type == "OP" and tok.value == "..." then
    self:advance()
    params[#params + 1] = "..."
  end
  return params
end

function Parser:parse_expr_list()
  local exprs = {}
  exprs[#exprs + 1] = self:parse_expr()
  while self:match("OP", ",") do
    exprs[#exprs + 1] = self:parse_expr()
  end
  return exprs
end

function Parser:parse_expr()
  return self:parse_or_expr()
end

function Parser:parse_or_expr()
  local left = self:parse_and_expr()
  while self:match("KEYWORD", "or") do
    local right = self:parse_and_expr()
    left = ast_binop("or", left, right)
  end
  return left
end

function Parser:parse_and_expr()
  local left = self:parse_cmp_expr()
  while self:match("KEYWORD", "and") do
    local right = self:parse_cmp_expr()
    left = ast_binop("and", left, right)
  end
  return left
end

function Parser:parse_cmp_expr()
  local left = self:parse_bor_expr()
  local ops_map = {["=="]="==",["~="]="~=",[">"]=">",["<"]="<",[">="]=">=",["<="]="<="}
  local tok = self:peek()
  if tok.type == "OP" and ops_map[tok.value] then
    self:advance()
    local right = self:parse_bor_expr()
    return ast_binop(ops_map[tok.value], left, right)
  end
  return left
end

function Parser:parse_bor_expr()
  local left = self:parse_xor_expr()
  while self:match("OP", "|") do
    local right = self:parse_xor_expr()
    left = ast_binop("|", left, right)
  end
  return left
end

function Parser:parse_xor_expr()
  local left = self:parse_band_expr()
  while self:match("OP", "~") do
    local right = self:parse_band_expr()
    left = ast_binop("~", left, right)
  end
  return left
end

function Parser:parse_band_expr()
  local left = self:parse_shift_expr()
  while self:match("OP", "&") do
    local right = self:parse_shift_expr()
    left = ast_binop("&", left, right)
  end
  return left
end

function Parser:parse_shift_expr()
  local left = self:parse_concat_expr()
  while true do
    local tok = self:peek()
    if tok.type == "OP" and (tok.value == "<<" or tok.value == ">>") then
      self:advance()
      local right = self:parse_concat_expr()
      left = ast_binop(tok.value, left, right)
    else
      break
    end
  end
  return left
end

function Parser:parse_concat_expr()
  local left = self:parse_add_expr()
  while self:match("OP", "..") do
    local right = self:parse_add_expr()
    left = ast_binop("..", left, right)
  end
  return left
end

function Parser:parse_add_expr()
  local left = self:parse_mul_expr()
  while true do
    local tok = self:peek()
    if tok.type == "OP" and (tok.value == "+" or tok.value == "-") then
      self:advance()
      local right = self:parse_mul_expr()
      left = ast_binop(tok.value, left, right)
    else
      break
    end
  end
  return left
end

function Parser:parse_mul_expr()
  local left = self:parse_unary_expr()
  while true do
    local tok = self:peek()
    if tok.type == "OP" and (tok.value == "*" or tok.value == "/" or tok.value == "//" or tok.value == "%") then
      self:advance()
      local right = self:parse_unary_expr()
      left = ast_binop(tok.value, left, right)
    else
      break
    end
  end
  return left
end

function Parser:parse_unary_expr()
  local tok = self:peek()
  if tok.type == "KEYWORD" and tok.value == "not" then
    self:advance()
    return ast_unop("not", self:parse_unary_expr())
  end
  if tok.type == "OP" and tok.value == "#" then
    self:advance()
    return ast_unop("#", self:parse_unary_expr())
  end
  if tok.type == "OP" and tok.value == "-" then
    self:advance()
    return ast_unop("-", self:parse_unary_expr())
  end
  if tok.type == "OP" and tok.value == "~" then
    self:advance()
    return ast_unop("~", self:parse_unary_expr())
  end
  return self:parse_pow_expr()
end

function Parser:parse_pow_expr()
  local left = self:parse_primary_expr()
  if self:match("OP", "^") then
    local right = self:parse_unary_expr()
    return ast_binop("^", left, right)
  end
  return left
end

function Parser:parse_primary_expr()
  local tok = self:peek()
  local node
  
  if tok.type == "NUMBER" then
    self:advance()
    node = ast_number(tonumber(tok.value))
  elseif tok.type == "STRING" then
    self:advance()
    local s
    if tok.value:sub(1, 1) == '[' and tok.value:sub(2, 2) ~= '"' and tok.value:sub(2, 2) ~= "'" then
      local eq_end = 2
      while tok.value:sub(eq_end, eq_end) == '=' do eq_end = eq_end + 1 end
      s = tok.value:sub(eq_end + 1, -(eq_end + 1))
    else
      s = tok.value:sub(2, -2)
      s = s:gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\r", "\r"):gsub("\\\\", "\\"):gsub('\\"', '"'):gsub("\\'", "'"):gsub("\\0", "\0")
    end
    node = ast_string(s)
  elseif tok.type == "KEYWORD" and tok.value == "nil" then
    self:advance()
    node = ast_nil()
  elseif tok.type == "KEYWORD" and tok.value == "true" then
    self:advance()
    node = ast_bool(true)
  elseif tok.type == "KEYWORD" and tok.value == "false" then
    self:advance()
    node = ast_bool(false)
  elseif tok.type == "OP" and tok.value == "..." then
    self:advance()
    node = ast_vararg()
  elseif tok.type == "OP" and tok.value == "(" then
    self:advance()
    node = self:parse_expr()
    self:expect("OP", ")")
  elseif tok.type == "KEYWORD" and tok.value == "function" then
    self:advance()
    self:expect("OP", "(")
    local params = self:parse_param_list()
    self:expect("OP", ")")
    local body = self:parse_block()
    self:expect("KEYWORD", "end")
    node = ast_func_def(params, body, false)
  elseif tok.type == "OP" and tok.value == "{" then
    node = self:parse_table_constructor()
  elseif tok.type == "IDENT" then
    self:advance()
    node = ast_ident(tok.value)
  else
    self:advance()
    node = ast_ident("__unknown__")
  end
  
  -- Handle indexing and calls (postfix operations) for ALL primary expressions
  while true do
    local next_tok = self:peek()
    if next_tok.type == "OP" and next_tok.value == "[" then
      self:advance()
      local key = self:parse_expr()
      self:expect("OP", "]")
      node = ast_index(node, key)
    elseif next_tok.type == "OP" and next_tok.value == "." then
      self:advance()
      local field = self:expect("IDENT").value
      node = ast_index(node, ast_string(field))
    elseif next_tok.type == "OP" and next_tok.value == ":" then
      self:advance()
      local method = self:expect("IDENT").value
      self:expect("OP", "(")
      local args = {}
      if self:peek().type ~= "OP" or self:peek().value ~= ")" then
        args = self:parse_expr_list()
      end
      self:expect("OP", ")")
      node = ast_call(ast_index(node, ast_string(method)), {node, table.unpack(args)})
    elseif next_tok.type == "OP" and next_tok.value == "(" then
      self:advance()
      local args = {}
      if self:peek().type ~= "OP" or self:peek().value ~= ")" then
        args = self:parse_expr_list()
      end
      self:expect("OP", ")")
      node = ast_call(node, args)
    elseif next_tok.type == "STRING" then
      -- String literal as single call arg: "hello" == ("hello")
      self:advance()
      local s = next_tok.value:sub(2, -2)
      node = ast_call(node, {ast_string(s)})
    elseif next_tok.type == "OP" and next_tok.value == "{" then
      -- Table constructor as single call arg
      local tbl = self:parse_table_constructor()
      node = ast_call(node, {tbl})
    else
      break
    end
  end
  return node
end

function Parser:parse_table_constructor()
  self:expect("OP", "{")
  local fields = {}
  while not (self:peek().type == "OP" and self:peek().value == "}") do
    local tok = self:peek()
    if tok.type == "IDENT" then
      -- Save position, advance past identifier, check if next is "="
      local save_pos = self.pos
      local save_tpos = self.token_pos
      local key_tok = self:advance()
      local next_tok = self:peek()
      if next_tok.type == "OP" and next_tok.value == "=" then
        -- It's a key-value pair
        self:advance()  -- consume =
        local val = self:parse_expr()
        fields[#fields + 1] = { key = ast_string(key_tok.value), value = val }
      else
        -- Not a key-value pair, backtrack
        self.pos = save_pos
        self.token_pos = save_tpos
        local val = self:parse_expr()
        fields[#fields + 1] = { key = nil, value = val }
      end
    elseif tok.type == "OP" and tok.value == "[" then
      self:advance()
      local key = self:parse_expr()
      self:expect("OP", "]")
      self:expect("OP", "=")
      local val = self:parse_expr()
      fields[#fields + 1] = { key = key, value = val }
    else
      local val = self:parse_expr()
      fields[#fields + 1] = { key = nil, value = val }
    end
    if not self:match("OP", ",") then break end
  end
  self:expect("OP", "}")
  return ast_table(fields)
end

------------------------------------------------------------
-- 字节码编译器
------------------------------------------------------------
local Compiler = {}
Compiler.__index = Compiler

function Compiler.new(parent)
  return setmetatable({
    code = {},
    constants = {},
    const_map = {},
    reg_count = 0,
    var_regs = {},
    upvalues = {},
    break_jmps = {},  -- stack of break JMP lists for nested loops
    labels = {},      -- label name -> code position
    goto_jmps = {},   -- {label, jmp_pc} pairs for later resolution
    parent = parent,  -- parent scope for upvalue access
  }, Compiler)
end

function Compiler:emit(op, a, b, c)
  self.code[#self.code + 1] = { op = op, a = a or 0, b = b or 0, c = c or 0, sBx = b }
  return #self.code
end

function Compiler:emit_sbx(op, a, sbx)
  self.code[#self.code + 1] = { op = op, a = a or 0, b = sbx or 0, c = 0, sBx = sbx or 0 }
  return #self.code
end

function Compiler:add_const(val)
  local key = type(val) == "string" and ("S:" .. val) or ("N:" .. tostring(val))
  if not self.const_map[key] then
    self.constants[#self.constants + 1] = val
    self.const_map[key] = #self.constants  -- 1-based index
  end
  return self.const_map[key]
end

function Compiler:alloc_reg()
  self.reg_count = self.reg_count + 1
  return self.reg_count - 1
end

-- Find existing upvalue for a variable name, or create a new one
function Compiler:find_or_create_upvalue(var_name)
  -- Check if we already have an upvalue for this variable
  for i, uv in ipairs(self.upvalues) do
    if uv.name == var_name then
      return i - 1  -- Return 0-based index for the VM
    end
  end
  -- Create new upvalue
  local uv_idx = #self.upvalues + 1
  self.upvalues[uv_idx] = { reg = self.parent.var_regs[var_name], name = var_name }
  return uv_idx - 1  -- Return 0-based index for the VM
end

function Compiler:free_reg(r)
  if r == self.reg_count - 1 then
    self.reg_count = self.reg_count - 1
  end
end

function Compiler:compile_block(block)
  for _, stmt in ipairs(block.stmts) do
    self:compile_stmt(stmt)
  end
end

function Compiler:compile_stmt(stmt)
  if stmt.type == "assign" then
    self:compile_assign(stmt)
  elseif stmt.type == "local" then
    self:compile_local(stmt)
  elseif stmt.type == "call" then
    local r = self:compile_expr(stmt)
    self:free_reg(r)
  elseif stmt.type == "if" then
    self:compile_if(stmt)
  elseif stmt.type == "while" then
    self:compile_while(stmt)
  elseif stmt.type == "for_num" then
    self:compile_for_num(stmt)
  elseif stmt.type == "for_in" then
    self:compile_for_in(stmt)
  elseif stmt.type == "return" then
    self:compile_return(stmt)
  elseif stmt.type == "do_block" then
    -- Save scope: snapshot var_regs and reg_count for proper lexical scoping
    local saved_vars = {}
    for k, v in pairs(self.var_regs) do saved_vars[k] = v end
    local saved_reg_count = self.reg_count
    self:compile_block(stmt.body)
    -- Restore scope: free inner registers and restore outer variable mapping
    self.reg_count = saved_reg_count
    self.var_regs = saved_vars
  elseif stmt.type == "repeat" then
    self:compile_repeat(stmt)
  elseif stmt.type == "break" then
    local jmp_pc = self:emit_sbx(OPC.JMP, 0, 0)  -- placeholder, fix later
    if #self.break_jmps > 0 then
      self.break_jmps[#self.break_jmps][#self.break_jmps[#self.break_jmps] + 1] = jmp_pc
    end
  elseif stmt.type == "goto" then
    local jmp_pc = self:emit_sbx(OPC.JMP, 0, 0)  -- placeholder, resolve later
    self.goto_jmps[#self.goto_jmps + 1] = { label = stmt.label, pc = jmp_pc }
  elseif stmt.type == "label" then
    self.labels[stmt.name] = #self.code + 1  -- label points to next instruction
  elseif stmt.type == "func_def" then
    self:compile_func_def(stmt)
  end
end

function Compiler:compile_assign(stmt)
  -- Evaluate all values first, copying to fresh temp registers
  -- This prevents overlap when target register == source register
  -- e.g. a, b = b, a  where compile_expr(b) returns b's own register
  local val_regs = {}
  if stmt.values then
    for i, val in ipairs(stmt.values) do
      if i <= #stmt.targets then
        local src = self:compile_expr(val)
        -- Always copy to a fresh temp to avoid register aliasing
        local tmp = self:alloc_reg()
        self:emit(OPC.MOVE, tmp, src, 0)
        self:free_reg(src)
        val_regs[i] = tmp
      end
    end
  end
  -- Now assign to targets
  for i, target in ipairs(stmt.targets) do
    local r = val_regs[i]
    if r then
      if target.type == "ident" then
        if self.var_regs[target.name] then
          self:emit(OPC.MOVE, self.var_regs[target.name], r, 0)
        elseif self.parent and self.parent.var_regs[target.name] then
          local uv_idx = self:find_or_create_upvalue(target.name)
          self:emit(OPC.SETUPVAL, r, uv_idx, 0)
        else
          local k = self:add_const(target.name)
          self:emit(OPC.SETGLOBAL, r, k, 0)
        end
      elseif target.type == "index" then
        local obj_r = self:compile_expr(target.obj)
        local key_r = self:compile_expr(target.key)
        self:emit(OPC.SETTABLE, obj_r, key_r, r)
        self:free_reg(obj_r)
        self:free_reg(key_r)
      end
      self:free_reg(r)
    end
  end
end

function Compiler:compile_local(stmt)
  local regs = {}
  for i, name in ipairs(stmt.names) do
    local r = self:alloc_reg()
    self.var_regs[name] = r
    regs[#regs + 1] = r
  end
  if stmt.values then
    local nvals = #stmt.values
    local nnames = #stmt.names
    -- Multi-return: local a, b, c = f()
    if nvals == 1 and nnames > 1 and stmt.values[1].type == "call" then
      local call_expr = stmt.values[1]
      local func_r = self:compile_expr(call_expr.func)
      local base = func_r
      local nargs = 0
      if call_expr.args then
        for i, arg in ipairs(call_expr.args) do
          local ar = self:compile_expr(arg)
          if ar ~= base + i then
            self:emit(OPC.MOVE, base + i, ar, 0)
          end
          nargs = nargs + 1
        end
      end
      -- Store nnames results: C = nnames + 1
      self:emit(OPC.CALL, base, nargs + 1, nnames + 1)
      -- Move results to target registers
      for i = 1, nnames do
        if regs[i] ~= base + i - 1 then
          self:emit(OPC.MOVE, regs[i], base + i - 1, 0)
        end
      end
      self:free_reg(func_r)
    -- Multi-vararg: local a, b, c = ...
    elseif nvals == 1 and nnames > 1 and stmt.values[1].type == "vararg" then
      -- VARARG with B = nnames + 1 to get nnames varargs
      self:emit(OPC.VARARG, regs[1], nnames + 1, 0)
    else
      for i, val in ipairs(stmt.values) do
        if regs[i] then
          local r = self:compile_expr(val)
          self:emit(OPC.MOVE, regs[i], r, 0)
          self:free_reg(r)
        end
      end
    end
  else
    for _, r in ipairs(regs) do
      self:emit(OPC.LOADNIL, r, 0, 0)
    end
  end
end

function Compiler:compile_if(stmt)
  -- Check if condition is a comparison that can be optimized
  if stmt.cond.type == "binop" and ({["=="]=1,["~="]=1,["<"]=1,[">"]=1,["<="]=1,[">="]=1})[stmt.cond.op] then
    -- Direct comparison: emit compare + JMP pattern
    local lr = self:compile_expr(stmt.cond.left)
    local rr = self:compile_expr(stmt.cond.right)
    local cmp_ops = {["=="]=OPC.EQ, ["~="]=OPC.EQ, ["<"]=OPC.LT, [">"]=OPC.LT, ["<="]=OPC.LE, [">="]=OPC.LE}
    local negate = (stmt.cond.op == "~=") and 1 or 0
    local op1, op2 = lr, rr
    if stmt.cond.op == ">" or stmt.cond.op == ">=" then op1, op2 = rr, lr end
    -- Emit comparison: skip next JMP if condition matches
    local cmp_a = (stmt.cond.op ~= "~=") and 0 or 1
    self:emit(cmp_ops[stmt.cond.op], cmp_a, op1, op2)
    self:free_reg(lr)
    self:free_reg(rr)
    -- JMP to else/end (skipped if condition is true)
    local jmp_pc = self:emit(OPC.JMP, 0, 0, 0)
    self:compile_block(stmt.then_block)
    if stmt.else_block then
      local else_jmp = self:emit(OPC.JMP, 0, 0, 0)
      self.code[jmp_pc].b = #self.code - jmp_pc
      self:compile_block(stmt.else_block)
      self.code[else_jmp].b = #self.code - else_jmp
    else
      self.code[jmp_pc].b = #self.code - jmp_pc
    end
  else
    -- General case: evaluate condition, TEST + JMP pattern
    local cond_r = self:compile_expr(stmt.cond)
    local test_pc = self:emit(OPC.TEST, cond_r, 0, 0)  -- if falsy, skip next
    self:free_reg(cond_r)
    -- JMP to else/end (skipped when condition is truthy)
    local jmp_pc = self:emit(OPC.JMP, 0, 0, 0)
    self:compile_block(stmt.then_block)
    if stmt.else_block then
      local else_jmp = self:emit(OPC.JMP, 0, 0, 0)
      self.code[jmp_pc].b = #self.code - jmp_pc
      self:compile_block(stmt.else_block)
      self.code[else_jmp].b = #self.code - else_jmp
    else
      self.code[jmp_pc].b = #self.code - jmp_pc
    end
  end
end

function Compiler:compile_while(stmt)
  -- Push break JMP list for this loop
  self.break_jmps[#self.break_jmps + 1] = {}
  local loop_pc = #self.code + 1
  local cond_r = self:compile_expr(stmt.cond)
  local test_pc = self:emit(OPC.TEST, cond_r, 0, 0)
  self:free_reg(cond_r)
  local exit_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  self:compile_block(stmt.body)
  local back_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  self.code[back_jmp].sBx = loop_pc - back_jmp - 1
  self.code[back_jmp].b = loop_pc - back_jmp - 1
  self.code[exit_jmp].sBx = #self.code - exit_jmp
  self.code[exit_jmp].b = #self.code - exit_jmp
  -- Fix all break JMPs to point past the loop
  local breaks = table.remove(self.break_jmps)
  for _, bj in ipairs(breaks) do
    self.code[bj].sBx = #self.code - bj
    self.code[bj].b = #self.code - bj
  end
end

function Compiler:compile_repeat(stmt)
  self.break_jmps[#self.break_jmps + 1] = {}
  local loop_pc = #self.code + 1
  self:compile_block(stmt.body)
  local cond_r = self:compile_expr(stmt.cond)
  local test_pc = self:emit(OPC.TEST, cond_r, 0, 0)
  self:free_reg(cond_r)
  local back_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  self.code[back_jmp].sBx = loop_pc - back_jmp - 1
  self.code[back_jmp].b = loop_pc - back_jmp - 1
  -- Fix all break JMPs to point past the loop
  local breaks = table.remove(self.break_jmps)
  for _, bj in ipairs(breaks) do
    self.code[bj].sBx = #self.code - bj
    self.code[bj].b = #self.code - bj
  end
end

function Compiler:compile_for_num(stmt)
  -- Numeric for with correct step sign handling (including negative steps).
  -- Uses FORPREP/FORLOOP layout:
  --   R[base]=idx, R[base+1]=limit, R[base+2]=step, R[base+3]=external idx
  self.break_jmps[#self.break_jmps + 1] = {}
  local init_r = self:compile_expr(stmt.init)
  local limit_r = self:compile_expr(stmt.limit)
  local step_r = stmt.step and self:compile_expr(stmt.step) or nil
  if not step_r then
    step_r = self:alloc_reg()
    self:emit(OPC.LOADK, step_r, self:add_const(1), 0)
  end

  local base = self.reg_count
  self.reg_count = self.reg_count + 4
  local limit_slot = base + 1
  local step_slot = base + 2
  local ext_r = base + 3

  self:emit(OPC.MOVE, base, init_r, 0)
  self:emit(OPC.MOVE, limit_slot, limit_r, 0)
  self:emit(OPC.MOVE, step_slot, step_r, 0)
  self.var_regs[stmt.name] = ext_r

  -- FORPREP: idx = idx - step; jump to FORLOOP
  local prep_pc = self:emit_sbx(OPC.FORPREP, base, 0)
  local body_pc = #self.code + 1
  self:compile_block(stmt.body)
  -- FORLOOP: idx = idx + step; if in range, store ext idx and jump back to body
  local loop_pc = self:emit_sbx(OPC.FORLOOP, base, 0)

  -- FORLOOP back to body: body = loop + 1 + sBx => sBx = body - loop - 1
  self.code[loop_pc].sBx = body_pc - loop_pc - 1
  self.code[loop_pc].b = body_pc - loop_pc - 1
  -- FORPREP to FORLOOP: loop = prep + 1 + sBx => sBx = loop - prep - 1
  self.code[prep_pc].sBx = loop_pc - prep_pc - 1
  self.code[prep_pc].b = loop_pc - prep_pc - 1

  local breaks = table.remove(self.break_jmps)
  for _, bj in ipairs(breaks) do
    self.code[bj].sBx = #self.code - bj
    self.code[bj].b = #self.code - bj
  end
  self:free_reg(init_r)
  self:free_reg(limit_r)
  self:free_reg(step_r)
end

function Compiler:compile_for_in(stmt)
  -- for k, v, ... in iter_expr do body end
  --
  -- Lua semantics:
  --   local func, state, control = iter_expr
  --   while true do
  --     local k, v, ... = func(state, control)
  --     if k == nil then break end
  --     control = k
  --     -- body
  --   end
  --
  -- Bytecode:
  --   <compile iter_expr to get func, state, control in R[A], R[A+1], R[A+2]>
  --   TFORCALL A, C: R[A+3..A+2+C] = R[A](R[A+1], R[A+2])
  --   TFORLOOP A, sBx: if R[A+3] ~= nil then R[A+2]=R[A+3]; jump back
  --

  self.break_jmps[#self.break_jmps + 1] = {}
  local nvars = #stmt.names

  -- Allocate ALL registers contiguously: base, state, ctrl, var1, var2, ...
  -- This ensures they are at R[A], R[A+1], R[A+2], R[A+3], R[A+4], ...
  local base_r = self:alloc_reg()  -- R[A]: iterator function
  local state_r = self:alloc_reg() -- R[A+1]: state
  local ctrl_r = self:alloc_reg()  -- R[A+2]: control variable
  local var_regs = {}
  for i = 1, nvars do
    var_regs[i] = self:alloc_reg() -- R[A+3], R[A+4], ...
  end

  -- Set variable names to point to TFORCALL output registers
  for i, name in ipairs(stmt.names) do
    self.var_regs[name] = var_regs[i]
  end

  -- Now compile iterator expression (may allocate/free temp regs above our range)
  if #stmt.iter_expr == 1 and stmt.iter_expr[1].type == 'call' then
    local call_expr = stmt.iter_expr[1]
    local func_r = self:compile_expr(call_expr.func)
    local arg_regs = {}
    for i, arg in ipairs(call_expr.args) do
      arg_regs[i] = self:compile_expr(arg)
    end
    self:emit(OPC.MOVE, base_r, func_r, 0)
    for i, ar in ipairs(arg_regs) do
      self:emit(OPC.MOVE, base_r + i, ar, 0)
      self:free_reg(ar)
    end
    self:free_reg(func_r)
    self:emit(OPC.CALL, base_r, #arg_regs + 1, 4)
  else
    local r = self:compile_expr(stmt.iter_expr[1])
    self:emit(OPC.MOVE, base_r, r, 0)
    self:free_reg(r)
    self:emit(OPC.LOADNIL, state_r, 0, 0)
    self:emit(OPC.LOADNIL, ctrl_r, 0, 0)
  end

  -- Update reg_count to account for TFORCALL output registers
  local max_used = base_r + 2 + nvars
  if max_used > self.reg_count then
    self.reg_count = max_used
  end

  -- TFORCALL: R[A+3..A+2+C] = R[A](R[A+1], R[A+2])
  local tforcall_pc = #self.code + 1
  self:emit(OPC.TFORCALL, base_r, 0, nvars)

  -- TFORLOOP: if R[A+3] ~= nil then R[A+2]=R[A+3]; jump to loop body
  --           if R[A+3] == nil then fall through (exit loop)
  local tforloop_pc = self:emit_sbx(OPC.TFORLOOP, base_r, 0)

  -- If nil, jump to exit
  local exit_jmp = self:emit_sbx(OPC.JMP, 0, 0)

  -- Loop body
  local body_start = #self.code + 1
  self:compile_block(stmt.body)

  -- Jump back to TFORCALL
  local back_jmp = self:emit_sbx(OPC.JMP, 0, 0)
  self.code[back_jmp].b = tforcall_pc - back_jmp - 1
  self.code[back_jmp].sBx = tforcall_pc - back_jmp - 1

  -- Fix TFORLOOP: jump to body_start
  self.code[tforloop_pc].sBx = body_start - tforloop_pc - 1
  self.code[tforloop_pc].b = body_start - tforloop_pc - 1

  -- Fix exit jump: jump to after loop
  self.code[exit_jmp].sBx = #self.code - exit_jmp
  self.code[exit_jmp].b = #self.code - exit_jmp
  -- Fix all break JMPs to point past the loop
  local breaks = table.remove(self.break_jmps)
  for _, bj in ipairs(breaks) do
    self.code[bj].sBx = #self.code - bj
    self.code[bj].b = #self.code - bj
  end

  -- Free registers
  for i = 1, nvars do
    self:free_reg(var_regs[i])
  end
  self:free_reg(base_r)
  self:free_reg(state_r)
  self:free_reg(ctrl_r)
end

function Compiler:compile_return(stmt)
  if stmt.values and #stmt.values > 0 then
    if #stmt.values == 1 then
      local r = self:compile_expr(stmt.values[1])
      self:emit(OPC.RETURN, r, 2, 0)
    else
      local base = self:alloc_reg()
      for i, val in ipairs(stmt.values) do
        local r = self:compile_expr(val)
        self:emit(OPC.MOVE, base + i - 1, r, 0)
        self:free_reg(r)
      end
      self:emit(OPC.RETURN, base, #stmt.values + 1, 0)
    end
  else
    self:emit(OPC.RETURN, 0, 1, 0)
  end
end

function Compiler:resolve_gotos()
  for _, g in ipairs(self.goto_jmps) do
    local target = self.labels[g.label]
    if target then
      self.code[g.pc].sBx = target - g.pc - 1
      self.code[g.pc].b = target - g.pc - 1
    end
    -- Silently skip unresolved gotos (Lua allows forward refs in some cases)
  end
  self.goto_jmps = {}
end

function Compiler:compile_func_def(stmt)
  -- Compile function body in a sub-compiler with parent scope
  local sub = Compiler.new(self)
  local named_params = {}
  for i, param in ipairs(stmt.params) do
    if param ~= "..." then
      named_params[#named_params + 1] = param
      sub.var_regs[param] = i - 1
      sub.reg_count = i
    end
  end
  sub:compile_block(stmt.body)
  sub:resolve_gotos()  -- resolve goto -> label jumps
  if #sub.code == 0 or sub.code[#sub.code].op ~= OPC.RETURN then
    sub:emit(OPC.RETURN, 0, 1, 0)
  end
  
  local proto = {
    code = sub.code,
    constants = sub.constants,
    numparams = #named_params,
    maxstack = sub.reg_count + 1,
    upvalues = sub.upvalues,  -- upvalue descriptors
    has_vararg = (#stmt.params > 0 and stmt.params[#stmt.params] == "..."),
  }
  
  local r = self:alloc_reg()
  self:emit(OPC.CLOSURE, r, #self.constants + 1, 0)
  self.constants[#self.constants + 1] = proto
  
  if stmt.is_local and stmt.name then
    -- For recursive local functions, also set as global
    local gk = self:add_const(stmt.name)
    self:emit(OPC.SETGLOBAL, r, gk, 0)
  end
  
  return r
end

function Compiler:compile_expr(expr)
  if expr.type == "number" then
    local r = self:alloc_reg()
    local k = self:add_const(expr.value)
    self:emit(OPC.LOADK, r, k, 0)
    return r
  end
  
  if expr.type == "string" then
    local r = self:alloc_reg()
    local k = self:add_const(expr.value)
    self:emit(OPC.LOADK, r, k, 0)
    return r
  end
  
  if expr.type == "bool" then
    local r = self:alloc_reg()
    self:emit(OPC.LOADBOOL, r, expr.value and 1 or 0, 0)
    return r
  end
  
  if expr.type == "nil" then
    local r = self:alloc_reg()
    self:emit(OPC.LOADNIL, r, 0, 0)
    return r
  end

  if expr.type == "vararg" then
    local r = self:alloc_reg()
    self:emit(OPC.VARARG, r, 2, 0)  -- B=2 means 1 result
    return r
  end
  
  if expr.type == "ident" then
    if self.var_regs[expr.name] then
      local r = self:alloc_reg()
      self:emit(OPC.MOVE, r, self.var_regs[expr.name], 0)
      return r
    elseif self.parent and self.parent.var_regs[expr.name] then
      -- Variable is in parent scope -> use GETUPVAL
      local r = self:alloc_reg()
      local uv_idx = self:find_or_create_upvalue(expr.name)
      self:emit(OPC.GETUPVAL, r, uv_idx, 0)
      return r
    else
      local r = self:alloc_reg()
      local k = self:add_const(expr.name)
      self:emit(OPC.GETGLOBAL, r, k, 0)
      return r
    end
  end
  
  if expr.type == "binop" then
    local opcodes = {
      ["+"] = OPC.ADD, ["-"] = OPC.SUB, ["*"] = OPC.MUL,
      ["/"] = OPC.DIV, ["//"] = OPC.IDIV, ["%"] = OPC.MOD, ["^"] = OPC.POW,
      ["&"] = OPC.BAND, ["|"] = OPC.BOR, ["~"] = OPC.BXOR,
      ["<<"] = OPC.SHL, [">>"] = OPC.SHR, [".."] = OPC.CONCAT,
    }
    -- For CONCAT chains (a..b..c..d), collect all operands first
    -- to avoid compile_expr being called multiple times on shared subexpressions
    if expr.op == ".." then
      local function collect_concat(node, out)
        if node.type == "binop" and node.op == ".." then
          collect_concat(node.left, out)
          collect_concat(node.right, out)
        else
          out[#out + 1] = node
        end
      end
      local operands = {}
      collect_concat(expr, operands)
      -- Compile all operands once, then move to contiguous registers
      -- This ensures CONCAT's [B,C] range has no gaps (e.g. from CALL args)
      local tmp_regs = {}
      for i, op in ipairs(operands) do
        tmp_regs[i] = self:compile_expr(op)
      end
      -- Allocate contiguous registers and MOVE operands into them
      local concat_regs = {}
      for i = 1, #operands do
        concat_regs[i] = self:alloc_reg()
      end
      for i = 1, #operands do
        self:emit(OPC.MOVE, concat_regs[i], tmp_regs[i], 0)
      end
      -- Free original temp registers
      for i = 1, #operands do self:free_reg(tmp_regs[i]) end
      -- Emit single CONCAT with contiguous range
      if #operands > 1 then
        self:emit(OPC.CONCAT, concat_regs[1], concat_regs[1], concat_regs[#operands])
      end
      -- Free all but result
      for i = 2, #operands do self:free_reg(concat_regs[i]) end
      return concat_regs[1]
    end
    local lr = self:compile_expr(expr.left)
    local rr = self:compile_expr(expr.right)
    if opcodes[expr.op] then
      self:emit(opcodes[expr.op], lr, lr, rr)
      self:free_reg(rr)
      return lr
    end
    -- Comparison operators: produce a boolean result
    local cmp_ops = {["=="]=OPC.EQ, ["~="]=OPC.EQ, ["<"]=OPC.LT, [">"]=OPC.LT, ["<="]=OPC.LE, [">="]=OPC.LE}
    if cmp_ops[expr.op] then
      local r = self:alloc_reg()
      -- For > and >=, swap operands so we can use < and <=
      local op1, op2 = lr, rr
      if expr.op == ">" or expr.op == ">=" then
        op1, op2 = rr, lr
      end
      -- A=0: skip next if condition TRUE;  A=1: skip next if condition FALSE
      -- For ==/<,<=: condition TRUE → A=0
      -- For ~=: condition TRUE is "not equal" → EQ A=1 skips when not-equal
      local cmp_a = (expr.op == "~=") and 1 or 0
      self:emit(cmp_ops[expr.op], cmp_a, op1, op2)
      self:emit(OPC.LOADBOOL, r, 0, 1)  -- false + skip next
      self:emit(OPC.LOADBOOL, r, 1, 0)  -- true
      self:free_reg(lr)
      self:free_reg(rr)
      return r
    end
    -- Logical
    if expr.op == "and" or expr.op == "or" then
      -- Simplified: evaluate both sides
      self:free_reg(lr)
      return rr
    end
    self:free_reg(lr)
    self:free_reg(rr)
    return lr
  end
  
  if expr.type == "unop" then
    local r = self:compile_expr(expr.expr)
    if expr.op == "-" then
      self:emit(OPC.UNM, r, r, 0)
    elseif expr.op == "not" then
      self:emit(OPC.NOT, r, r, 0)
    elseif expr.op == "#" then
      self:emit(OPC.LEN, r, r, 0)
    elseif expr.op == "~" then
      self:emit(OPC.BNOT, r, r, 0)
    end
    return r
  end
  
  if expr.type == "index" then
    local obj_r = self:compile_expr(expr.obj)
    local key_r = self:compile_expr(expr.key)
    self:emit(OPC.GETTABLE, obj_r, obj_r, key_r)
    self:free_reg(key_r)
    return obj_r
  end
  
  if expr.type == "call" then
    local func_r = self:compile_expr(expr.func)
    local base = func_r
    local nargs = 0
    if expr.args then
      for i, arg in ipairs(expr.args) do
        local ar = self:compile_expr(arg)
        if ar ~= base + i then
          self:emit(OPC.MOVE, base + i, ar, 0)
        end
        nargs = nargs + 1
      end
    end
    self:emit(OPC.CALL, base, nargs + 1, 2)
    return base
  end
  
  if expr.type == "table" then
    -- Special case: {...} - rewrite to use select-based loop
    if #expr.fields == 1 and not expr.fields[1].key and expr.fields[1].value.type == "vararg" then
      -- Use _pack() global helper registered by exec_proto to pack varargs into a table
      local tbl_r = self:alloc_reg()
      local fn_r = self:alloc_reg()
      local pack_k = self:add_const("_pack")
      self:emit(OPC.GETGLOBAL, fn_r, pack_k, 0)
      self:emit(OPC.CALL, fn_r, 1, 2)  -- CALL fn, 0 args, 1 result
      self:emit(OPC.MOVE, tbl_r, fn_r, 0)
      self:free_reg(fn_r)
      return tbl_r
    end
    local r = self:alloc_reg()
    self:emit(OPC.NEWTABLE, r, 0, 0)
    local arr_idx = 0
    for _, field in ipairs(expr.fields) do
      if field.key then
        local kr = self:compile_expr(field.key)
        local vr = self:compile_expr(field.value)
        self:emit(OPC.SETTABLE, r, kr, vr)
        self:free_reg(kr)
        self:free_reg(vr)
      else
        -- Array-style: use numeric index
        arr_idx = arr_idx + 1
        local kr = self:alloc_reg()
        local vr = self:compile_expr(field.value)
        self:emit(OPC.LOADK, kr, self:add_const(arr_idx), 0)
        self:emit(OPC.SETTABLE, r, kr, vr)
        self:free_reg(kr)
        self:free_reg(vr)
      end
    end
    return r
  end
  
  if expr.type == "func_def" then
    return self:compile_func_def(expr)
  end
  
  -- Fallback
  local r = self:alloc_reg()
  self:emit(OPC.LOADNIL, r, 0, 0)
  return r
end

function Compiler:get_proto()
  return {
    code = self.code,
    constants = self.constants,
    numparams = 0,
    maxstack = self.reg_count + 1,
  }
end

------------------------------------------------------------
-- 字节码编码（混淆 + 加密）
------------------------------------------------------------
-- 字节码编码（op 池映射 + 字符池 + 整表加密）
------------------------------------------------------------

local OPC_NAMES = {
  {"NOP", 0}, {"LOADK", 1}, {"LOADBOOL", 2}, {"LOADNIL", 3},
  {"MOVE", 4}, {"GETGLOBAL", 5}, {"SETGLOBAL", 6},
  {"GETTABLE", 7}, {"SETTABLE", 8}, {"NEWTABLE", 9},
  {"ADD", 10}, {"SUB", 11}, {"MUL", 12}, {"DIV", 13}, {"MOD", 14}, {"POW", 15},
  {"BAND", 16}, {"BOR", 17}, {"BXOR", 18}, {"SHL", 19}, {"SHR", 20},
  {"UNM", 21}, {"BNOT", 22}, {"NOT", 23}, {"LEN", 24}, {"CONCAT", 25},
  {"EQ", 26}, {"LT", 27}, {"LE", 28},
  {"JMP", 29}, {"TEST", 30}, {"TESTSET", 31},
  {"CALL", 32}, {"TAILCALL", 33}, {"RETURN", 34},
  {"FORPREP", 35}, {"FORLOOP", 36},
  {"TFORPREP", 37}, {"TFORCALL", 38}, {"TFORLOOP", 39},
  {"SETLIST", 40}, {"CLOSURE", 41}, {"VARARG", 42},
  {"EXTRARG", 43}, {"GETUPVAL", 44}, {"SETUPVAL", 45},
  {"IDIV", 55},
}

local function shuffle_list(t)
  for i = #t, 2, -1 do
    local j = math.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

local function build_op_map()
  local n = #OPC_NAMES
  local runtime_ids = {}
  for i = 1, n do runtime_ids[i] = i - 1 end
  shuffle_list(runtime_ids)
  local op_map = {}
  local name_to_rt = {}
  for i, entry in ipairs(OPC_NAMES) do
    local name, logical = entry[1], entry[2]
    local rt = runtime_ids[i]
    op_map[logical] = rt
    name_to_rt[name] = rt
  end
  return op_map, name_to_rt
end

local function build_char_pool(proto)
  local seen = {}
  local pool = {}

  local function add_bytes(s)
    if type(s) ~= "string" then return end
    for i = 1, #s do
      local b = string.byte(s, i)
      if not seen[b] then
        seen[b] = true
        pool[#pool + 1] = b
      end
    end
  end

  local function walk(p)
    for _, k in ipairs(p.constants or {}) do
      if type(k) == "string" then
        add_bytes(k)
      elseif type(k) == "number" then
        add_bytes(tostring(k))
      elseif type(k) == "table" and k.code then
        walk(k)
      end
    end
    for _, uv in ipairs(p.upvalues or {}) do
      add_bytes(uv.name or "")
    end
  end
  walk(proto)

  for _ = 1, math.random(4, 16) do
    local b = math.random(0, 255)
    if not seen[b] then
      seen[b] = true
      pool[#pool + 1] = b
    end
  end
  if #pool == 0 then
    pool[1] = 0
  end
  shuffle_list(pool)

  local byte_to_idx = {}
  for i, b in ipairs(pool) do
    byte_to_idx[b] = i
  end
  local pool_key = math.random(1, 255)
  local encrypted = {}
  for i, b in ipairs(pool) do
    encrypted[i] = b ~ pool_key
  end
  return encrypted, byte_to_idx, pool_key
end

local function encode_string_via_pool(s, byte_to_idx, parts)
  parts[#parts + 1] = #s
  for i = 1, #s do
    local b = string.byte(s, i)
    parts[#parts + 1] = byte_to_idx[b] or 1
  end
end

local function encode_proto(proto, key, op_map, byte_to_idx)
  local parts = {}
  parts[#parts + 1] = proto.numparams
  parts[#parts + 1] = proto.maxstack
  parts[#parts + 1] = #proto.constants
  parts[#parts + 1] = #proto.code

  for _, k in ipairs(proto.constants) do
    if type(k) == "number" then
      parts[#parts + 1] = 1
      encode_string_via_pool(tostring(k), byte_to_idx, parts)
    elseif type(k) == "string" then
      parts[#parts + 1] = 2
      encode_string_via_pool(k, byte_to_idx, parts)
    elseif type(k) == "boolean" then
      parts[#parts + 1] = 3
      parts[#parts + 1] = k and 1 or 0
    elseif type(k) == "table" then
      parts[#parts + 1] = 4
      local sub = encode_proto(k, key, op_map, byte_to_idx)
      for _, v in ipairs(sub) do parts[#parts + 1] = v end
      parts[#parts + 1] = 0
    end
  end
  parts[#parts + 1] = 0

  for _, instr in ipairs(proto.code) do
    parts[#parts + 1] = op_map[instr.op] or instr.op
    parts[#parts + 1] = instr.a
    parts[#parts + 1] = instr.b
    parts[#parts + 1] = instr.c
  end

  local uvs = proto.upvalues or {}
  parts[#parts + 1] = #uvs
  for _, uv in ipairs(uvs) do
    parts[#parts + 1] = uv.reg
    encode_string_via_pool(uv.name or "", byte_to_idx, parts)
  end

  for i, v in ipairs(parts) do
    if type(v) == "number" and v < 0 then
      parts[i] = v & 0xFFFFFFFF
    end
  end
  return parts
end

local function generate_vm_source(proto, key)
  local op_map, name_to_rt = build_op_map()
  local char_pool_enc, byte_to_idx, pool_key = build_char_pool(proto)
  local encoded = encode_proto(proto, key, op_map, byte_to_idx)

  local seed = math.random(1000, 9999)
  local cs = seed
  for i, v in ipairs(encoded) do cs = (cs + v * (i + seed)) % 65536 end
  for i, v in ipairs(encoded) do
    encoded[i] = v ~ key
  end
  local data_str = table.concat(encoded, ",")
  local chars_str = table.concat(char_pool_enc, ",")

  local names_order = {
    "NOP","LOADK","LOADBOOL","LOADNIL","MOVE","GETGLOBAL","SETGLOBAL",
    "GETUPVAL","SETUPVAL","GETTABLE","SETTABLE","NEWTABLE",
    "ADD","SUB","MUL","DIV","IDIV","MOD","POW",
    "BAND","BOR","BXOR","SHL","SHR",
    "UNM","BNOT","NOT","LEN","CONCAT",
    "EQ","LT","LE","JMP","TEST","TESTSET",
    "CALL","TAILCALL","RETURN","FORPREP","FORLOOP",
    "TFORPREP","TFORCALL","TFORLOOP","CLOSURE","VARARG","EXTRARG","SETLIST",
  }
  local op_locals = {}
  for _, nm in ipairs(names_order) do
    op_locals[#op_locals + 1] = string.format("  local OP_%s = %d", nm, name_to_rt[nm] or 0)
  end
  local op_locals_str = table.concat(op_locals, "\n")

  -- Template uses %% for literal % in string.format
  local tpl = [====[
-- VM Protected Code (op-pool + char-pool)
do
  local _d = {%s}
  local _chars = {%s}
  local _k = %d
  local _ck = %d
  local _cs_seed = %d
  local _cs_expect = %d

  for _i = 1, #_d do _d[_i] = _d[_i] ~ _k end

  local function _dec_str(di, len)
    local t = {}
    for i = 1, len do
      local idx = _d[di]; di = di + 1
      t[i] = string.char((_chars[idx] or 0) ~ _ck)
    end
    return table.concat(t), di
  end

%s

  local function decode_proto(di)
    local np = _d[di]; di = di + 1
    local ms = _d[di]; di = di + 1
    local nk = _d[di]; di = di + 1
    local nc = _d[di]; di = di + 1
    local consts = {}
    for _ci = 1, nk do
      local t = _d[di]; di = di + 1
      if t == 0 then break end
      if t == 1 then
        local sl = _d[di]; di = di + 1
        local s; s, di = _dec_str(di, sl)
        consts[#consts + 1] = tonumber(s)
      elseif t == 2 then
        local sl = _d[di]; di = di + 1
        local s; s, di = _dec_str(di, sl)
        consts[#consts + 1] = s
      elseif t == 3 then
        consts[#consts + 1] = _d[di] == 1; di = di + 1
      elseif t == 4 then
        local sub, new_di = decode_proto(di)
        consts[#consts + 1] = sub
        di = new_di + 1
      end
    end
    di = di + 1
    local code = {}
    for _ = 1, nc do
      code[#code + 1] = { op = _d[di], a = _d[di+1], b = _d[di+2], c = _d[di+3] }
      di = di + 4
    end
    local nuv = _d[di]; di = di + 1
    local upvalues = {}
    for _ = 1, nuv do
      local uv_reg = _d[di]; di = di + 1
      local name_len = _d[di]; di = di + 1
      local nm; nm, di = _dec_str(di, name_len)
      upvalues[#upvalues + 1] = { reg = uv_reg, name = nm }
    end
    return { code = code, constants = consts, numparams = np, maxstack = ms, upvalues = upvalues }, di
  end

  local _orig_pack = _G._pack

  local function exec_proto(proto, regs, base, nargs, upvals, varargs)
    _G._pack = function()
      local t = {}
      if varargs then for i = 1, #varargs do t[i] = varargs[i] end end
      return t
    end
    local code = proto.code
    local consts = proto.constants
    local pc = 1
    local A, B, C

    local H = {}

    H[OP_NOP] = function() end
    H[OP_LOADK] = function()
      regs[base + A] = consts[B]
    end
    H[OP_LOADBOOL] = function()
      regs[base + A] = B ~= 0
      if C ~= 0 then pc = pc + 1 end
    end
    H[OP_LOADNIL] = function()
      for i = 0, B do regs[base + A + i] = nil end
    end
    H[OP_MOVE] = function()
      regs[base + A] = regs[base + B]
    end
    H[OP_GETGLOBAL] = function()
      regs[base + A] = _G[consts[B]]
    end
    H[OP_SETGLOBAL] = function()
      _G[consts[B]] = regs[base + A]
    end
    H[OP_GETUPVAL] = function()
      if upvals and upvals[B + 1] then
        local uv = upvals[B + 1]
        regs[base + A] = uv[1][uv[2]]
      end
    end
    H[OP_SETUPVAL] = function()
      if upvals and upvals[B + 1] then
        local uv = upvals[B + 1]
        uv[1][uv[2]] = regs[base + A]
      end
    end
    H[OP_GETTABLE] = function()
      local t = regs[base + B]
      if type(t) == "table" then
        regs[base + A] = t[regs[base + C]]
      else
        regs[base + A] = nil
      end
    end
    H[OP_SETTABLE] = function()
      local t = regs[base + A]
      if type(t) == "table" then t[regs[base + B]] = regs[base + C] end
    end
    H[OP_NEWTABLE] = function()
      regs[base + A] = {}
    end
    H[OP_ADD] = function()
      local l, r = regs[base + B], regs[base + C]
      regs[base + A] = (type(l) == "number" and type(r) == "number") and (l + r) or (tonumber(l) or 0) + (tonumber(r) or 0)
    end
    H[OP_SUB] = function()
      regs[base + A] = regs[base + B] - regs[base + C]
    end
    H[OP_MUL] = function()
      regs[base + A] = regs[base + B] * regs[base + C]
    end
    H[OP_DIV] = function()
      regs[base + A] = regs[base + B] / regs[base + C]
    end
    H[OP_IDIV] = function()
      regs[base + A] = regs[base + B] // regs[base + C]
    end
    H[OP_MOD] = function()
      regs[base + A] = regs[base + B] %% regs[base + C]
    end
    H[OP_POW] = function()
      regs[base + A] = regs[base + B] ^ regs[base + C]
    end
    H[OP_BAND] = function()
      regs[base + A] = regs[base + B] & regs[base + C]
    end
    H[OP_BOR] = function()
      regs[base + A] = regs[base + B] | regs[base + C]
    end
    H[OP_BXOR] = function()
      regs[base + A] = regs[base + B] ~ regs[base + C]
    end
    H[OP_SHL] = function()
      regs[base + A] = regs[base + B] << regs[base + C]
    end
    H[OP_SHR] = function()
      regs[base + A] = regs[base + B] >> regs[base + C]
    end
    H[OP_UNM] = function()
      regs[base + A] = -regs[base + B]
    end
    H[OP_BNOT] = function()
      regs[base + A] = ~regs[base + B]
    end
    H[OP_NOT] = function()
      regs[base + A] = not regs[base + B]
    end
    H[OP_LEN] = function()
      regs[base + A] = #regs[base + B]
    end
    H[OP_CONCAT] = function()
      local v = regs[base + B]
      local s = type(v) == 'string' and v or tostring(v)
      for j = B + 1, C do
        v = regs[base + j]
        s = s .. (type(v) == 'string' and v or tostring(v))
      end
      regs[base + A] = s
    end
    H[OP_EQ] = function()
      local eq = (regs[base + B] == regs[base + C])
      if (eq and A == 0) or (not eq and A == 1) then pc = pc + 1 end
    end
    H[OP_LT] = function()
      local lt = (regs[base + B] < regs[base + C])
      if (lt and A == 0) or (not lt and A == 1) then pc = pc + 1 end
    end
    H[OP_LE] = function()
      local le = (regs[base + B] <= regs[base + C])
      if (le and A == 0) or (not le and A == 1) then pc = pc + 1 end
    end
    H[OP_JMP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      pc = pc + sBx
    end
    H[OP_FORPREP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      regs[base + A] = regs[base + A] - regs[base + A + 2]
      pc = pc + sBx
    end
    H[OP_FORLOOP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      regs[base + A] = regs[base + A] + regs[base + A + 2]
      local step = regs[base + A + 2]
      local limit = regs[base + A + 1]
      local idx = regs[base + A]
      local cont = ((step > 0) and (idx <= limit)) or ((step <= 0) and (idx >= limit))
      if cont then
        regs[base + A + 3] = idx
        pc = pc + sBx
      end
    end
    H[OP_TFORLOOP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      if regs[base + A + 3] ~= nil then
        regs[base + A + 2] = regs[base + A + 3]
        pc = pc + sBx
      end
    end
    H[OP_TFORCALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local results = {fn(regs[base + A + 1], regs[base + A + 2])}
        for j = 1, C do
          regs[base + A + 2 + j] = results[j]
        end
      end
    end
    H[OP_TFORPREP] = function()
      local sBx = B
      if sBx > 0x7FFFFFFF then sBx = sBx - 0x100000000 end
      pc = pc + sBx
    end
    H[OP_TEST] = function()
      local v = regs[base + A]
      local truthy = v and v ~= false
      if (truthy and C == 0) or (not truthy and C ~= 0) then pc = pc + 1 end
    end
    H[OP_TESTSET] = function()
      local v = regs[base + B]
      local truthy = v and v ~= false
      if (truthy and C == 0) or (not truthy and C ~= 0) then
        pc = pc + 1
      else
        regs[base + A] = v
      end
    end
    H[OP_CALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local nargs = B - 1
        local results
        if nargs <= 0 then
          results = {fn()}
        elseif nargs == 1 then
          results = {fn(regs[base + A + 1])}
        elseif nargs == 2 then
          results = {fn(regs[base + A + 1], regs[base + A + 2])}
        elseif nargs == 3 then
          results = {fn(regs[base + A + 1], regs[base + A + 2], regs[base + A + 3])}
        else
          local args = {}
          for j = 1, nargs do args[j] = regs[base + A + j] end
          results = {fn(table.unpack(args))}
        end
        if C > 0 then
          for j = 1, C - 1 do
            regs[base + A + j - 1] = results[j]
          end
        else
          regs[base + A] = results[1]
        end
      end
    end
    H[OP_TAILCALL] = function()
      local fn = regs[base + A]
      if type(fn) == "function" then
        local nargs = B - 1
        if nargs <= 0 then return "RET", {fn()}
        elseif nargs == 1 then return "RET", {fn(regs[base + A + 1])}
        elseif nargs == 2 then return "RET", {fn(regs[base + A + 1], regs[base + A + 2])}
        elseif nargs == 3 then return "RET", {fn(regs[base + A + 1], regs[base + A + 2], regs[base + A + 3])}
        else
          local args = {}
          for j = 1, nargs do args[j] = regs[base + A + j] end
          return "RET", {fn(table.unpack(args))}
        end
      end
    end
    H[OP_RETURN] = function()
      if B >= 2 then
        local results = {}
        for j = 0, B - 2 do results[j + 1] = regs[base + A + j] end
        return "RET", results
      elseif B == 1 then
        return "RET", {regs[base + A]}
      else
        return "RET", {}
      end
    end
    H[OP_CLOSURE] = function()
      local sub_proto = consts[B]
      if type(sub_proto) == "table" and sub_proto.code then
        local captured_upvals = {}
        if sub_proto.upvalues then
          for ui, uv_desc in ipairs(sub_proto.upvalues) do
            captured_upvals[ui] = { regs, base + uv_desc.reg }
          end
        end
        regs[base + A] = function(...)
          local sub_regs = {}
          local args = {...}
          local n = select("#", ...)
          for ai = 1, sub_proto.numparams do
            sub_regs[ai - 1] = args[ai]
          end
          local vargs = {}
          for vi = sub_proto.numparams + 1, n do
            vargs[#vargs + 1] = args[vi]
          end
          return exec_proto(sub_proto, sub_regs, 0, n, captured_upvals, vargs)
        end
      end
    end
    H[OP_VARARG] = function()
      if B == 0 then
        if varargs then
          for j = 1, #varargs do
            regs[base + A + j - 1] = varargs[j]
          end
        end
      else
        for j = 0, B - 2 do
          regs[base + A + j] = varargs and varargs[j + 1] or nil
        end
      end
    end
    H[OP_SETLIST] = function()
      local t = regs[base + A]
      if type(t) == "table" then
        for j = 1, C do
          t[B + j - 1] = regs[base + A + j]
        end
      end
    end
    H[OP_EXTRARG] = function() end

    -- Safety: hard step limit prevents browser hang if bytecode is corrupted
    local _steps = 0
    local _max_steps = 5000000
    while pc <= #code do
      _steps = _steps + 1
      if _steps > _max_steps then
        error("VM step limit exceeded (possible infinite loop)")
      end
      local ins = code[pc]
      local op = ins.op
      A, B, C = ins.a, ins.b, ins.c
      pc = pc + 1
      local h = H[op]
      if h then
        local tag, pack = h()
        if tag == "RET" then
          return table.unpack(pack or {})
        end
      end
    end
  end

  local _cs = _cs_seed
  for _i = 1, #_d do
    _cs = (_cs + _d[_i] * (_i + _cs_seed)) & 0xFFFF
  end
  if _cs ~= _cs_expect then
    error('integrity check failed')
  end

  local main_proto = decode_proto(1)
  local regs = {}
  exec_proto(main_proto, regs, 0, 0, nil)
  _G._pack = _orig_pack
end
]====]

  return string.format(tpl, data_str, chars_str, key, pool_key, seed, cs, op_locals_str)
end

local function vm_protect(source_code)
  math.randomseed(math.floor(os.time() + os.clock() * 10000))
  local function random_int(min, max)
    return math.random(min, max)
  end

  -- Parse
  local parser = Parser.new(source_code)
  local ast = parser:parse_block()

  -- Compile
  local compiler = Compiler.new()
  compiler:compile_block(ast)
  compiler:resolve_gotos()  -- resolve goto -> label jumps
  -- Add return if missing
  if #compiler.code == 0 or compiler.code[#compiler.code].op ~= OPC.RETURN then
    compiler:emit(OPC.RETURN, 0, 1, 0)
  end
  local proto = compiler:get_proto()

  -- Generate VM
  local key = random_int(1, 0xFFFFFF)
  local vm_code = generate_vm_source(proto, key)

  return vm_code
end

------------------------------------------------------------
-- 导出
------------------------------------------------------------
local M = {}

function M.protect(source_code)
  return vm_protect(source_code)
end

function M.version()
  return VERSION
end

-- Debug: expose internals
M._Parser = Parser
M._Compiler = Compiler
M._OPC = OPC
return M
