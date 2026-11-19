#!/bin/sh
# ============================================================
# 环境检查：检测基准所需工具链，给出友好提示。
# 用法：sh benchmarks/check_env.sh
# 退出码：0=全部就绪（或仅有可选缺失）；1=必需项缺失（Nexus 自身）。
# ============================================================
ok=1
say_missing() {
    echo "  ✗ 未找到 $1"
    echo "    → 安装提示：$2"
    echo "    → 或运行本仓库附带的一键安装：sh benchmarks/setup_env.sh $3"
}

echo "── Nexus 自身 ──────────────────────────────"
if [ -x "./bin/nexus" ]; then
    echo "  ✓ bin/nexus（自举 LLVM 后端编译器）"
else
    say_missing "bin/nexus" "从本仓库 release 页下载对应平台的压缩包，解压到仓库根" "nexus"
    ok=0
fi

echo "── 对照语言工具链（可选——缺哪项就跳过哪项的对照列）──"
if command -v clang++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1; then
    echo "  ✓ C++ 编译器（clang++/g++）"
else
    say_missing "clang++" "macOS：xcode-select --install；Linux：sudo apt install g++" "cpp"
fi
if command -v rustc >/dev/null 2>&1; then
    echo "  ✓ rustc ($(rustc -V 2>/dev/null))"
else
    say_missing "rustc" "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh" "rust"
fi
if command -v go >/dev/null 2>&1; then
    echo "  ✓ go ($(go version 2>/dev/null))"
else
    say_missing "go" "macOS：brew install go；Linux：见 https://go.dev/dl/" "go"
fi
if command -v python3 >/dev/null 2>&1; then
    echo "  ✓ python3 ($(python3 -V 2>/dev/null))"
else
    say_missing "python3" "macOS：brew install python3；Linux：sudo apt install python3" "python"
fi

echo "── 速查 ───────────────────────────────────"
echo "  只想看 Nexus 自己的性能：直接跑  sh benchmarks/run_benchmarks.sh --nexus-only"
echo "  全量对照：                    sh benchmarks/run_benchmarks.sh"
exit $([ $ok -eq 1 ] && echo 0 || echo 1)
