local M={}
M.name="vm_function";M.title="函数级VM保护";M.description="对指定顶层函数进行VM字节码虚拟化保护";M.version="2.10.0";M.author="Rainy_qwq";M.order=5;M.enabled=false

local function find_function_end(code_lines,func_line)
  local state=0;local pd=0;local depth=1
  local found_params=false
  for li=func_line,#code_lines do
    local cl=code_lines[li]
    local j=1
    while j<=#cl do
      local c=cl:sub(j,j)
      if state==0 then
        if c=="("then state=1;pd=1 end
      elseif state==1 then
        if c=="("then pd=pd+1 elseif c==")"then pd=pd-1;if pd==0 then state=2 end end
      end
      j=j+1
    end
    if state==2 then
      if not found_params then
        found_params=true
      else
        for _ in cl:gmatch("function%s")do depth=depth+1 end
        for _ in cl:gmatch("for%s")do depth=depth+1 end
        for _ in cl:gmatch("if%s")do depth=depth+1 end
        for _ in cl:gmatch("while%s")do depth=depth+1 end
        for _ in cl:gmatch("repeat%s")do depth=depth+1 end
        local i=1
        while i<=#cl do
          local ei=cl:find("end",i,true)
          if not ei then break end
          local bok=(ei==1)or not cl:sub(ei-1,ei-1):match("[%w_]")
          local aok=(ei+3>#cl)or not cl:sub(ei+3,ei+3):match("[%w_]")
          if bok and aok then depth=depth-1;if depth==0 then return li end end
          i=ei+1
        end
      end
    end
  end
end

local function is_recursive(func_body, func_name)
  local pattern = func_name .. "%s*%("
  local first_line = true
  for line in func_body:gmatch("[^\n]+") do
    if first_line then
      first_line = false
    elseif not line:match("^%s*%-%-") then
      if line:match(pattern) then
        return true
      end
    end
  end
  return false
end

function M.apply(code,ctx)
  -- Strip UTF-8 BOM if present
  if code:sub(1,3) == "\239\187\191" then code = code:sub(4) end
  local vm=ctx.vm_module or require("passes.vm")
  local code_lines={}
  for line in code:gmatch("[^\n]*\n?")do code_lines[#code_lines+1]=line end
  local annotated={};local i=1
  while i<=#code_lines do
    local line=code_lines[i]
    if line:match("^%s*%-%-%s*@vm")then
      local j=i+1
      while j<=#code_lines and code_lines[j]:match("^%s*$")do j=j+1 end
      local fl=code_lines[j]
      local name=fl and fl:match("^%s*local%s+function%s+([%w_]+)")
      if name then
        local finish=find_function_end(code_lines,j)
        if finish then annotated[#annotated+1]={start=i,finish=finish,name=name};i=finish+1 else i=i+1 end
      else i=i+1 end
    else i=i+1 end
  end
  if #annotated==0 then return code end
  local replacements={}
  for _,ann in ipairs(annotated)do
    local fs={};for li=ann.start+1,ann.finish do fs[#fs+1]=code_lines[li]end
    fs=table.concat(fs,"\n")
    local bl={};local inf=false
    for line in fs:gmatch("[^\n]*\n?")do
      if not inf then if line:match("local%s+function%s+")then inf=true end end
      if inf then bl[#bl+1]=line end
    end
    local bs=table.concat(bl,"\n")
    if is_recursive(bs, ann.name) then
      replacements[#replacements+1]={start=ann.start,finish=ann.finish,new_src=nil}
    else
      local ok,vmr=pcall(vm.protect_as_expr,bs)
      if not ok then error("VM函数保护失败 ["..ann.name.."]: "..tostring(vmr))end
      replacements[#replacements+1]={start=ann.start,finish=ann.finish,new_src=vmr}
    end
  end
  local out={};local cur=1
  table.sort(replacements,function(a,b)return a.start>b.start end)
  for _,rep in ipairs(replacements)do
    while cur<rep.start do out[#out+1]=code_lines[cur];cur=cur+1 end
    if rep.new_src then
      cur=rep.finish+1
      out[#out+1]="-- @vm (protected)"
      for line in rep.new_src:gmatch("[^\n]*\n?")do out[#out+1]=line end
    else
      out[#out+1]="-- @vm (skipped: recursive)"
    end
  end
  while cur<=#code_lines do out[#out+1]=code_lines[cur];cur=cur+1 end
  return table.concat(out,"\n")
end

return M
