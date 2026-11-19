#!/bin/sh
# ============================================================
# 一键环境安装辅助（macOS: Homebrew / Linux: apt）
# 用法：sh benchmarks/setup_env.sh [cpp|rust|go|python|all]
#
# 装完后：source benchmarks/setup_env.sh  # 设好 NEXUS_RT_PREBUILT / NEXUS_SDK
#       或直接 cd nexus-release && 让 setup_env.sh 自己导出
# ============================================================

# ── 自动导出编译分发版所需环境变量（在脚本尾部 echo 提醒用户手动 source）──
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NEXUS_RT="${ROOT}/bin/nexus_runtime"
[ -f "${ROOT}/bin/libnexus_runtime.a" ] && NEXUS_RT="${ROOT}/bin/libnexus_runtime.a"

cat <<SETUP

# ============================================================
# Nexus 分发版编译需要两个环境变量（自动检测）：
# ============================================================
export NEXUS_RT_PREBUILT="${NEXUS_RT}"
export NEXUS_SDK="\$(xcrun --show-sdk-path 2>/dev/null || echo /)"  # Linux 下无 xcrun 可忽略

# 临时设好（当前 shell 生效），用户要永久生效请加到 ~/.zshrc / ~/.bashrc
# 或直接 source $0 让它生效。
SETUP

PKG=${1:-all}
have_brew() { command -v brew >/dev/null 2>&1; }
have_apt() { command -v apt-get >/dev/null 2>&1; }

install_one() {
    case "$1" in
        cpp)
            if have_brew; then echo "→ brew install llvm"; brew install llvm
            elif have_apt; then echo "→ apt install g++"; sudo apt-get install -y g++
            else echo "✗ 无包管理器（brew/apt）"; fi ;;
        rust)
            echo "→ rustup（官方安装器）"
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y ;;
        go)
            if have_brew; then echo "→ brew install go"; brew install go
            elif have_apt; then echo "→ apt install golang-go"; sudo apt-get install -y golang-go
            else echo "✗ 无包管理器；请到 https://go.dev/dl/ 下载"; fi ;;
        python)
            if have_brew; then echo "→ brew install python3"; brew install python3
            elif have_apt; then echo "→ apt install python3"; sudo apt-get install -y python3
            else echo "✗ 无包管理器"; fi ;;
        all)
            for p in cpp rust go python; do install_one "$p"; done ;;
        *) echo "用法：setup_env.sh [cpp|rust|go|python|all]" ;;
    esac
}

install_one "$PKG"
echo "── 完成后请重新运行 sh benchmarks/check_env.sh 核对 ──"
