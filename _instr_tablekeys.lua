-- Heavier instrumentation: wrap every "i = i + 1" site is hard; instead, add
-- a guard macro. Simplest: after each inner while, we can't easily instrument.
-- Instead, re-run but check: which byte does it get stuck on? Add a global
-- "i hasn't moved" detector using a snapshot of i at the TOP of each outer
-- iteration AND a per-inner-loop cap.

local f = io.open("_vmout.lua", "r")
local code = f:read("*a"); f:close()
local len = #code
print("code length:", len); io.flush()

local function report(tag, i)
  print(string.format("  [%s] stuck at i=%d byte=%s ctx=%q", tag, i, tostring(code:byte(i)), code:sub(math.max(1,i-30), i+30)))
  io.flush()
end

local function collect_table_keys(code)
  local keys = {}
  local i = 1
  local len = #code
  local outer_iters = 0
  while i <= len do
    outer_iters = outer_iters + 1
    if outer_iters > 500000 then report("OUTER", i); return keys end
    local prev_i = i
    local b = code:byte(i)
    if b == 95 and code:sub(i, i+3) == "__ST" then
      local ep = code:find("__", i+5, true); i = ep and (ep+2) or (i+1)
    elseif b == 45 and i < len and code:byte(i+1) == 45 then
      local nl = code:find("\n", i+2, true); i = nl and (nl+1) or (len+1)
    elseif b == 34 or b == 39 then
      local q = b; i = i + 1
      local cap = 0
      while i <= len do
        cap = cap + 1; if cap > len + 5 then report("STR", i); break end
        if code:byte(i) == 92 then i = i + 2
        elseif code:byte(i) == q then i = i + 1; break
        else i = i + 1 end
      end
    elseif b == 91 then
      i = i + 1; local depth = 1; local cap = 0
      while i <= len and depth > 0 do
        cap = cap + 1; if cap > len + 5 then report("BRACKET", i); break end
        local cb = code:byte(i)
        if cb == 91 then depth = depth + 1
        elseif cb == 93 then depth = depth - 1
        elseif cb == 34 or cb == 39 then
          local q2 = cb; i = i + 1
          while i <= len do
            if code:byte(i) == 92 then i = i + 2
            elseif code:byte(i) == q2 then i = i + 1; break
            else i = i + 1 end
          end
        else i = i + 1 end
      end
    elseif b == 123 then
      i = i + 1; local depth = 1; local cap = 0
      while i <= len and depth > 0 do
        cap = cap + 1; if cap > len + 5 then report("BRACE", i); break end
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
          local start = i; i = i + 1
          while i <= len do
            local ib = code:byte(i)
            if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
          end
          local key = code:sub(start, i - 1)
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if code:byte(i) == 61 then keys[key] = true; i = i + 1 end
        else i = i + 1 end
      end
    elseif (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
      local start = i; i = i + 1
      while i <= len do
        local ib = code:byte(i)
        if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
      end
      local idname = code:sub(start, i-1)
      local kw = {["local"]=1,["function"]=1,["if"]=1,["for"]=1,["while"]=1,["return"]=1,["end"]=1,["then"]=1,["do"]=1,["else"]=1,["or"]=1,["and"]=1,["not"]=1,["in"]=1,["repeat"]=1,["until"]=1,["break"]=1,["goto"]=1}
      if not kw[idname] then
        while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
        if code:byte(i) == 46 then
          i = i + 1
          while i <= len and (code:byte(i) == 32 or code:byte(i) == 9) do i = i + 1 end
          if (code:byte(i) >= 65 and code:byte(i) <= 90) or (code:byte(i) >= 97 and code:byte(i) <= 122) or code:byte(i) == 95 then
            local fstart = i; i = i + 1
            while i <= len do
              local ib = code:byte(i)
              if (ib >= 48 and ib <= 57) or (ib >= 65 and ib <= 90) or (ib >= 97 and ib <= 122) or ib == 95 then i = i + 1 else break end
            end
            local fieldname = code:sub(fstart, i-1); keys[fieldname] = true
          end
        end
      end
    else
      i = i + 1
    end
    if i == prev_i then report("OUTER-STUCK", i); return keys end
  end
  print("  collect_table_keys done, outer_iters:", outer_iters)
  return keys
end

print("running..."); io.flush()
collect_table_keys(code)
print("done"); io.flush()
