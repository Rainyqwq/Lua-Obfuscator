-- 85项功能正确性测试（覆盖所有Lua语言特性）
local tests = {}
local function t(name, code, expected) tests[#tests+1]={name=name,code=code,expected=expected} end

-- 基础运算
t("整数加法","return 1+2","3")
t("整数减法","return 10-3","7")
t("整数乘法","return 4*5","20")
t("浮点运算","return 0.1+0.2","0.3")
t("取模","return 17%5","2")
t("幂运算","return 2^10","1024.0")
t("整除","return 17//5","3")
t("负数","return -42+10","-32")
t("一元负号","local a=5; return -a","-5")

-- 位运算
t("按位与","return 0xFF&0x0F","15")
t("按位或","return 0xF0|0x0F","255")
t("按位异或","return 0xFF~0x0F","240")
t("左移","return 1<<8","256")
t("右移","return 256>>4","16")
t("按位取反","return ~0","-1")

-- 字符串
t("双引号字符串",'return "hello"',"hello")
t("单引号字符串","return 'world'","world")
t("字符串连接",'return "a".."b"',"ab")
t("字符串长度",'return #"abc"',"3")
t("多行字符串","return [[line1\nline2]]","line1\nline2")
t("转义换行",'return "a\\nb"',"a\nb")
t("转义制表",'return "a\\tb"',"a\tb")
t("转义反斜杠",'return "a\\\\b"',"a\\b")
t("转义引号",'return "a\\\"b"',"a\"b")
t("string.sub",'return string.sub("hello",2,4)',"ell")
t("string.rep",'return string.rep("ab",3)',"ababab")
t("string.reverse",'return string.reverse("abc")',"cba")
t("string.upper",'return string.upper("hi")',"HI")
t("string.lower",'return string.lower("HI")',"hi")
t("string.find",'return string.find("hello world","world")',"7")
t("string.format整数",'return string.format("%04d",42)',"0042")
t("string.format字符串",'return string.format("[%s]","x")',"[x]")
t("string.byte",'return string.byte("A")',"65")
t("string.char",'return string.char(65)',"A")
t("string.gsub",'return string.gsub("hello","l","r")',"herro")
t("string.match",'return string.match("abc123","%d+")',"123")
t("中英混合",'return "Hello你好World"',"Hello你好World")

-- 布尔和nil
t("true","return true","true")
t("false","return false","false")
t("nil","return nil","nil")
t("逻辑与真","return true and 42","42")
t("逻辑与假","return false and 42","false")
t("逻辑或真","return true or 42","true")
t("逻辑或假","return false or 99","99")
t("逻辑非","return not false","true")
t("双重非","return not not 1","true")

-- 比较
t("相等","return 1==1","true")
t("不等","return 1~=2","true")
t("小于","return 1<2","true")
t("大于","return 3>2","true")
t("小于等于相等","return 2<=2","true")
t("小于等于小于","return 1<=2","true")
t("大于等于相等","return 2>=2","true")
t("大于等于大于","return 3>=2","true")
t("字符串比较",'return "a"<"b"',"true")
t("nil比较","return nil==nil","true")

-- 变量和作用域
t("局部变量","local x=10; return x","10")
t("多变量赋值","local a,b=1,2; return a+b","3")
t("变量覆盖","local x=1; x=2; return x","2")
t("局部作用域","local x=1; do local x=2 end; return x","1")

-- 控制流
t("if-then","if true then return 1 end; return 0","1")
t("if-else","if false then return 1 else return 2 end","2")
t("if-elseif","if false then return 1 elseif true then return 2 else return 3 end","2")
t("嵌套if","if true then if true then return 42 end end; return 0","42")
t("if不等","if 1~=2 then return 1 end; return 0","1")

-- 循环
t("数值for","local s=0; for i=1,10 do s=s+i end; return s","55")
t("for步长","local s=0; for i=0,10,2 do s=s+i end; return s","30")
t("for倒序","local s=0; for i=10,1,-1 do s=s+i end; return s","55")
t("while","local s,i=0,1; while i<=10 do s=s+i; i=i+1 end; return s","55")
t("repeat-until","local s,i=0,0; repeat i=i+1; s=s+i until i>=10; return s","55")
t("break","local r=0; for i=1,100 do if i>5 then r=i; break end end; return r","6")
t("嵌套循环break","local found=false; for i=1,10 do for j=1,10 do if i*j==20 then found=true; break end end; if found then break end end; return found","true")
t("goto","local x=1; goto done; x=2; ::done::; return x","1")

-- 函数
t("简单函数","local function f(x) return x*2 end; return f(21)","42")
t("多返回值","local function f() return 1,2 end; local a,b=f(); return a+b","3")
t("递归","local function fact(n) if n<=1 then return 1 end; return n*fact(n-1) end; return fact(10)","3628800")
t("闭包","local function make(x) return function(y) return x+y end end; return make(10)(32)","42")
t("匿名函数","local f=function(x) return x+1 end; return f(41)","42")
t("可变参数","local function sum(...) local s=0; for _,v in ipairs({...}) do s=s+v end; return s end; return sum(1,2,3,4,5)","15")
t("嵌套函数","local function outer(x) local function inner(y) return x+y end; return inner(5) end; return outer(10)","15")
t("函数作为参数","local function apply(f,x) return f(x) end; return apply(function(n) return n*3 end,7)","21")
t("闭包计数器","local function ctr() local n=0; return function() n=n+1; return n end end; local c=ctr(); c(); c(); c(); return c()","4")
t("尾调用","local function f(n) if n<=0 then return 0 end; return f(n-1) end; return f(100)","0")

-- 表
t("表构造","local t={a=1,b=2}; return t.a+t.b","3")
t("表数字索引","local t={10,20,30}; return t[2]","20")
t("表赋值","local t={}; t[1]=42; return t[1]","42")
t("表长度","return #{1,2,3,4,5}","5")
t("表遍历","local t={a=1,b=2,c=3}; local s=0; for _,v in pairs(t) do s=s+v end; return s","6")
t("ipairs遍历","local t={10,20,30}; local s=0; for _,v in ipairs(t) do s=s+v end; return s","60")
t("表方法调用","local t={val=42,get=function(self) return self.val end}; return t:get()","42")
t("表构造器数字","local t={[1]='a',[2]='b'}; return t[1]..t[2]","ab")
t("嵌套表","local t={{1,2},{3,4}}; return t[1][2]+t[2][1]","5")
t("表解构","local a,b; local t={10,20}; a,b=t[1],t[2]; return a+b","30")

-- 数学库
t("math.abs","return math.abs(-42)","42")
t("math.max","return math.max(1,3,2)","3")
t("math.min","return math.min(1,3,2)","1")
t("math.floor","return math.floor(3.7)","3")
t("math.ceil","return math.ceil(3.2)","4")
t("math.sqrt","return math.sqrt(144)","12.0")
t("math.type整数","return math.type(42)","integer")
t("math.type浮点","return math.type(3.14)","float")

-- table库
t("table.insert","local t={}; table.insert(t,1); table.insert(t,2); return #t","2")
t("table.concat","local t={'a','b','c'}; return table.concat(t,',')","a,b,c")
t("table.sort","local t={3,1,2}; table.sort(t); return t[1]","1")
t("table.remove","local t={1,2,3}; table.remove(t,2); return #t","2")

-- 类型检查
t("type数字","return type(42)","number")
t("type字符串",'return type("hi")',"string")
t("type表","return type({})","table")
t("type函数","return type(print)","function")
t("type nil","return type(nil)","nil")
t("type布尔","return type(true)","boolean")
t("tostring","return tostring(42)","42")
t("tonumber",'return tonumber("42")',"42")
t("tonumber失败",'return tonumber("abc")',"nil")

-- 综合
t("斐波那契","local function fib(n) if n<=1 then return n end; local a,b=0,1; for i=2,n do a,b=b,a+b end; return b end; return fib(20)","6765")
t("冒泡排序","local t={5,3,1,4,2}; for i=1,#t do for j=1,#t-i do if t[j]>t[j+1] then t[j],t[j+1]=t[j+1],t[j] end end end; return t[1]..t[2]..t[3]..t[4]..t[5]","12345")
t("字符串处理",'local function trim(s) return s:match("^%s*(.-)%s*$") end; return trim("  hello  ")',"hello")
t("选择排序","local t={5,3,1,4,2}; for i=1,#t do local min=i; for j=i+1,#t do if t[j]<t[min] then min=j end end; t[i],t[min]=t[min],t[i] end; return t[1]..t[5]","15")
t("快速幂","local function pow(a,n) local r=1; while n>0 do if n%2==1 then r=r*a end; a=a*a; n=n//2 end; return r end; return pow(2,10)","1024")

-- 运行所有测试
local pass, fail = 0, 0
for i, tt in ipairs(tests) do
  local ok, result = pcall(function()
    local chunk = load("return (function()\n" .. tt.code .. "\nend)()")
    if not chunk then error("compile failed") end
    return tostring(chunk())
  end)
  local actual = ok and result or ("ERROR: " .. tostring(result))
  if actual == tt.expected then
    pass = pass + 1
  else
    fail = fail + 1
    io.write(string.format("  FAIL [%02d] %s: expected=[%s] actual=[%s]\n", i, tt.name, tt.expected, actual))
  end
end
print(string.format("\n结果: %d/%d 通过, %d 失败", pass, #tests, fail))
