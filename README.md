# Nexus

Nexus 是一门**既要易写又要高性能**的语言——内建纤程并发、自动引用计数、反射、切面、张量、逻辑编程，编译产物是原生二进制（LLVM 后端）。编译器自举，分发包里不需要外部 C 编译器。

---

## 快速上手

```bash
# 编译并运行
./bin/nexus examples/01_hello_world.nex -o hello --release
./hello
#   Hello, Nexus!
```

编译器会自动链接 runtime 静态归档（`bin/libnexus_runtime.a`），不需要任何动态链接依赖。首次编译约 0.13s，增量编译更短。

### 环境变量（脚本自动检测，手动可设）

| 变量 | 说明 |
|------|------|
| `NEXUS_RT_PREBUILT` | runtime 静态归档或 dylib 路径（默认检测 `bin/libnexus_runtime.a`） |
| `NEXUS_SDK` | macOS SDK 路径（自动 `xcrun --show-sdk-path`，Linux 可忽略） |

### 完整 CLI

```
nexus <file.nex> [选项]
  --backend llvm           代码生成后端（当前仅 llvm）
  -O 0|1|2|3               优化档位（默认 2）
  --release                等同于 -O 3 + 发布配置
  --emit=ll|mir|nhir|ast   只发射某层 IR 文本（调试用）
  -o <path>                输出可执行体路径
  --limit <key>=<val>      限制/调优项（如 --limit stack=262144）
```

---

## 功能验证

分发包里已经带了 24 个单文件示例 + 3 个多文件项目。一键验证全部：

```bash
bash tests/run_examples.sh
```

输出：
```
OK 01_hello_world (2 lines)
OK 02_types_and_vars (3 lines)
...
OK 26_ioc (完整 IoC 生命周期)
OK modules_demo (模块化工程)
OK 20_lib_demo (静态库链接)
OK 21_ffi_abi (C FFI + dylib)
== examples: pass=27 fail=0 ==
```

**需要外部 C 编译器**：`run_examples.sh` 默认用 cpp 后端（调用 clang++ 链）。如果你的机器没有 clang++，可以让它用 Nexus 自带的 LLVM 后端：

```bash
NEXUS_BACKEND=llvm bash tests/run_examples.sh
```

---

## 性能 Benchmark

### 跑全量（6 个 workload × 5 种语言）

```bash
python3 benchmarks/run_benchmarks.py
```

需要的对照语言工具链：
| 语言 | 安装 |
|------|------|
| C / C++ | macOS: `xcode-select --install`；Linux: `sudo apt install build-essential` |
| Rust | `curl https://sh.rustup.rs -sSf | sh` |
| Go | macOS: `brew install go`；Linux: https://go.dev/dl |
| Python | macOS: `brew install python3`；Linux: `sudo apt install python3` |

一键装齐全部对照语言：
```bash
sh benchmarks/setup_env.sh all
```

### 只看 Nexus 自身

```bash
python3 benchmarks/run_benchmarks.py --nexus-only
```

### 并发 benchmark

```bash
python3 benchmarks/run_benchmarks.py --concurrent
```

### 最新实测报告

[PERFORMANCE_REPORT.md](./PERFORMANCE_REPORT.md) — 包含所有 workload 的运行时间、二进制大小、编译速度、编译内存的横向对比，以及总体 PK 评价。

---

## 目录结构

```
nexus-release/
├── bin/
│   ├── nexus                      编译器（自举，LLVM 后端）
│   ├── libnexus_runtime.a         runtime 静态归档
│   ├── libLLVM.23.1.dylib         内嵌的 LLVM runtime
│   └── include/                   LLVM-C 头文件副本
├── examples/                      24 个语言特性示例 + 3 个多文件项目
├── benchmarks/                    跨语言 benchmark 源
│   ├── run_benchmarks.py          ✅ 主入口
│   ├── setup_env.sh / check_env.sh   工具链辅助
│   ├── c/ cpp/ rust/ nex/ go/ python/   6 种语言 × 6 workload
│   └── concurrent/                orders_pipeline（5 种语言）
├── tests/run_examples.sh          ✅ examples 全量验证入口
├── PERFORMANCE_REPORT.md          最新基准实测报告
└── README.md                      本文档
```

---

## 性能速览

| 维度 | Nexus 表现 |
|------|-----------|
| **编译速度** | 平均 0.13s（比 C 快 3×，比 C++/Rust 快 5×） |
| **编译内存** | 平均 80MB（比 C 少 51%，比 Rust 少 45%） |
| **二进制大小** | 51-53KB（比 Rust 小 8.8×，比 Go 小 46×） |
| **并发调度** | orders_pipeline 最快（比 Go/C++/Rust 快 8-17%） |
| **单线程纯计算** | 与 C/C++/Rust 同量级（±0-17%） |
| **单线程容器密集** | RC 开销明显（sieve 慢 39%，matmul 慢 94%） |

详见 [PERFORMANCE_REPORT.md](./PERFORMANCE_REPORT.md)。

---

## 语言参考

24 个示例覆盖了 Nexus 的全部核心特性。按序阅读 `examples/` 目录就是一篇完整的语言开发指南，从基础语法（01）到 IoC 注解驱动（26）。

| 示例 | 主题 | 示例 | 主题 |
|------|------|------|------|
| 01_hello_world | 变量、类型、函数 | 13_reflection | 类型反射 |
| 02_types_and_vars | 控制流、枚举 | 14_concurrency | spawn + Channel |
| 03_functions | List / Dict / Set | 15_tensors | Tensor 运算 |
| 04_control_flow | 闭包 | 16_formatting | fmt / println |
| 05_collections | 类 + super | 17_interfaces | 接口 |
| 06_closures | 操作符重载 | 18_aspect | 切面 / AOP |
| 07_classes | 泛型 + 概念 | 19_builtin_methods | 内建方法 |
| 08_operator_overload | 扩展方法 | 22_option_patterns | Option / if-let |
| 09_generics_concept | struct / enum | 23_async_advanced | 高级 async |
| 10_extension_methods | 编译期常量 | 24_algorithms | 模式匹配 / 尾递归 |
| 11_struct_enum | — | 25_comptime_metaprogramming | 编译期元编程 |
| 12_comptime | — | 26_ioc | 注解驱动 IoC |
