local f = io.open("_vmout.lua", "r")
local code = f:read("*a"); f:close()
local len = #code
print("code length:", len); io.flush()

local function is_digit(b) return b>=48 and b<=57 end
local function is_id_start(b) return (b>=65 and b<=90) or (b>=97 and b<=122) or b==95 end
local function is_id_char(b) return is_id_start(b) or (b>=48 and b<=57) end
local BYTE_DOT = string.byte(".")

local function report(tag, i)
  print(string.format("  [%s] stuck at i=%d byte=%s ctx=%q", tag, i, tostring(code:byte(i)), code:sub(math.max(1,i-30), i+30)))
  io.flush()
end

local function scan_identifiers(code)
  local ids = {}
  local n = 0
  local pos = 1
  local len = #code
  local iters = 0
  while pos <= len do
    iters = iters + 1
    if iters > 5000000 then report("SCAN", pos); return ids end
    local prev = pos
    local b = code:byte(pos)
    if b == 95 and code:sub(pos, pos + 3) == "__ST" then
      local end_pos = code:find("__", pos + 5, true)
      if end_pos then pos = end_pos + 2 else pos = pos + 1 end
    elseif b == 45 and pos < len and code:byte(pos + 1) == 45 then
      local nl = code:find("\n", pos + 2, true)
      pos = nl and (nl + 1) or (len + 1)
    elseif is_id_start(b) then
      local is_scientific_e = false
      if (b == 101 or b == 69) and pos > 1 then
        local prevb = code:byte(pos - 1)
        if is_digit(prevb) or prevb == BYTE_DOT then
          pos = pos + 1
          if pos <= len then
            local sign = code:byte(pos)
            if sign == 43 or sign == 45 then pos = pos + 1 end
          end
          while pos <= len and is_digit(code:byte(pos)) do pos = pos + 1 end
          is_scientific_e = true
        end
      end
      if not is_scientific_e then
        local start = pos
        pos = pos + 1
        while pos <= len and is_id_char(code:byte(pos)) do pos = pos + 1 end
        local name = code:sub(start, pos - 1)
        n = n + 1
        ids[n] = { name = name, start = start, stop = pos - 1 }
      end
    else
      pos = pos + 1
    end
    if pos == prev then report("SCAN-STUCK", pos); return ids end
  end
  print("  scan_identifiers done, iters:", iters, "ids:", n)
  return ids
end

print("running scan_identifiers..."); io.flush()
scan_identifiers(code)
print("done"); io.flush()
