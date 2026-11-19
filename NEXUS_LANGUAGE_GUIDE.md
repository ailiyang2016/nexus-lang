# Nexus 语言开发指南

> 适用版本：`nexus-release` 分发包（LLVM 后端，零外部 C 编译器依赖）
> 本指南的每个特性都在分发包的 `examples/` 与 `benchmarks/` 中可运行验证；文中代码均取自这些示例。
> 验证基线：`bash tests/run_examples.sh` ⇒ `pass=26 fail=0 skip=1`；`benchmarks/nex/*.nex` 与 `benchmarks/concurrent/*.nex` 全部编译并运行通过。

---

## 目录

1. [快速开始](#1-快速开始)
2. [词法与字面量](#2-词法与字面量)
3. [变量、类型与空安全](#3-变量类型与空安全)
4. [表达式与控制流](#4-表达式与控制流)
5. [函数与闭包](#5-函数与闭包)
6. [容器：List / Set / Dict](#6-容器list--set--dict)
7. [自定义类型：struct / class / enum](#7-自定义类型struct--class--enum)
8. [运算符与重载](#8-运算符与重载)
9. [泛型与 concept](#9-泛型与-concept)
10. [接口与动态分派](#10-接口与动态分派)
11. [扩展方法](#11-扩展方法)
12. [编译期能力：const fn 与 comptime](#12-编译期能力const-fn-与-comptime)
13. [反射、注解与切面](#13-反射注解与切面)
14. [并发：spawn 与 Channel](#14-并发spawn-与-channel)
15. [张量计算](#15-张量计算)
16. [模块与工程组织](#16-模块与工程组织)
17. [格式化输出](#17-格式化输出)
18. [性能实践](#18-性能实践)
19. [常见错误与排错](#19-常见错误与排错)
20. [附录](#20-附录)

---

## 1. 快速开始

### 1.1 分发包结构

```text
nexus-release/
├─ bin/nexus                   编译器（LLVM 后端）
├─ bin/libnexus_runtime.a      运行期静态归档（链接时自动使用）
├─ examples/                   24 个单文件示例 + 3 个多文件工程
├─ benchmarks/                 跨语言基准源（nex/c/cpp/rust/go/python）
└─ tests/run_examples.sh       一键验证全部示例
```

### 1.2 编译与运行

```bash
./bin/nexus examples/01_hello_world.nex -o hello --release
./hello
# Hello, Nexus!
```

命令行（分发版）：

```text
nexus <file.nex> [-o <out>] [--release]
  -o <out>    输出可执行体路径（缺省由输入名推断）
  --release   发布模式（更强优化）
  -h, --help  帮助
```

编译器在进程内完成 LLVM codegen 与链接：产物是原生可执行体，运行期归档已静态链入，不依赖外部 C 编译器，也没有动态运行时依赖。若运行期归档不在 `bin/` 下，可用环境变量 `NEXUS_RT_PREBUILT` 指定路径。

### 1.3 第一个程序

```nexus
fn main() {
    println("Hello, Nexus!")
}
```

- `fn main()` 是入口；
- `println` 打印并换行，`print` 打印不换行；
- 函数体最后一行若是表达式，其值即返回值（见 [5.1](#51-定义与返回)）。

---

## 2. 词法与字面量

### 2.1 注释

```nexus
// 单行注释
```

### 2.2 整数字面量

```nexus
let a = 42                // 十进制；字面量缺省 i32，按上下文自动加宽
let big: i64 = 9000000000
let mask = 0xFFFF_FFFFu64 // 十六进制 + 下划线分隔 + 宽度/符号后缀
let i = 1usize            // usize 后缀（容器下标常用）
```

- 下划线 `_` 可用于数字分组；
- 后缀 `i8/i16/i32/i64/i128`、`u8/u16/u32/u64/u128`、`f32/f64`、`usize`；
- 整型字面量会按期望类型自动加宽（如 `i32 → i64`），必要时也可显式 `as`。

### 2.3 浮点、布尔、字符、字符串

```nexus
let pi = 3.14159          // f64
let flag = true           // bool
let letter: Char = 'N'    // 字符
let name = "Nexus"        // Str（不可变字符串视图）
```

### 2.4 字符串插值（f-string）

```nexus
let version = 25
let counter = 2
let pi = 3.14159
println("Nexus v{0}: counter={1}, pi={2:.2}", version, counter, pi)

println(f"pi={pi:.2f} hex={255:x} pad={255:>8}")
```

- `f"..."` 内可直接嵌入任意表达式；
- f-string 与格式串共用同一渲染核，说明符文法见 [第 17 节](#17-格式化输出)。

### 2.5 复合字面量

```nexus
let xs = [1, 2, 3]                 // List
let s: Set<i64> = { 1, 2, 2, 3 }   // Set（自动去重）
let db: Dict<i64, Str> = { 1: "alice", 2: "bob" }  // Dict
let pt = (3, 4)                    // 元组
```

### 2.6 范围

范围一律写作 `[a..b]`（上界排他），不存在裸 `a..b` 形态：

```nexus
for i in [0..3] {
    println(i) // 0 1 2
}
```

范围也可用于切片（产出视图，不拷贝）：

```nexus
let xs = [10, 20, 30, 40, 50]
let mid = xs[1..4] // 20 30 40
```

---

## 3. 变量、类型与空安全

### 3.1 绑定与可变性

```nexus
let small = 42            // 不可变
let mut counter: i64 = 0  // 显式 mut 才可写
counter = counter + 1
```

默认不可变；写操作需要 `mut`。类型大多可推导，必要时写注解。

### 3.2 内置类型

| 类别 | 类型 |
|------|------|
| 有符号整数 | `i8` `i16` `i32` `i64` `i128` |
| 无符号整数 | `u8` `u16` `u32` `u64` `u128` `usize` |
| 浮点 | `f32` `f64` |
| 其它标量 | `bool` `Char` |
| 字符串 | `Str`（不可变视图，按字节索引） |
| 容器 | `List<T>` `Set<T>` `Dict<K,V>` `Tensor<T>` |
| 可空 | `T?`（即 `Option<T>`） |
| 元组 | `(T1, T2, ...)` |
| 函数值 | `fn(参数类型) -> 返回类型` |

### 3.3 类型转换

```nexus
let n: i64 = 42
let f = 2.5
println((n + f as i64).to_str())
let idx = i as usize          // 容器下标要 usize
```

### 3.4 Option：可空与空安全

`T?` 表示可能有值。构造：`Some(v)`、`None`、或直接用 `T?` 注解接收值。

```nexus
let maybe: i64? = 7
println(maybe ?? 0)      // 7：?? 提供缺省值
let empty: i64? = null
println(empty ?? 0)      // 0

fn safe_div(a: f64, b: f64) -> f64? {
    if b == 0.0 { let r: f64? = None; return r } else { Some(a / b) }
}

match safe_div(10.0, 3.0) {
    Some(v) => println(f"result={v:.4}"),
    None => println("divide by zero"),
}

if find_user(1).is_some() { println("exists") }
if find_user(99).is_none() { println("missing") }
```

常用形态：

- `??`：`Some → 值`，`None → 缺省值`；
- `match`：完整分支，编译器检查穷尽；
- `is_some()` / `is_none()`：布尔查询；
- `?.`：安全解引用链（示例见 04）。

> `Dict.get(k)` 返回 `Option<V>`，因此最常见的兜底写法是 `dict.get(k) ?? 默认值`。

### 3.5 元组

```nexus
fn divmod(a: i64, b: i64) -> (i64, i64) {
    return (a / b, a % b)
}

let p = divmod(17, 5)
println(f"{p.0} ... {p.1}")   // 3 ... 2
```

元组按值聚合，用 `.0` / `.1` 取元素。

---

## 4. 表达式与控制流

### 4.1 if / else

```nexus
if n % 2 == 0 {
    println("even")
} else {
    println("odd")
}
```

### 4.2 while

```nexus
let mut i: i64 = 0
while i < 3 {
    i = i + 1
}
```

### 4.3 for-in

```nexus
for i in [1, 2, 3] { println(i) }   // 列表
for i in [0..3] { println(i) }      // 范围
for v in mid { println(v) }         // 切片
for k in ages.keys() { println(k) } // Dict 的键
```

### 4.4 match：表达式 + 穷尽检查

```nexus
fn classify(n: i64) -> Str {
    match n {
        0 => "zero",
        1 => "one",
        _ => "many",
    }
}
```

对 enum 的 match 必须覆盖全部变体，漏掉即编译错误：

```nexus
enum Shape {
    Circle(f64),
    Rect(f64, f64),
    Unit,
}

fn area(s: Shape) -> f64 {
    match s {
        Circle(r) => 3.14159 * r * r,
        Rect(w, h) => w * h,
        Unit => 0.0,
    }
}
```

### 4.5 表达式位置

`match` 与 `if` 都可以出现在表达式位置。块的最后一个表达式即块的值：

```nexus
fn safe_div(a: f64, b: f64) -> f64? {
    if b == 0.0 { let r: f64? = None; return r } else { Some(a / b) }
}
```

---

## 5. 函数与闭包

### 5.1 定义与返回

```nexus
fn fib(n: i64) -> i64 {
    if n <= 1 { return n }
    return fib(n - 1) + fib(n - 2)
}
```

省略 `return` 时，函数体最后一个表达式的值即返回值：

```nexus
fn classify(n: i64) -> Str {
    match n { 0 => "zero", 1 => "one", _ => "many" }
}
```

### 5.2 缺省参数

```nexus
fn connect(host: Str, port: i32 = 5432, timeout_ms: i32 = 3000) -> Str {
    return f"tcp://{host}:{port} (timeout={timeout_ms}ms)"
}

connect("db.local")            // 全部缺省
connect("db.local", 6379)      // 部分缺省
```

### 5.3 不限定参数（rest）

```nexus
fn total(...nums: i64) -> i64 {
    let mut s: i64 = 0
    for n in nums { s = s + n }
    return s
}

total(1, 2, 3) // 6
```

### 5.4 函数值

```nexus
fn apply_twice(f: fn(i64) -> i64, x: i64) -> i64 {
    return f(f(x))
}

fn inc(x: i64) -> i64 { return x + 1 }

apply_twice(inc, 10) // 12
```

### 5.5 闭包

```nexus
let add = fn(a: i64, b: i64) => a + b
println(add(2, 3)) // 5

let base = 100
let offset = fn(x: i64) => x + base
println(offset(7)) // 107：捕获创建时作用域的变量
```

闭包可作实参传给高阶函数：

```nexus
fn apply(f: fn(i64) -> i64, x: i64) -> i64 { return f(x) }

let inc = fn(x: i64) => x + 1
apply(inc, 10) // 11
```

---

## 6. 容器：List / Set / Dict

### 6.1 List

```nexus
let mut nums: List<i64> = [3, 1, 2]
nums.push(5)
nums.sort()            // 原地排序
println(nums.len())
println(nums.contains(2))

for n in nums { println(n) } // 1 2 3 5

let top = nums.pop()   // 弹出末尾，返回 Option
println(top ?? 0)
```

两种读取方式（来自 `24_algorithms.nex`）：

```nexus
let v = xs[i]        // 下标：直接返回值
let maybe = xs.get(i) // 安全读：返回 Option
```

预分配容量（来自 `benchmarks/nex/sieve.nex` 与 `struct_churn.nex`）：

```nexus
let mut flags: List<i64> = List.new(5000000) // 预分配 capacity，push 不触发扩容
let mut pts: List<Point> = List.new(2000000)
```

切片是视图，不拷贝：

```nexus
let mid = xs[1..4]
```

列表推导：

```nexus
let squares = [x * x for x in nums]
```

### 6.2 Set

```nexus
let s: Set<i64> = { 1, 2, 2, 3 }
println(s.len())        // 3
println(s.contains(2))  // true

let mut tags: Set<Str> = Set.new()
tags.insert("core")
tags.insert("jit")
```

### 6.3 Dict

```nexus
let mut scores: Dict<Str, i64> = Dict.new()
scores.set("alice", 90)
scores.set("bob", 85)
println(scores.get("alice") ?? 0)       // 90
println(scores.contains_key("bob"))     // true
println(scores.len())

for k in scores.keys() { println(k) }

// 字面量形态（键值对，逗号分隔）
let db: Dict<i64, Str> = { 1: "alice", 2: "bob", 4: "carol" }
```

### 6.4 迭代与聚合

```nexus
let doubled = xs.map(fn(v: i64) => v * 10)

let mut evens: List<i64> = []
for x in xs {
    if x % 2 == 0 { evens.push(x) }
}
```

> **注意**：空列表字面量必须能从上下文推断元素类型，最常见写法是加注解：
> `let mut evens: List<i64> = []`。

---

## 7. 自定义类型：struct / class / enum

### 7.1 struct：值语义聚合

```nexus
struct Point {
    x: i64,
    y: i64,
}

struct Size {
    w: i64,
    h: i64,
    fn area(self) -> i64 {
        return self.w * self.h
    }
}

let p = Point { x: 3, y: 4 }
let sz = Size { w: 2, h: 5 }
println(p.x + p.y) // 7
println(sz.area()) // 10
```

struct 按值拷贝，适合纯数据与消息体（并发基准中的 `Order`、`Agg` 都是 struct）。

### 7.2 class：引用语义与构造

```nexus
class Animal {
    pub name: Str

    fn init(name: Str) {
        self.name = name
    }

    fn speak(self) -> Str {
        return self.name + " makes a sound"
    }

    fn describe(self) -> Str {
        return f"{self.name} says: " + self.speak()
    }
}

let mut d = Dog("Rex") // 构造调用即 init
```

- 字段默认模块内可见，`pub` 后可跨模块读；
- 方法默认不可改字段，需改字段时声明 `mut self`：

```nexus
fn learn_trick(mut self) -> i64 {
    self.tricks = self.tricks + 1
    return self.tricks
}
```

- 字段可带初始值：`pub tricks: i64 = 0`；
- `private fn init()` 可把构造器私有化（IoC 单例示例）。

### 7.3 继承与多态

```nexus
class Dog extends Animal {
    fn speak(self) -> Str {
        return self.name + " barks!"
    }
}

let d = Dog("Rex")
println(d.describe())   // 父类方法内部调用到子类 speak（动态分派）
let a: Animal = d       // 子类实例可赋给父类引用
```

### 7.4 泛型类

```nexus
class Box<T> {
    pub value: T

    fn init(v: T) { self.value = v }
    fn get(self) -> T { return self.value }
}

let bi = Box::<i64>(42)      // 类型实参用 turbofish
let bs = Box::<Str>("payload")
```

### 7.5 enum：代数数据类型

```nexus
enum Shape {
    Circle(f64),
    Rect(f64, f64),
    Unit,
}

let shapes = [Shape.Circle(1.0), Shape.Rect(2.0, 3.0), Shape.Unit]
for s in shapes {
    println(area(s))
}

match Shape.Circle(2.0) {
    Circle(r) => println(f"radius = {r}"),
    _ => println("other"),
}
```

### 7.6 静态字段与单例

```nexus
class Container {
    static readonly global: Container
    static {
        Container.global = Container()
    }

    pub names: List<Str>

    private fn init() {
        self.names = List.new()
    }
}

let c = Container.global
```

`static { ... }` 在静态初始化阶段执行；`private fn init` 防止外部构造。

### 7.7 struct 还是 class？

| 需求 | 选择 |
|------|------|
| 纯数据、消息体、可拷贝的值 | `struct` |
| 有身份、需要共享引用/继承/多态 | `class` |
| 一组固定变体（可带载荷） | `enum` |

---

## 8. 运算符与重载

### 8.1 内置运算符

| 类别 | 运算符 |
|------|--------|
| 算术 | `+ - * / % **`（`**` 幂） |
| 比较 | `== != < > <= >=` |
| 逻辑 | `&& \|\| !` |
| 位运算 | `& \| ^ << >>` |
| 其它 | `??`（空值兜底）、`?.`（安全成员）、`as`（转换）、`#`（张量矩阵乘） |

### 8.2 成员运算符重载

```nexus
class Vec2 {
    pub x: f64
    pub y: f64

    fn init(x: f64, y: f64) { self.x = x; self.y = y }

    operator +(self, other: Vec2) -> Vec2 {
        return Vec2(self.x + other.x, self.y + other.y)
    }
    operator *(self, k: f64) -> Vec2 {
        return Vec2(self.x * k, self.y * k)
    }
    operator ==(self, other: Vec2) -> bool {
        return self.x == other.x && self.y == other.y
    }
    operator [](self, i: i64) -> f64 {
        if i == 0 { return self.x }
        return self.y
    }
    operator []=(mut self, i: i64, value: f64) {
        if i == 0 { self.x = value } else { self.y = value }
    }
}

let sum = a + b
let scaled = a * 3.0
if a == Vec2(1.0, 2.0) { println("equal") }

let mut v = Vec2(0.0, 0.0)
v[0] = 9.0
println(v[0])
```

### 8.3 全局运算符重载

用于跨类型、或以"构建表达式树"为目的的场景（`25_comptime_metaprogramming.nex`）：

```nexus
operator +(a: Node, b: Node) -> Add { return Add(a, b) }
operator *(a: Node, b: Node) -> Mul { return Mul(a, b) }

let expr = (x + y) * two   // 不立即求值，而是构造 AST 节点
println(expr.dump())       // ((x + y) * 2)
println(expr.eval())
```

---

## 9. 泛型与 concept

concept 是类型谓词，用来约束泛型参数：

```nexus
concept Integral<T> = is_integral(T)
concept Signed<T> = is_signed(T)

fn clamp_to<T: Integral<T>>(x: T, lo: T, hi: T) -> T {
    if x < lo { return lo }
    if x > hi { return hi }
    return x
}

// 多约束用 + 组合
fn negate<T: Integral<T> + Signed<T>>(x: T) -> T {
    return -x
}

println(clamp_to<i64>(15, 0, 10)) // 10
println(negate<i64>(42))          // -42
```

泛型类：

```nexus
class Accumulator<T: Integral<T>> {
    pub sum: T

    fn init() {
        self.sum = 0 as T
    }

    fn add(mut self, x: T) -> T {
        self.sum = self.sum + x
        return self.sum
    }
}

let mut acc = Accumulator::<i64>()
acc.add(10)
```

concept 也可以写成 requires 形式（用于接口方法存在性约束）：

```nexus
concept HasTlen<T> requires { exists fn tlen(self: T) -> i64 }
```

---

## 10. 接口与动态分派

```nexus
interface Shape {
    fn area(self) -> f64
    // 默认方法：实现者未重写时自动继承
    fn describe(self) -> Str {
        return "a shape"
    }
}

// 内联实现：类体内直接实现
class Circle impl Shape {
    pub r: f64
    fn init(r: f64) { self.r = r }
    fn area(self) -> f64 { return 3.14159 * self.r * self.r }
    fn describe(self) -> Str { return f"circle(r={self.r})" }
}

// 外联实现：类型定义与实现分离（struct 也能实现接口）
struct Square { side: f64 }
impl Shape for Square {
    fn area(self) -> f64 { return self.side * self.side }
    // describe 未重写 ⇒ 走默认实现
}

// 接口值参：vtable 动态分派
fn render(s: Shape) -> f64 { return s.area() }

let c = Circle(2.0)
println(render(c))

let s: Shape = c   // 显式 upcast：具体类型 → 接口引用
println(s.area())
```

泛型实现与"具体头"实现（偏特化风格）：

```nexus
interface TSum { fn tsum(self) -> i64 }
impl TSum for Nil { fn tsum(self) -> i64 { return 0 } }
impl<T: HasTsum<T>> TSum for Cons<i64, T> {
    fn tsum(self) -> i64 { return self.head + self.tail.tsum() }
}
```

---

## 11. 扩展方法

`extend` 可以为既有类型（包括内建类型）追加方法，无需修改类型定义：

```nexus
extend Str {
    fn shout(self) -> Str {
        return self + "!"
    }

    fn is_palindrome(self) -> bool {
        let bytes = self.len()
        let mut i: usize = 0
        while i < bytes / 2 {
            let a = self[i]
            let b = self[bytes - 1 - i]
            if a != b { return false }
            i = i + 1
        }
        return true
    }
}

println("hello".shout())          // hello!
println("racecar".is_palindrome()) // true
```

---

## 12. 编译期能力：const fn 与 comptime

### 12.1 const fn

`const fn` 在编译期求值，结果物化为常量，运行期零成本：

```nexus
const fn square(n: i64) -> i64 { return n * n }

const fn fib(n: i64) -> i64 {
    if n < 2 { return n }
    return fib(n - 1) + fib(n - 2)
}

println(square(12)) // 编译期折叠为 144
println(fib(25))    // 编译期算完，运行期只是读常量
```

`if`、`while`、递归在 `const fn` 中都可使用：

```nexus
const fn factorial(n: i64) -> i64 {
    if n <= 1 { return 1 }
    return n * factorial(n - 1)
}

const fn gauss(n: i64) -> i64 {
    let mut s: i64 = 0
    let mut i: i64 = 1
    while i <= n { s = s + i; i = i + 1 }
    return s
}

const fn is_prime(n: i64) -> bool {
    if n < 2 { return false }
    let mut i: i64 = 2
    while i * i <= n {
        if n % i == 0 { return false }
        i = i + 1
    }
    return true
}
```

### 12.2 comptime assert

编译期断言，条件不成立则编译失败：

```nexus
comptime assert factorial(10) == 3628800, "10! must be 3628800"
comptime assert is_prime(104729), "104729 is prime"
```

### 12.3 类型级编程（TypeList 模式）

Nexus 没有偏特化，但可以用 `struct 递归 + interface + impl 递归 + concept 约束` 表达等价能力：

```nexus
struct Nil {}
struct Cons<H, T> { head: H, tail: T }

interface TList { fn tlen(self) -> i64 }
concept HasTlen<T> requires { exists fn tlen(self: T) -> i64 }

impl TList for Nil {
    fn tlen(self) -> i64 { return 0 }
}
impl<H, T: HasTlen<T>> TList for Cons<H, T> {
    fn tlen(self) -> i64 { return 1 + self.tail.tlen() }
}

let list = Cons<i64, Cons<i64, Cons<i64, Nil>>> {
    head: 1,
    tail: Cons<i64, Cons<i64, Nil>> {
        head: 2,
        tail: Cons<i64, Nil> { head: 3, tail: Nil {} }
    }
}
println(list.tlen()) // 3
```

---

## 13. 反射、注解与切面

### 13.1 @reflect 与类型句柄

```nexus
@reflect
class Point {
    pub x: i64
    pub y: i64
    fn init(x: i64, y: i64) { self.x = x; self.y = y }
}

let t = Type.from_name("Point")   // Option<Type>
match t {
    Some(h) => {
        println(h.name())        // Point
        println(h.field_count()) // 2
    }
    None => println("not found"),
}

let p = Point(1, 2)
let h = typeof(p)                // 直接取表达式类型句柄
println(h.name())
```

### 13.2 注解

```nexus
annotation Tag(label: Str)

@Tag("geometry")
@reflect
class Circle {
    pub radius: f64
    fn init(r: f64) { self.radius = r }
}

// 注解可限定目标
annotation Component(name: Str) where class
annotation ContainerRun where fn

// 运行期查询
println(h.annotation_count())
println(h.annotation_name(0))
println(h.annotation_arg(0, "name"))
```

### 13.3 切面（aspect）

```nexus
annotation Audit(by: Str)

aspect for @Audit {
    fn before(ctx: CallCtx) -> bool {
        let src = ctx.ann_str("by")
        let argc = ctx.arg_count()
        println("[audit] before by={0} args={1}", src, argc)
        return true // false = 短路，原方法不执行
    }
    fn after_return(ctx: CallCtx, result: Value) {
        println("[audit] after, result={0}", result.as_i64())
    }
}

class Bank {
    @Audit("sys")
    fn deposit(n: i64) -> i64 {
        return n
    }
}
```

可用通知点：

| 通知点 | 触发时机 | ctx 类型 |
|--------|---------|----------|
| `before(ctx) -> bool` | 原方法执行前；返回 `false` 可拒绝调用 | `CallCtx` |
| `after_return(ctx, result)` | 原方法正常返回后 | `CallCtx` + `Value` |
| `type_init(ctx)` | 类型静态初始化阶段（如自动注册） | `TypeCtx`（`ctx.refl_type`） |
| `instance_create(ctx)` | 反射实例化新对象 | `InstanceCtx`（`ctx.instance_ptr`） |
| `instance_destroy(ctx)` | 对象销毁 | `InstanceCtx` |

反射实例化与调用：

```nexus
let raw: i64 = h.instantiate()            // 创建实例，返回 obj_ptr
let _ = h.invoke_i64(raw, "emit")         // 按名调用无参方法（void 返回 0）
```

---

## 14. 并发：spawn 与 Channel

### 14.1 spawn + await

```nexus
fn compute_sum(n: i64) -> i64 {
    let mut s: i64 = 0
    let mut i: i64 = 1
    while i <= n { s = s + i; i = i + 1 }
    return s
}

let h1 = spawn { compute_sum(1000000) }
let h2 = spawn { compute_sum(2000000) }
let r1 = h1.await()
let r2 = h2.await()
```

### 14.2 Channel：有界通道

```nexus
let ch = Channel<Str>::bounded(8)   // 容量 8，满时 send 背压阻塞

let producer = spawn {
    ch.send("alpha")
    ch.send("beta")
    ch.close()
}

let msg = ch.recv()
```

- `send(v)`：发送；有界通道满时阻塞（背压）；
- `recv()`：接收；
- `close()`：关闭通道。

### 14.3 流水线与扇出

多 worker 竞争消费同一输入通道，天然负载均衡；各 worker 维护局部聚合，主线程合并（`benchmarks/concurrent/orders_pipeline.nex`）：

```nexus
fn fanout_jobs(n_jobs: i64, total: i64) -> i64 {
    let result_ch = Channel<i64>::bounded(n_jobs)
    let work_ch = Channel<i64>::bounded(64)

    let wp = spawn {
        let mut i: i64 = 0
        while i < total { work_ch.send(i); i = i + 1 }
    }

    let mut i: i64 = 0
    while i < n_jobs {
        let wch = work_ch
        let rch = result_ch
        spawn {
            let mut local_sum: i64 = 0
            let mut count: i64 = 0
            while count < total / n_jobs {
                let v = wch.recv()
                local_sum = local_sum + v * v
                count = count + 1
            }
            rch.send(local_sum)
        }
        i = i + 1
    }

    wp.await()
    // ... 主线程 recv 汇总
}
```

### 14.4 高并发

```nexus
let n: i64 = 10000
let done = Channel<i64>::bounded(n)
let mut i: i64 = 0
while i < n {
    spawn { done.send(1) }
    i = i + 1
}
// 主线程收 n 条
```

Nexus 的并发是消息传递模型：任务间不共享可变内存，数据经类型化通道传递，从源头避免数据竞争。10⁴ 量级协程的内存开销远低于同数量 OS 线程。

---

## 15. 张量计算

`Tensor<T>` 是语言内建容器，同一份代码面向 CPU 与未来加速器。

### 15.1 构造

```nexus
let zeros  = Tensor<f64>.zeros([2, 3])                       // 全 0
let ones   = Tensor<f64>.ones([2, 2])                        // 全 1
let filled = Tensor<i64>.filled([2, 2], 7)                   // 全 7
let nested = Tensor<f64>.from_nested([[1.0, 2.0], [3.0, 4.0]])
let grid   = Tensor<i64>.range(0, 6, 1).reshape([2, 3])      // 0..5 → 2×3
let samples = Tensor<f64>.linspace(0.0, 1.0, 5)              // 0..1 均匀 5 点
```

### 15.2 读写与归约

```nexus
println(zeros.shape().len()) // 秩 = 2
println(filled.get([1, 1]))  // 7
println(nested.sum())        // 10
println(nested.mean())       // 2.5
println(nested.max())        // 4

let a = Tensor<i64>.zeros([2, 2])
a.set([0, 1], 5)             // 按索引写
```

### 15.3 逐元素运算与矩阵乘

```nexus
let two = Tensor<f64>.filled([2, 2], 2.0)
let doubled = nested.mul(two) // 逐元素乘
let added   = nested.add(ones)

let m = m1.matmul(m2) // 矩阵乘
let m2 = a # b        // 同上，`#` 运算符
```

> 注意：`*` 用于张量会被类型检查拒绝（`no common numeric type`）。逐元素乘/加请用 `.mul()` / `.add()`；矩阵乘用 `.matmul()` 或 `#`。

### 15.4 形状变换与持久化

```nexus
println(m1.transpose(0, 1).get([1, 0]))
let flat = grid.reshape([6])
let parts = m1.split(0, [1, 1])   // 沿轴 0 切成 [1,1] 两块
println(parts.len())

m1.save("/tmp/nexus_tensor_demo")
let loaded = Tensor<f64>.load("/tmp/nexus_tensor_demo")
println(m1.dtype()) // f64
```

---

## 16. 模块与工程组织

### 16.1 目录即包

```text
modules_demo/
├── main.nex
└── modules/
    └── geometry/
        ├── mod.nex      ← 包入口
        └── point.nex    ← 同包第二文件（同符号空间）
```

```nexus
// main.nex
import modules.geometry

fn main() {
    let a = Point(1, 2)
    println(dot(a, b))
    println(a.norm())
}
```

- 包按目录解析，与文件名无关；
- 同目录多文件的 `pub` 声明并入同一符号空间（`mod.nex` 可直接使用 `point.nex` 的 `pub` 类型）；
- 也可按成员导入：`import modules.geometry.{dot, Point}`，或整包导入 `import modules.geometry.*`。

### 16.2 可见性

```nexus
// point.nex
pub class Point {
    pub x: i64
    pub y: i64
    pub fn norm(self) -> f64 { ... }
}

// mod.nex
pub fn dot(a: Point, b: Point) -> i64 { ... }   // 可被外部 import
fn scale_squared(a: Point) -> i64 { ... }        // 模块私有：外部不可见
```

- 只有 `pub` 声明可被 import；
- 无 `pub` 的声明是模块私有，构成封装边界。

### 16.3 库工程

`20_lib_demo` 展示"库 ＋ 消费方"两步：

```bash
# ① 库侧自检（库文件单独可编译）
./bin/nexus lib/mathx/mod.nex

# ② 消费侧编译运行
./bin/nexus main.nex -o demo --release && ./demo
```

```nexus
// main.nex
import lib.mathx

fn main() {
    let xs: List<f64> = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0]
    println(mean(xs))     // 5.0
    println(variance(xs)) // 4.0
}
```

> 当前边界：被 import 的包内，导出函数之间尚不支持相互调用。库内每个导出函数请写成自足形态（需要抽公共助手时，等模块系统后续收口）。

---

## 17. 格式化输出

两个入口共用同一渲染核：

```nexus
// ① 格式串：占位 {N} 必须带显式索引（0 起）
println("pi = {0:.2f}", pi)

// ② f-string：插值任意表达式
println(f"pi={pi:.2f} hex={n:x} pad={n:>8}")
```

说明符文法：

```text
[[fill]align]? sign? "#"? zero? width? ("." precision)? type?
  align ∈ < > ^      sign ∈ + - 空格
  type  ∈ b o d x X e E f F g s ?
```

示例（`16_formatting.nex`）：

```nexus
let pi = 3.14159265358979
let n = 255

println("pi = {0:.2f}", pi)             // 定点两位
println("sci = {0:.3e}", pi)            // 科学计数
println("compact = {0:g}", 2500000.0)   // 最紧凑

println("dec={0:d} hex={0:x} HEX={0:X} oct={0:o} bin={0:b}", n)
println("hex#={0:#x}", n)               // 0xff

println("right [{0:>8}]", 42)
println("left  [{0:<8}]", 42)
println("center[{0:^8}]", 42)
println("zero  [{0:08}]", 42)
println("fill  [{0:*<8}]", 42)

println("sign [{0:+d}] [{1: d}]", 5, 5)
println("{1} before {0}", "second", "first")   // 乱序与重复引用
println("debug = {0:?}", "text")               // 调试转储
println("braces {{{0}}}", 1)                   // {{ → {，}} → }
```

`print` / `println` 的规则：裸写不带换行 / 补换行；带参数时用 `{N}` / f-string。

格式串的占位在**编译期**校验：`{` 未闭合、占位缺数字索引（如 `"{}"`）、索引超出实参个数
（如 `println("{2}", a, b)` 之外的越界）都会被直接拒收并给出具名诊断；`{{` / `}}` 是字面量
花括号。占位索引只是"引用第几个实参"，因此乱序（`{1} {0}`）与重复（`{0} {0}`）按引用语义
取实参，实参表达式仍按源码序求值一次。

---

## 18. 性能实践

以下建议来自 `benchmarks/nex/` 与 `benchmarks/concurrent/` 的实测写法：

### 18.1 预分配容器容量

已知规模时优先 `List.new(n)`，避免 push 过程中的反复扩容：

```nexus
let mut flags: List<i64> = List.new(5000000)
let mut pts: List<Point> = List.new(2000000)
```

### 18.2 热循环里避免分配

- 用 `while` ＋ 局部变量做数值循环（`loop_sum`、`matmul`、`mandelbrot`）；
- 用 `List`/`struct` 承载批量数据，而不是在循环内创建短命对象；
- 用 `as usize` / `0usize` 明确下标类型，避免多余的整型转换。

### 18.3 用 struct 传递消息

并发流水线以 `struct Order` / `struct Agg` 作为通道消息：单次分配、值语义、无共享可变状态：

```nexus
struct Order {
    id: i64,
    amount: f64,
    cat: i64,
}
```

### 18.4 局部聚合，最后合并

多 worker 竞争消费同一输入通道，各自维护局部聚合，主线程只做一次合并——避免任何共享写入：

```nexus
let result_ch = Channel<i64>::bounded(n_jobs)
// 每个 worker: local_sum 累加后 rch.send(local_sum)
// 主线程: 逐个 recv 相加
```

### 18.5 把计算搬进编译期

`const fn` 能在编译期算完的，不要留给运行期（阶乘、斐波那契、素数判定、常量表）。

### 18.6 实测参考

同机实测（Apple M4 / macOS 27.3，详见 `PERFORMANCE_REPORT.md`）：

- 单文件编译约 0.15s；
- fib(40) 约 190ms（C++/Rust 160~170ms，差距约 12~19%）；
- 2M 订单并发流水线约 60ms，优于同场景 C++/Rust/Go（200/140/80ms）；
- 产物约 455KB，与 Rust（459KB）同档，无动态运行时依赖。

---

## 19. 常见错误与排错

| 现象 | 原因 | 处理 |
|------|------|------|
| `empty list literal needs a type annotation` | `[]` 无法推断元素类型 | 写注解：`let mut xs: List<i64> = []` |
| `unexpected token DotDot in expression` | 用了裸 `a..b` | 写成 `[a..b]` |
| `indexing requires array or list` | 下标用在非容器/未实现 `operator []` 的类型 | 用容器，或为该类实现 `operator []` |
| match 报非穷尽 | 漏了 enum 变体 | 补齐变体或加 `_` 臂 |
| `cannot assign i32 to i64` | 整型宽度不一致 | 注解目标类型或 `as` 转换 |
| 方法里改字段报错 | 方法未声明 `mut self` | `fn f(mut self)` |
| 下标类型不匹配 | 用了 `i64` 作下标 | `i as usize` 或写 `1usize` |
| 通道 `send` 卡住 | 有界通道满且无消费者 | 检查消费端/容量；必要时 `close()` |

编译错误会带源码位置（span），如 `at @{1264..1265}`，直接定位到表达式。

---

## 20. 附录

### 20.1 内建方法速查（示例中验证过的子集）

**Str**

```nexus
s.len()                  // 字节长度
s.contains("Nex")
s.starts_with("Hello")
s.find("Nexus")          // Option<usize>
s.slice(7, 12)
s.slice_to(5)
s.trim()
s.split(",")             // 可 for 迭代
s[i]                     // 取第 i 个字符（Char；越界即终止）
s.char_at(i)             // 同上但返回 Option<Char>（越界为 None）
```

**List**

```nexus
xs.push(v)
xs.pop()                 // Option<T>
xs.len()
xs.sort()                // 原地
xs.contains(v)
xs[i]                    // 直接返回值
xs.get(i)                // Option<T>
xs.map(fn(v) => ...)
List.new()
List.new(capacity)
xs[a..b]                 // 切片视图
```

**Set**

```nexus
Set.new()
s.insert(v)
s.contains(v)
s.len()
```

**Dict**

```nexus
Dict.new()
d.set(k, v)
d.get(k)                 // Option<V>
d.contains_key(k)
d.keys()
d.len()
```

**数值**

```nexus
n.to_str()
f.to_str()
```

**Tensor**：见 [第 15 节](#15-张量计算)。

**Type（反射句柄）**

```nexus
h.name()
h.field_count()
h.annotation_count()
h.annotation_name(i)
h.annotation_arg(i, "name")
h.instantiate()          // -> i64（obj_ptr）
h.invoke_i64(ptr, "method")
```

### 20.2 CLI 速查

```text
nexus <file.nex> [-o <out>] [--release]
  -h, --help
```

环境变量：

| 变量 | 说明 |
|------|------|
| `NEXUS_RT_PREBUILT` | 运行期静态归档路径（缺省取 `bin/nexus` 同目录的 `libnexus_runtime.a`） |
| `NEXUS_SDK` | macOS SDK 路径（缺省自动 `xcrun --show-sdk-path`） |

### 20.3 示例索引

| 示例 | 章节 |
|------|------|
| 01_hello_world | 1 |
| 02_types_and_vars | 2、3 |
| 03_functions | 5 |
| 04_control_flow | 2、4、3.4 |
| 05_collections | 6 |
| 06_closures | 5.5 |
| 07_classes | 7.2、7.3、7.4 |
| 08_operator_overload | 8.2 |
| 09_generics_concept | 9 |
| 10_extension_methods | 11 |
| 11_struct_enum | 7.1、7.5 |
| 12_comptime | 12.1、12.2 |
| 13_reflection | 13.1、13.2 |
| 14_concurrency | 14.1、14.2 |
| 15_tensors | 15 |
| 16_formatting | 17 |
| 17_interfaces | 10 |
| 18_aspect | 13.3 |
| 19_builtin_methods | 6、20.1 |
| 20_lib_demo | 16.3 |
| 22_option_patterns | 3.4 |
| 23_async_advanced | 14.2、14.3、14.4 |
| 24_algorithms | 5.1、6.1、3.4 |
| 25_comptime_metaprogramming | 8.3、12、9、10 |
| 26_ioc | 7.6、13.2、13.3 |
| modules_demo | 16.1 |
| benchmarks | 18 |

### 20.4 延伸阅读

- 性能数据与复现方式：[`PERFORMANCE_REPORT.md`](./PERFORMANCE_REPORT.md)
- 功能验证：`bash tests/run_examples.sh`
- 全量基准：`python3 benchmarks/run_benchmarks.py --all`
