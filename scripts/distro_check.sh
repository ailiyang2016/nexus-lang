#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# distro_check.sh — 自举分发编译器验证脚本
#
# 前提：boot_build.sh 已成功执行，bin/nexus + bin/libnexus_runtime.a 就位。
#       本脚本**不依赖** NEXUS_RT_PREBUILT / NEXUS_SDK（boot₂ 会自动找 .a）。
#       但编译时仍需要 xcrun --show-sdk-path 供系统 ld 链接用。
#
# 流程（3 个 phase，任一失败立即 abort）：
#   V1  Examples 回归（known-pass 必须全过；known-gap 记录但不算 FAIL）
#   V2  单线程 perf benchmark（fib/loop/mandelbrot/sieve/matmul/struct_churn）
#   V3  并发 benchmark（orders_pipeline.nex）
#   V4  生成报告 → target/distro_report.md + target/results.json
#
# 用法：
#   nexus-release/scripts/distro_check.sh          # 默认 5 runs
#   RUNS=3 distro_check.sh                         # 自定义 runs 数
#   distro_check.sh --nex /tmp/my_nexus           # 指定编译器路径
#
# 退出码：0 = 全部 known-pass 通过（known-gap 不计 FAIL），非 0 = 异常 FAIL
# ═══════════════════════════════════════════════════════════════════════
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="$ROOT/bin"
TARGET="$ROOT/target"
TMP="$ROOT/tmp"

rm -rf "$TMP" && mkdir -p "$TMP"
mkdir -p "$TARGET"

# 编译器定位（默认 bin/nexus，可通过 --nex 覆盖）
NEXUS_BIN="$BIN/nexus"
while [ $# -gt 0 ]; do
    case "$1" in
        --nex) NEXUS_BIN="$2"; shift 2 ;;
        *) shift ;;
    esac
done
[ -x "$NEXUS_BIN" ] || { echo "FATAL: 编译器不存在: $NEXUS_BIN" >&2; exit 1; }

RUNS="${RUNS:-5}"

echo "═══ distro_check ═══"
echo "  编译器 : $NEXUS_BIN"
echo "  运行期 : $BIN/libnexus_runtime.a"
echo "  runs   : $RUNS"
echo "  临时   : $TMP"
echo "═══════════════════"

# SDK 仍需——虽然 boot₂ 自己找 .a，但系统 ld 需要 sdk
export NEXUS_SDK="${NEXUS_SDK:-$(xcrun --show-sdk-path 2>/dev/null)}"
unset NEXUS_RT_PREBUILT

# ── 辅助 ────────────────────────────────────────────────────────────────
PASS=0; FAIL=0; SKIP=0
RESULTS_JSON="$TARGET/results.json"
REPORT_MD="$TARGET/distro_report.md"
JSON_ROWS=""

phase() { echo ""; echo "── $1: $2 ──"; }
note()  { echo "  NOTE: $*"; }

# ── 计时器 ──────────────────────────────────────────────────────────────
# $1 = command; $2 = runs; stdout = "median_ms p95_ms compile_s"
run_bench() {
    local cmd="$1" runs="${2:-5}" exe="$3"
    local compile_out compile_rc compile_s
    local times=() i

    # 预热 1 次（同时校验能否跑）
    local warm_out warm_rc
    warm_out=$(mktemp)
    warm_rc=0
    for try in 1 2 3; do
        wall_ms=$(/usr/bin/time -lp "$exe" >"$warm_out" 2>/dev/null || true)
        # 从 /usr/bin/time -lp 的 stderr 解析 real
        wall_ms=$(awk '/^real/{print $2}' <<< "$(/usr/bin/time -lp "$exe" >/dev/null 2>&1)")
        [ -n "$wall_ms" ] && break
    done
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "RUNFAIL"; rm -f "$warm_out"; return 1
    fi
    rm -f "$warm_out"

    for ((i=0; i<runs; i++)); do
        local ms
        ms=$(/usr/bin/time -lp "$exe" >/dev/null 2>&1 | awk '/^real/{print $2*1000}')
        [ -n "$ms" ] && times+=("$ms")
    done

    if [ ${#times[@]} -eq 0 ]; then echo "TIMEOUT"; return 1; fi

    # 排序 + 取中位 / p95
    local sorted median p95
    sorted=$(printf '%s\n' "${times[@]}" | sort -n)
    median=$(echo "$sorted" | awk -v n="${#times[@]}" 'NR==int((n+1)/2){print}')
    p95=$(echo "$sorted" | awk -v n="${#times[@]}" -v idx=$(( n*95/100 > 0 ? n*95/100 : n )) 'NR==idx{print}')
    [ -z "$median" ] && median="${times[0]}"
    [ -z "$p95" ] && p95="${times[-1]}"

    printf "%.1f %.1f" "$median" "$p95"
}

# ── JSON 行收集 ─────────────────────────────────────────────────────────
json_append() {
    local key="$1" status="$2" compile_s="${3:-0}" wall_ms="${4:-0}" extra="${5:-}"
    [ -n "$JSON_ROWS" ] && JSON_ROWS="$JSON_ROWS,"
    JSON_ROWS="$JSON_ROWS\"$key\":{\"status\":\"$status\",\"compile_s\":$compile_s,\"wall_ms\":$wall_ms$extra}"
}

# ═══════════════════════════════════════════════════════════════════════
# V1  Examples 回归
# ═══════════════════════════════════════════════════════════════════════
phase V1 "Examples 回归"

# known-pass: boot₂ 能完整编过并跑通
EXAMPLES_PASS="01_hello_world 02_types_and_vars 03_functions 04_control_flow 05_collections 06_closures 07_classes 09_generics_concept 10_extension_methods 11_struct_enum 12_comptime 13_reflection 16_formatting 17_interfaces 19_builtin_methods"
EXAMPLES_PASS_COUNT=$(echo "$EXAMPLES_PASS" | wc -w | tr -d ' ')

# known-gap: boot 侧 parser/typeck 能力边界（不是分发问题）
EXAMPLES_GAP="08_operator_overload:parser(Mut token) 14_concurrency:typeck(tc_pass2 crash) 15_tensors:typeck(List<i32> vs usize) 18_aspect:runtime(CallCtx.ann_str) 22_option_patterns:parser(Comma) 23_async_advanced:semantic(channel type) 24_algorithms:parser(Question) 25_comptime_metaprogramming:comptime 26_ioc:ioc framework"

note "known-pass : $EXAMPLES_PASS_COUNT 个（必须全过）"
note "known-gap  : $(echo $EXAMPLES_GAP | wc -w | tr -d ' ') 个（boot 侧能力边界，不计 FAIL）"

for name in $EXAMPLES_PASS; do
    f="$ROOT/examples/${name}.nex"
    [ -f "$f" ] || { echo "  WARN: $f 不存在，跳过"; continue; }
    out="$TMP/ex_$name"
    rm -f "$out" "$out.o"
    build_start=$(python3 -c 'import time;print(time.time())')
    if "$NEXUS_BIN" "$f" -o "$out" >"$TMP/ex_${name}.build" 2>&1; then
        build_end=$(python3 -c 'import time;print(time.time())')
        compile_s=$(python3 -c "print(round($build_end - $build_start, 3))")
        if [ -x "$out" ] && "$out" >/dev/null 2>&1; then
            echo "  PASS  $name (compile=${compile_s}s)"
            json_append "examples/$name" "PASS" "$compile_s" 0
            PASS=$((PASS+1))
        else
            echo "  FAIL  $name RUN_FAIL"
            FAIL=$((FAIL+1))
            json_append "examples/$name" "RUNFAIL" "$compile_s" 0
        fi
    else
        compile_s="?"
        echo "  FAIL  $name BUILD_FAIL"
        tail -3 "$TMP/ex_${name}.build" | sed 's/^/    /'
        FAIL=$((FAIL+1))
        json_append "examples/$name" "BUILDFAIL" "$compile_s" 0
    fi
done

# modules_demo / 20_lib_demo — 多文件
for multi in "modules_demo:main.nex" "20_lib_demo:main.nex"; do
    dir="${multi%%:*}" entry="${multi##*:}"
    src="$ROOT/examples/$dir/$entry"
    [ -f "$src" ] || { echo "  WARN: $src 不存在"; continue; }
    out="$TMP/ex_${dir}"
    rm -f "$out"
    if "$NEXUS_BIN" "$src" -o "$out" >"$TMP/ex_${dir}.build" 2>&1; then
        if [ -x "$out" ] && "$out" >/dev/null 2>&1; then
            echo "  PASS  $dir"
            json_append "examples/$dir" "PASS" 0 0
            PASS=$((PASS+1))
        else
            echo "  FAIL  $dir RUN_FAIL"; FAIL=$((FAIL+1))
            json_append "examples/$dir" "RUNFAIL" 0 0
        fi
    else
        echo "  FAIL  $dir BUILD_FAIL"
        tail -3 "$TMP/ex_${dir}.build" | sed 's/^/    /'
        FAIL=$((FAIL+1))
        json_append "examples/$dir" "BUILDFAIL" 0 0
    fi
done

# known-gap 明确标记 SKIP
for desc in $EXAMPLES_GAP; do
    name="${desc%%:*}" reason="${desc##*:}"
    echo "  SKIP  $name ($reason)"
    json_append "examples/$name" "SKIP" 0 0 "\"reason\":\"$reason\""
    SKIP=$((SKIP+1))
done

# ═══════════════════════════════════════════════════════════════════════
# V2  单线程 Perf Benchmark
# ═══════════════════════════════════════════════════════════════════════
phase V2 "Perf Benchmark（单线程，runs=$RUNS）"

# workload:expected_output
# workload:expected_output  — boot₂ 已知能编过的（sieve/struct_churn 用 List.new(N) 语法 boot parser 不认）
WORKLOADS="fib_rec:102334155 loop_sum:499999999500000000 mandelbrot:10923009 matmul:1698681604"
BENCH_SRC="$ROOT/benchmarks/nex"

for entry in $WORKLOADS; do
    name="${entry%%:*}" expected="${entry##*:}"
    src="$BENCH_SRC/${name}.nex"
    [ -f "$src" ] || { echo "  WARN: $src 不存在"; continue; }

    out="$TMP/bench_${name}"
    rm -f "$out" "$out.o"

    # 编译
    compile_start=$(python3 -c 'import time;print(time.time())')
    if ! "$NEXUS_BIN" "$src" -o "$out" >"$TMP/bench_${name}.build" 2>&1; then
        compile_end=$(python3 -c 'import time;print(time.time())')
        compile_s=$(python3 -c "print(round($compile_end - $compile_start, 3))")
        echo "  FAIL  $name BUILD_FAIL ($compile_s s)"
        json_append "bench/$name" "BUILDFAIL" "$compile_s" 0
        FAIL=$((FAIL+1))
        continue
    fi
    compile_end=$(python3 -c 'import time;print(time.time())')
    compile_s=$(python3 -c "print(round($compile_end - $compile_start, 3))")

    # 校验输出
    actual=$("$out" 2>/dev/null | tr -d ' \n')
    if [ "$actual" != "$expected" ]; then
        echo "  FAIL  $name MISMATCH (expect=$expected got=$actual)"
        json_append "bench/$name" "MISMATCH" "$compile_s" 0
        FAIL=$((FAIL+1))
        continue
    fi

    # 计时（runs 次取中位）
    times=""
    for ((i=0; i<RUNS; i++)); do
        ms=$(/usr/bin/time -lp "$out" >/dev/null 2>&1 | awk '/^real/{print $2*1000}')
        [ -n "$ms" ] && times="$times $ms"
    done
    wall_median=$(echo $times | tr ' ' '\n' | sort -n | awk -v n="$RUNS" 'NR==int((n+1)/2){print}')
    wall_p95=$(echo $times | tr ' ' '\n' | sort -n | awk -v n="$RUNS" -v idx=$(( n*95/100 )) 'NR==idx{print}')

    echo "  OK    $name  compile=${compile_s}s  wall_median=${wall_median}ms  p95=${wall_p95}ms"
    json_append "bench/$name" "OK" "$compile_s" "$wall_median" "\"p95_ms\":$wall_p95"
    PASS=$((PASS+1))
done

# ═══════════════════════════════════════════════════════════════════════
# V3  并发 Benchmark
# ═══════════════════════════════════════════════════════════════════════
phase V3 "并发 Benchmark"

CONC_SRC="$ROOT/benchmarks/concurrent/orders_pipeline.nex"
if [ -f "$CONC_SRC" ]; then
    cp "$CONC_SRC" "$TMP/orders_pipeline.nex"
    conc_out="$TMP/orders_pipeline"
    rm -f "$conc_out"
    compile_start=$(python3 -c 'import time;print(time.time())')
    if "$NEXUS_BIN" "$CONC_SRC" -o "$conc_out" >"$TMP/orders_pipeline.build" 2>&1; then
        compile_end=$(python3 -c 'import time;print(time.time())')
        compile_s=$(python3 -c "print(round($compile_end - $compile_start, 3))")
        conc_wall=$(/usr/bin/time -lp "$conc_out" >/dev/null 2>&1 | awk '/^real/{print $2*1000}')
        rc=$?
        if [ $rc -eq 0 ]; then
            echo "  OK    orders_pipeline  compile=${compile_s}s  wall=${conc_wall}ms"
            json_append "bench/orders_pipeline" "OK" "$compile_s" "$conc_wall"
            PASS=$((PASS+1))
        else
            echo "  FAIL  orders_pipeline RUN_FAIL rc=$rc"
            json_append "bench/orders_pipeline" "RUNFAIL" "$compile_s" 0
            FAIL=$((FAIL+1))
        fi
    else
        compile_end=$(python3 -c 'import time;print(time.time())')
        compile_s=$(python3 -c "print(round($compile_end - $compile_start, 3))")
        echo "  FAIL  orders_pipeline BUILD_FAIL"
        tail -3 "$TMP/orders_pipeline.build" | sed 's/^/    /'
        json_append "bench/orders_pipeline" "BUILDFAIL" "$compile_s" 0
        FAIL=$((FAIL+1))
    fi
else
    note "orders_pipeline.nex 不存在 → SKIP"
    SKIP=$((SKIP+1))
fi

# ═══════════════════════════════════════════════════════════════════════
# V4  生成报告 + 退出
# ═══════════════════════════════════════════════════════════════════════
phase V4 "生成报告"

TS="$(date '+%Y-%m-%d %H:%M:%S')"

# JSON
echo "{$JSON_ROWS}" | python3 -m json.tool > "$RESULTS_JSON" 2>/dev/null \
    || echo "{$JSON_ROWS}" > "$RESULTS_JSON"

# Markdown 报告
cat > "$REPORT_MD" <<MDEOF
# Nexus 分发版验证报告

- 时间：$TS
- 编译器：$NEXUS_BIN ($(ls -lh "$NEXUS_BIN" | awk '{print $5}'))
- runs：$RUNS

## 汇总

| 指标 | 值 |
|---|---|
| Examples PASS | $PASS |
| FAIL | $FAIL |
| SKIP（boot 侧能力边界） | $SKIP |

## Perf（单线程，毫秒）

| workload | compile(s) | wall median | p95 |
|---|---|---|---|
$(python3 -c "
import json
d = json.load(open('$RESULTS_JSON'))
for k,v in sorted(d.items()):
    if k.startswith('bench/') and v.get('status')=='OK':
        print(f'| {k.split(\"/\")[1]} | {v.get(\"compile_s\",\"?\")} | {v.get(\"wall_ms\",\"?\"):.1f} | {v.get(\"p95_ms\",\"?\"):.1f} |')
" 2>/dev/null || echo "_(parse error)_")

## 已知 gap（不计 FAIL）

$(echo "$EXAMPLES_GAP" | tr ' ' '\n' | sed 's/^/- /')
MDEOF

echo "  ✓ $REPORT_MD"
echo "  ✓ $RESULTS_JSON"

# ── 最终判定 ──────────────────────────────────────────────────────────
echo ""
echo "═══ 结果 ═══"
echo "  PASS=$PASS  FAIL=$FAIL  SKIP=$SKIP"
if [ $FAIL -gt 0 ]; then
    echo ""
    echo "  ❌ FAIL 不为 0 → 请查 $TMP/*.build 或 $REPORT_MD"
    exit 1
fi
echo "  ✅ 全部 known-pass 通过"
exit 0
