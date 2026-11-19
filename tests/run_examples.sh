#!/bin/sh
# 逐个编译+运行 examples，汇总结果（分发目录收尾用，保留在 tests/ 内）。
# 适配分发版 boot₂：恒走 llvm-embed，无 dev flag（--backend / --crate-type / -O 等）。
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# NEXUS_RT_PREBUILT / NEXUS_SDK：分发版 nexus_llvm.c 会从 exe 同目录自动找 .a，
# 但本地开发跑时仍需要 SDK（xcrun --show-sdk-path）。
if [ -z "$NEXUS_SDK" ] && command -v xcrun >/dev/null 2>&1; then
    export NEXUS_SDK=$(xcrun --show-sdk-path 2>/dev/null)
fi

NEX=${NEX:-./bin/nexus}
if [ "$1" = "--nex" ] && [ -n "$2" ]; then NEX="$2"; shift 2; fi
case "$NEX" in
    /*) ;;
    *) NEX="$ROOT/$NEX" ;;
esac
BUILD="$ROOT/tmp/examples"
mkdir -p "$BUILD"
pass=0; fail=0; skip=0
for f in examples/*.nex; do
    name=$(basename "$f" .nex)
    rm -f "$BUILD/$name"
    if ! $NEX "$f" -o "$BUILD/$name" >"$BUILD/$name.build" 2>&1 \
       || [ ! -x "$BUILD/$name" ]; then
        echo "BUILD_FAIL $name:"; head -3 "$BUILD/$name.build" | sed 's/^/    /'
        fail=$((fail+1)); continue
    fi
    out=$("$BUILD/$name" 2>&1); rc=$?
    if [ $rc -ne 0 ]; then
        echo "RUN_FAIL  $name rc=$rc: $(echo "$out" | head -1)"
        fail=$((fail+1)); continue
    fi
    echo "OK $name ($(echo "$out" | wc -l | tr -d ' ') lines)"
    pass=$((pass+1))
done
# 多文件项目：模块库
cd "$ROOT/examples/modules_demo"
rm -f "$BUILD/modules_demo"
if $NEX main.nex -o "$BUILD/modules_demo" >"$BUILD/modules_demo.build" 2>&1 \
   && [ -x "$BUILD/modules_demo" ]; then
    out=$("$BUILD/modules_demo" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then echo "OK modules_demo ($(echo "$out" | head -1))"; pass=$((pass+1))
    else echo "RUN_FAIL  modules_demo rc=$rc: $(echo "$out" | head -1)"; fail=$((fail+1)); fi
else
    echo "BUILD_FAIL modules_demo:"; head -3 "$BUILD/modules_demo.build" | sed 's/^/    /'
    fail=$((fail+1))
fi
# 20 库工程（模块 lib）
cd "$ROOT/examples/20_lib_demo"
rm -f "$BUILD/libdemo"
if $NEX main.nex -o "$BUILD/libdemo" >"$BUILD/libdemo.build" 2>&1 \
   && [ -x "$BUILD/libdemo" ]; then
    out=$("$BUILD/libdemo" 2>&1); rc=$?
    if [ $rc -eq 0 ]; then echo "OK 20_lib_demo ($(echo "$out" | head -1))"; pass=$((pass+1))
    else echo "RUN_FAIL  20_lib_demo rc=$rc"; fail=$((fail+1)); fi
else
    echo "BUILD_FAIL 20_lib_demo:"; head -3 "$BUILD/libdemo.build" | sed 's/^/    /'
    fail=$((fail+1))
fi
cd ../..

# 21 FFI/ABI（需要 --crate-type cdylib 产 dylib，分发版不支持 → SKIP）
echo "SKIP 21_ffi_abi (分发版不产 dylib，--crate-type 已退休)"
skip=$((skip+1))

cd "$ROOT"
echo "== examples: pass=$pass fail=$fail skip=$skip =="
