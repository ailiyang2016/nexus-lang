#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# boot_build.sh — 自举编译器（boot₂）固化构建脚本
#
# 流程（4 个 phase，任一失败立即 abort，修代码后重跑即可）：
#   P1  Rust 生产编译器  →  cargo build --release nexus_driver
#   P2  运行期预编译归档  →  runtime/*.c + *.S → libnexus_runtime.a
#   P3  boot₁：Rust nex  →  boot_nex_main_release.nex （LLVM-embed）
#   P4  boot₂：boot₁    →  boot_nex_main_release.nex （自举验证）
#   P5  部署验证：boot₂  →  hello_world 通过 → 拷贝到 bin/
#
# 用法：
#   nexus-release/scripts/boot_build.sh                  # 默认（../nexus-compiler）
#   NEXUS_COMPILER_ROOT=/path/to/compiler boot_build.sh # 指定路径
#   boot_build.sh --clean                               # 清 target/ 重跑
#
# 退出码：0 = 成功，非 0 = 某 phase 失败（stderr 有明确说明）
# ═══════════════════════════════════════════════════════════════════════
set -euo pipefail

# ── 路径定位 ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPILER_ROOT="${NEXUS_COMPILER_ROOT:-$(cd "$RELEASE_ROOT/../nexus-compiler" && pwd 2>/dev/null || echo "")}"

if [ -z "$COMPILER_ROOT" ] || [ ! -d "$COMPILER_ROOT" ]; then
    echo "FATAL: nexus-compiler 路径无法定位" >&2
    echo "  默认: $RELEASE_ROOT/../nexus-compiler" >&2
    echo "  或  : export NEXUS_COMPILER_ROOT=/path/to/nexus-compiler" >&2
    exit 1
fi

TARGET="$RELEASE_ROOT/target"
BIN="$RELEASE_ROOT/bin"
TMP="$RELEASE_ROOT/tmp"

if [ "${1:-}" = "--clean" ]; then
    echo "[clean] 清空 $TARGET $TMP"
    rm -rf "$TARGET" "$TMP"
fi
mkdir -p "$TARGET" "$TMP"

echo "═══ boot_build ═══"
echo "  compiler: $COMPILER_ROOT"
echo "  release : $RELEASE_ROOT"
echo "  target  : $TARGET"
echo "═══════════════════"

# ── 辅助函数 ────────────────────────────────────────────────────────────
phase() { echo ""; echo "── P$1: $2 ──"; }
die()   { echo "FATAL: $1" >&2; exit "${2:-1}"; }

# ── LLVM / SDK 定位 ─────────────────────────────────────────────────────
SDK="$(xcrun --show-sdk-path 2>/dev/null || echo "")"
[ -z "$SDK" ] && die "无法获取 SDK 路径（xcrun --show-sdk-path 失败）"

LLVM_INC=""
LLVM_LIB=""
if [ -d /opt/homebrew/opt/llvm/include ]; then
    LLVM_INC=/opt/homebrew/opt/llvm/include
    LLVM_LIB=/opt/homebrew/opt/llvm/lib
elif [ -d "$HOME/.brew/opt/llvm/include" ]; then
    LLVM_INC="$HOME/.brew/opt/llvm/include"
    LLVM_LIB="$HOME/.brew/opt/llvm/lib"
else
    die "未找到 LLVM（/opt/homebrew 或 ~/.brew）"
fi
echo "  SDK  = $SDK"
echo "  LLVM = $LLVM_INC"

# ═══════════════════════════════════════════════════════════════════════
# P1  Rust 生产编译器
# ═══════════════════════════════════════════════════════════════════════
phase 1 "cargo build --release -p nexus_driver --bin nex --features llvm-embed"

NEX="$COMPILER_ROOT/target/release/nex"
if [ -f "$NEX" ] && [ -z "${1:-}" ]; then
    echo "  已存在（跳过）: $NEX"
else
    cd "$COMPILER_ROOT"
    cargo build --release -p nexus_driver --bin nex --features llvm-embed \
        || die "cargo build 失败" 1
fi
[ -x "$NEX" ] || die "P1 产物 $NEX 不存在或不可执行" 1
echo "  ✓ $NEX ($(ls -lh "$NEX" | awk '{print $5}'))"

# ═══════════════════════════════════════════════════════════════════════
# P2  运行期预编译归档（libnexus_runtime.a）
#
# 规则：编译所有 runtime/*.c + *.S，跳过：
#   - nexus_runtime.c  （与 containers.c 有 452 个重复 T 符号）
#   - bench_*           （基准专用，非运行期）
#   - ctx_x86_64.S      （x86_64，非当前平台）
# 所有 FFI 符号（nex_args_*/nex_fs_*/nex_llvm_*/nex_process_exit 等）
# 必须留在归档里 → 最终链接时 -force_load + 不使用 -dead_strip。
# ═══════════════════════════════════════════════════════════════════════
phase 2 "运行期归档 → libnexus_runtime.a"

RT_OBJ="$TARGET/rt_objs"
RT_A="$TARGET/libnexus_runtime.a"
rm -rf "$RT_OBJ" && mkdir -p "$RT_OBJ"

SRC_FILES=$(cd "$COMPILER_ROOT/runtime" && ls *.c *.S 2>/dev/null \
    | grep -v "^bench_" \
    | grep -v "ctx_x86_64" \
    | grep -v "^nexus_runtime\.c$" \
    | grep -v "^nexus_llvm\.c$")
# nexus_llvm.c 由 push_llvm_bridge 现场编 bridge.o 提供（含 emit_obj/link_kind）
# —— 和 Rust driver 同口径；libnexus_runtime.a 只放纯 runtime 代码

echo "  编译 $(echo "$SRC_FILES" | wc -l) 个源文件..."
FAIL=0
cd "$COMPILER_ROOT/runtime"
for src in $SRC_FILES; do
    base="${src%.*}"
    if ! cc -c -O2 -fPIC -arch arm64 -target arm64-apple-macosx13.0.0 \
            -isysroot "$SDK" \
            -I. -Iinclude \
            -I"$LLVM_INC" \
            "$src" -o "$RT_OBJ/$base.o" 2>"$TARGET/rt_err_$base.log"; then
        echo "    FAIL: $src (见 $TARGET/rt_err_$base.log)"
        FAIL=1
    fi
done
[ $FAIL -eq 0 ] || die "runtime .c 编译失败" 1

ar rcs "$RT_A" "$RT_OBJ"/*.o \
    || die "ar rcs 失败" 1

echo "  ✓ $RT_A ($(ls -lh "$RT_A" | awk '{print $5}'))"

# 关键 FFI 符号验证
# （macOS anaconda 的 nm 在 pipe 场景下行为不稳定 → 先落盘再 grep）
# ★ nexus_llvm_* 符号由 bridge.o 提供（push_llvm_bridge 现场编 nexus_llvm.c），
#   不在 libnexus_runtime.a 里——这里只校验纯 runtime 符号
FFI_SYMS=(nex_args_init nex_args_count nex_args_get nex_fs_read_file nex_process_exit nex_ewrite_str)
NM_OUT="$TARGET/nm_syms.txt"
nm "$RT_A" > "$NM_OUT" 2>&1 || true
MISS=0
for sym in "${FFI_SYMS[@]}"; do
    if ! grep -q "T _${sym}" "$NM_OUT"; then
        echo "    MISSING: $sym"; MISS=1
    fi
done
[ $MISS -eq 0 ] || die "关键 FFI 符号缺失（见 $NM_OUT）" 1
echo "  ✓ runtime FFI 符号全齐"

# LLVM bridge 符号校验（bridge.o 由 push_llvm_bridge 现场编）
LLVM_SYMS=(nex_llvm_emit_obj nex_llvm_link nex_llvm_link_kind nex_llvm_last_err)
LLVM_BRIDGE="$COMPILER_ROOT/runtime/prebuilt/arm64-apple-macosx13.0.0/nexus_llvm_bridge.o"
if [ -f "$LLVM_BRIDGE" ]; then
    NM_B="$TARGET/nm_bridge.txt"
    nm "$LLVM_BRIDGE" > "$NM_B" 2>&1 || true
    LMISS=0
    for sym in "${LLVM_SYMS[@]}"; do
        if ! grep -q "T _${sym}" "$NM_B"; then
            echo "    BRIDGE MISSING: $sym"; LMISS=1
        fi
    done
    [ $LMISS -eq 0 ] || die "bridge.o 符号缺失（见 $NM_B）" 1
    echo "  ✓ LLVM bridge 符号全齐"
fi

# ═══════════════════════════════════════════════════════════════════════
# P3  boot₁：Rust nex → boot_nex_main_release.nex（分发版入口）
#
# 分发版入口（boot_nex_main_release.nex）= 精简 CLI：
#   nexus <file.nex> [-o <out>] [--release]
#   拒绝 --backend / --crate-type / --emit / -O / --target / --set
#   恒走 llvm-embed（进程内 libLLVM 出 .o → 系统 ld）
# ═══════════════════════════════════════════════════════════════════════
phase 3 "boot₁：Rust nex → boot_nex_main_release.nex"

BOOT_SRC="$COMPILER_ROOT/selfhost/boot_nex_main_release.nex"
[ -f "$BOOT_SRC" ] || die "找不到 boot_nex_main_release.nex" 1

export NEXUS_RT_PREBUILT="$RT_A"
export NEXUS_SDK="$SDK"

BOOT1="$TARGET/boot1"
rm -f "$BOOT1" "$BOOT1.o"

echo "  $NEX → boot₁ ..."
cd "$COMPILER_ROOT"
"$NEX" selfhost/boot_nex_main_release.nex \
    --backend llvm -o "$BOOT1" --release 2>&1 \
    || die "boot₁ 编译失败（上一行有具体错误）" 1

[ -x "$BOOT1" ] || die "boot₁ 产物不存在" 1
echo "  ✓ $BOOT1 ($(ls -lh "$BOOT1" | awk '{print $5}'))"

# ═══════════════════════════════════════════════════════════════════════
# P4  bin/ 环境准备（自举验证前必须保证 bin/ 干净）
#
# bin/ 里只允许：LLVM dylibs、ld64.lld、llvm-config、include/、
#                nexus（即将被 boot₁ 临时部署）、libnexus_runtime.a
# 先清掉所有非运行时必需物，再放入 boot₁ + .a。
# ═══════════════════════════════════════════════════════════════════════
phase 4 "bin/ 环境准备"

# 先列出所有 bin/ 里的文件，保留运行时必需物
KEEP_GLOBS=("libLLVM*.dylib" "liblld*.dylib" "ld64.lld" "llvm-config" "include" "nexus_llvm_bridge.o")
echo "  清理 $BIN/（保留运行时必需物）..."
for f in "$BIN"/*; do
    base=$(basename "$f")
    keep=false
    for g in "${KEEP_GLOBS[@]}"; do
        # 简单 glob 匹配
        case "$base" in
            $g) keep=true; break ;;
        esac
    done
    if [ "$keep" = false ]; then
        echo "    rm $base"
        rm -rf "$f"
    fi
done
# libnexus_runtime.a 还没放进来
rm -f "$BIN/libnexus_runtime.a" "$BIN/nexus"

# 部署 boot₁ + runtime .a + LLVM bridge 到干净的 bin/
cp "$BOOT1" "$BIN/nexus"
cp "$RT_A" "$BIN/libnexus_runtime.a"
# LLVM bridge.o（boot₁/boot₂ 自举时需要）——从 prebuilt 取
PREBUILT_BRIDGE="$COMPILER_ROOT/runtime/prebuilt/arm64-apple-macosx13.0.0/nexus_llvm_bridge.o"
[ -f "$PREBUILT_BRIDGE" ] || PREBUILT_BRIDGE="$(find "$COMPILER_ROOT" -name nexus_llvm_bridge.o 2>/dev/null | head -1)"
if [ -f "$PREBUILT_BRIDGE" ]; then
    cp "$PREBUILT_BRIDGE" "$BIN/nexus_llvm_bridge.o"
fi
chmod +x "$BIN/nexus"

echo ""
echo "  bin/ 当前内容："
ls -1 "$BIN" | sed 's/^/    /'

# ═══════════════════════════════════════════════════════════════════════
# P5  boot₂：bin/nexus（boot₁） 自举 boot_nex_main_release.nex
#
# **完全模拟用户场景**：从任意目录（但这里用 TMP）跑 bin/nexus，
# bin/ 里有 libnexus_runtime.a（_NSGetExecutablePath 找得到）。
# boot₂ 产物放到 target/（不污染 bin/）。
# ═══════════════════════════════════════════════════════════════════════
phase 5 "boot₂：bin/nexus → boot_nex_main_release.nex（用户环境自举）"

BOOT2="$TARGET/boot2"
rm -f "$BOOT2" "$BOOT2.o"

# 清 env var，强制 bin/nexus 靠 exe-sibling 找 .a
unset NEXUS_RT_PREBUILT

export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
# posix_spawn 在 macOS 上对 PATH 继承不稳定 ⇒ 显式设
export NEX_LLVM_CONFIG="${NEX_LLVM_CONFIG:-/opt/homebrew/opt/llvm/bin/llvm-config}"

echo "  $BIN/nexus → boot₂ ..."
"$BIN/nexus" "$BOOT_SRC" -o "$BOOT2" --release 2>&1
BOOT2_RC=$?
[ $BOOT2_RC -eq 0 ] || die "boot₂ 自举失败（exit=$BOOT2_RC，上一行有具体错误）" 1
[ -x "$BOOT2" ] || die "boot₂ 产物不存在" 1
echo "  ✓ $BOOT2 ($(ls -lh "$BOOT2" | awk '{print $5}'))"

# ═══════════════════════════════════════════════════════════════════════
# P6  boot₂ 验证：把 boot₂ 放进干净 bin/，从外部编 hello_world
#
# boot₂ 自己也必须能在用户环境下工作：
#   1. boot₂ 放到 bin/（替换 boot₁）
#   2. bin/libnexus_runtime.a 已在
#   3. 从 TMP 目录跑 bin/nexus examples/01_hello_world.nex
#   4. 编出来的 hello 从 TMP 运行
# ═══════════════════════════════════════════════════════════════════════
phase 6 "boot₂ 在用户环境下编 + 跑 hello_world"

# 把 boot₂ 放进 bin/ 替换 boot₁
cp "$BOOT2" "$BIN/nexus"
chmod +x "$BIN/nexus"

unset NEXUS_RT_PREBUILT
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"

HELLO_BIN="$TMP/hello"
rm -f "$HELLO_BIN" "$HELLO_BIN.o"

echo "  $BIN/nexus → hello_world ..."
"$BIN/nexus" "$RELEASE_ROOT/examples/01_hello_world.nex" -o "$HELLO_BIN" --release 2>&1 \
    || die "boot₂ 编 hello_world 失败" 1

echo "  运行 $HELLO_BIN ..."
RUN_OUT="$("$HELLO_BIN" 2>/dev/null)"
RUN_RC=$?
echo "  stdout: $RUN_OUT"
[ "$RUN_RC" -eq 0 ] || die "hello_world 运行失败 rc=$RUN_RC" 1
echo "$RUN_OUT" | grep -qi "hello.*nexus" \
    || die "hello_world 输出异常（应含 'Hello, Nexus!'）" 1
echo "  ✓ boot₂ 用户环境自验证通过"

# ═══════════════════════════════════════════════════════════════════════
# P7  最终部署（bin/ 现在就是最终分发形态）
# ═══════════════════════════════════════════════════════════════════════
phase 7 "最终部署确认"

echo ""
echo "═══ bin/ 最终内容 ═══"
ls -lh "$BIN"/nexus "$BIN"/libnexus_runtime.a
echo ""
echo "bin/ 里 nexus ($(ls -lh "$BIN/nexus" | awk '{print $5}')) 已自举通过"
echo "下一步: $RELEASE_ROOT/scripts/distro_check.sh"
