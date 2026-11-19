#!/usr/bin/env python3
# ============================================================
# 基准主脚本：编译 + 运行 + 计时（中位数/p95）+ CPU + 峰值 RSS + 编译时长 + 产物大小。
#
# 用法：
#   python3 benchmarks/run_benchmarks.py                # 单线程 6 负载 × 全语言
#   python3 benchmarks/run_benchmarks.py --concurrent   # 并发 orders_pipeline × 多规模 × 全语言
#   python3 benchmarks/run_benchmarks.py --all          # 两者
#   python3 benchmarks/run_benchmarks.py --runs 5 --nexus-only
#
# 口径：
#   * 每负载先跑 1 次预热丢弃；runs 次取墙钟中位数与 p95；
#   * CPU＝user+sys（同一轮 /usr/bin/time -l 采集）；峰值 RSS 同源；
#   * 校验和不对即判 FAIL（性能数字不作数）；
#   * Nexus 用分发编译器 bin/nexus（LLVM 后端，--release）。
# ============================================================
import argparse
import os
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BC = os.path.join(ROOT, "benchmarks")
NEXUS = os.path.join(ROOT, "bin", "nexus")

# 自动检测分发版 runtime（用户不需要手动 export）
if not os.environ.get("NEXUS_RT_PREBUILT"):
    for cand in ("libnexus_runtime.a", "nexus_runtime"):
        p = os.path.join(ROOT, "bin", cand)
        if os.path.isfile(p):
            os.environ["NEXUS_RT_PREBUILT"] = p
            break
if not os.environ.get("NEXUS_SDK"):
    r = subprocess.run(["xcrun", "--show-sdk-path"], capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip():
        os.environ["NEXUS_SDK"] = r.stdout.strip()

WORKLOADS = {
    "fib_rec": "102334155",
    "loop_sum": "499999999500000000",
    # Go 规范允许 FMA 收缩（同一算法末位不同）；C/C++ 以 -ffp-contract=off 对齐严格 IEEE。
    "mandelbrot": ("10923009", "10922953"),
    "sieve": "348513",
    "matmul": "1698681604",
    "struct_churn": "5999997000000",
}

def _match(out, check):
    """校验：check 为字符串或可接受集合（任一命中即通过）。"""
    if isinstance(check, (tuple, list)):
        return any(c in out for c in check)
    return check in out


TIME_RE = re.compile(r"([\d.]+)\s+real\s+([\d.]+)\s+user\s+([\d.]+)\s+sys")
RSS_RE = re.compile(r"(\d+)\s+maximum resident set size")


def run_once(cmd, cwd=None, timeout=900):
    """单次运行（经 /usr/bin/time -l）：返回 (real_ms, cpu_ms, rss_mb, rc, stdout)。"""
    r = subprocess.run(["/usr/bin/time", "-l"] + cmd, cwd=cwd,
                       capture_output=True, text=True, timeout=timeout)
    m = TIME_RE.search(r.stderr)
    real = float(m.group(1)) * 1000.0 if m else None
    cpu = (float(m.group(2)) + float(m.group(3))) * 1000.0 if m else None
    mr = RSS_RE.search(r.stderr)
    rss = int(mr.group(1)) / (1024.0 * 1024.0) if mr else None
    return real, cpu, rss, r.returncode, r.stdout


def measure(cmd, runs=5, cwd=None, check=None, timeout=900):
    """预热 1 次丢弃 ⇒ runs 次取中位/p95/CPU/RSS。校验失败返回 None。"""
    _, _, _, rc, out = run_once(cmd, cwd, timeout)
    if rc != 0:
        return None
    if check and not _match(out, check):
        return None
    reals, cpus, rsss = [], [], []
    for _ in range(runs):
        real, cpu, rss, rc2, out2 = run_once(cmd, cwd, timeout)
        if rc2 != 0:
            return None
        if check and not _match(out2, check):
            return None
        reals.append(real)
        if cpu is not None:
            cpus.append(cpu)
        if rss is not None:
            rsss.append(rss)
    reals.sort()
    p95 = reals[min(len(reals) - 1, int(round(len(reals) * 0.95)) - 1)]
    return {
        "real": statistics.median(reals),
        "p95": p95,
        "cpu": statistics.median(cpus) if cpus else None,
        "rss": max(rsss) if rsss else None,
    }


def compile_cmd(kind, src, exe):
    if kind == "nex":
        return [NEXUS, src, "-o", exe, "--release"]
    if kind == "c":
        return ["cc", "-O2", src, "-o", exe]
    if kind == "cpp":
        return ["clang++", "-std=c++17", "-O2", "-pthread", "-ffp-contract=off", src, "-o", exe]
    if kind == "rust":
        return ["rustc", "-O", src, "-o", exe]
    if kind == "go":
        return ["go", "build", "-o", exe, src]
    raise ValueError(kind)


def timed_compile(cmd):
    t0 = time.perf_counter()
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    return (time.perf_counter() - t0), r.returncode, (r.stderr or "")


def have(tool):
    return shutil.which(tool) is not None


def bench_single(runs, kinds):
    """单线程：6 负载 × 语言。返回 {lang: {workload: row}}。"""
    out = {}
    exts = {"nex": "nex", "c": "c", "cpp": "cpp", "rust": "rs", "go": "go"}
    dirs = {"nex": "nex", "c": "c", "cpp": "cpp", "rust": "rust", "go": "go"}
    for kind in kinds:
        if kind == "python":
            continue
        out[kind] = {}
        for name in WORKLOADS:
            src = os.path.join(BC, dirs[kind], f"{name}.{exts[kind]}")
            if not os.path.isfile(src):
                out[kind][name] = {"status": "ABSENT"}
                continue
            exe = os.path.join(tempfile.gettempdir(), f"nxb_{name}_{kind}")
            ctime, rc, err = timed_compile(compile_cmd(kind, src, exe))
            if rc != 0:
                out[kind][name] = {"status": "BUILD_FAIL", "err": err.strip().split("\n")[0][:120]}
                continue
            size_kb = os.path.getsize(exe) / 1024.0
            m = measure([exe], runs=runs, check=WORKLOADS[name])
            if m is None:
                out[kind][name] = {"status": "RUN_FAIL"}
                continue
            m["status"] = "OK"
            m["compile_s"] = ctime
            m["size_kb"] = size_kb
            out[kind][name] = m
    # Python：解释执行（无编译），只计运行
    if "python" in kinds:
        out["python"] = {}
        for name in WORKLOADS:
            src = os.path.join(BC, "python", f"{name}.py")
            if not os.path.isfile(src):
                out["python"][name] = {"status": "ABSENT"}
                continue
            m = measure(["python3", src], runs=max(1, runs // 2), check=WORKLOADS[name], timeout=1800)
            if m is None:
                out["python"][name] = {"status": "RUN_FAIL"}
                continue
            m["status"] = "OK"
            m["compile_s"] = 0.0
            m["size_kb"] = 0.0
            out["python"][name] = m
    return out


# ── 并发：orders_pipeline（同一算法 × 多规模） ─────────────────────
def gen_concurrent_sources(n, tmpdir):
    """按规模生成各语言源码；返回 {lang: srcpath}。"""
    half = n // 2
    paths = {}
    # Nexus：原文硬编码 20000/10000/97 派生式
    src = os.path.join(BC, "concurrent", "orders_pipeline.nex")
    t = open(src, encoding="utf-8").read()
    t = t.replace("while j < 20000", f"while j < {n}")
    t = t.replace("worker(ch_in, ch_out, 10000)", f"worker(ch_in, ch_out, {half})")
    t = t.replace("20000 / 97", f"{n} / 97").replace("20000 % 97", f"{n} % 97")
    t = t.replace("expect_count = 20000", f"expect_count = {n}")
    p = os.path.join(tmpdir, f"op_{n}.nex")
    open(p, "w", encoding="utf-8").write(t)
    paths["nex"] = p
    # 其余语言：只改 N_ORDERS 常量（N_PER_WORKER = N_ORDERS/2 派生）
    for kind, fname in (("cpp", "orders_pipeline.cpp"), ("rust", "orders_pipeline.rs"), ("go", "orders_pipeline.go")):
        s = os.path.join(BC, "concurrent", fname)
        if not os.path.isfile(s):
            continue
        t = open(s, encoding="utf-8").read()
        t2 = re.sub(r"(N_ORDERS[^=\n]*=\s*)\d+", r"\g<1>%d" % n, t, count=1)
        p = os.path.join(tmpdir, f"op_{n}.{ 'rs' if kind=='rust' else kind }")
        open(p, "w", encoding="utf-8").write(t2)
        paths[kind] = p
    return paths


def bench_concurrent(runs, scales, kinds):
    out = {}
    tmpdir = tempfile.mkdtemp(prefix="nxb_conc_")
    for n in scales:
        paths = gen_concurrent_sources(n, tmpdir)
        out[n] = {}
        for kind in kinds:
            if kind not in paths:
                out[n][kind] = {"status": "ABSENT"}
                continue
            src = paths[kind]
            exe = os.path.join(tmpdir, f"op_{n}_{kind}")
            ctime, rc, err = timed_compile(compile_cmd(kind, src, exe))
            if rc != 0:
                out[n][kind] = {"status": "BUILD_FAIL", "err": err.strip().split("\n")[0][:120]}
                continue
            m = measure([exe], runs=runs, check="CHECKSUM OK")
            if m is None:
                out[n][kind] = {"status": "RUN_FAIL"}
                continue
            m["status"] = "OK"
            m["compile_s"] = ctime
            m["size_kb"] = os.path.getsize(exe) / 1024.0
            out[n][kind] = m
    return out


def fmt(v, key, unit="", digits=1):
    if v.get("status") != "OK" or v.get(key) is None:
        return v.get("status", "-")
    return f"{v[key]:.{digits}f}{unit}"


def print_single(res, kinds):
    print()
    print("═══ 单线程：运行时间中位数（ms，越小越快） ═══")
    head = f"{'workload':<14}" + "".join(f"{k:>12}" for k in kinds)
    print(head)
    for name in WORKLOADS:
        row = f"{name:<14}"
        for k in kinds:
            row += f"{fmt(res.get(k, {}).get(name, {}), 'real'):>12}"
        print(row)
    print()
    print("═══ 单线程：CPU 时间中位数（user+sys，ms） ═══")
    print(head)
    for name in WORKLOADS:
        row = f"{name:<14}"
        for k in kinds:
            row += f"{fmt(res.get(k, {}).get(name, {}), 'cpu'):>12}"
        print(row)
    print()
    print("═══ 单线程：峰值 RSS（MB） ═══")
    print(head)
    for name in WORKLOADS:
        row = f"{name:<14}"
        for k in kinds:
            row += f"{fmt(res.get(k, {}).get(name, {}), 'rss'):>12}"
        print(row)
    print()
    print("═══ 单线程：产物大小（KB） ═══")
    print(head)
    for name in WORKLOADS:
        row = f"{name:<14}"
        for k in kinds:
            row += f"{fmt(res.get(k, {}).get(name, {}), 'size_kb', '', 0):>12}"
        print(row)
    print()
    print("═══ 单线程：编译时长（s） ═══")
    print(head)
    for name in WORKLOADS:
        row = f"{name:<14}"
        for k in kinds:
            row += f"{fmt(res.get(k, {}).get(name, {}), 'compile_s', '', 3):>12}"
        print(row)


def print_concurrent(res, kinds, scales):
    print()
    print("═══ 并发 orders_pipeline：运行时间中位数（ms） ═══")
    head = f"{'N':>10}" + "".join(f"{k:>12}" for k in kinds)
    print(head)
    for n in scales:
        row = f"{n:>10}"
        for k in kinds:
            row += f"{fmt(res.get(n, {}).get(k, {}), 'real'):>12}"
        print(row)
    print()
    print("═══ 并发 orders_pipeline：CPU 时间（user+sys，ms） ═══")
    print(head)
    for n in scales:
        row = f"{n:>10}"
        for k in kinds:
            row += f"{fmt(res.get(n, {}).get(k, {}), 'cpu'):>12}"
        print(row)
    print()
    print("═══ 并发 orders_pipeline：峰值 RSS（MB） ═══")
    print(head)
    for n in scales:
        row = f"{n:>10}"
        for k in kinds:
            row += f"{fmt(res.get(n, {}).get(k, {}), 'rss'):>12}"
        print(row)
    print()
    print("═══ 并发 orders_pipeline：产物大小（KB） ═══")
    print(head)
    for n in scales:
        row = f"{n:>10}"
        for k in kinds:
            row += f"{fmt(res.get(n, {}).get(k, {}), 'size_kb', '', 0):>12}"
        print(row)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--nexus-only", action="store_true")
    ap.add_argument("--concurrent", action="store_true")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--scales", default="20000,200000,2000000")
    args = ap.parse_args()

    kinds = ["nex"]
    if not args.nexus_only:
        if have("cc"):
            kinds.append("c")
        if have("clang++"):
            kinds.append("cpp")
        if have("rustc"):
            kinds.append("rust")
        if have("go"):
            kinds.append("go")
        if have("python3"):
            kinds.append("python")

    do_single = not args.concurrent or args.all
    do_conc = args.concurrent or args.all

    print(f"Nexus 编译器: {NEXUS}")
    print(f"语言列: {', '.join(kinds)}   runs={args.runs}")

    if do_single:
        res = bench_single(args.runs, kinds)
        print_single(res, kinds)
    if do_conc:
        scales = [int(x) for x in args.scales.split(",") if x.strip()]
        titles = ["workload"]
        print()
        print(f"并发规模: {scales}")
        res = bench_concurrent(args.runs, scales, [k for k in kinds if k != "python"])
        print_concurrent(res, [k for k in kinds if k != "python"], scales)

    print()
    print("口径：墙钟中位（预热 1 次丢弃，runs=%d）；CPU＝user+sys 中位；RSS＝多次运行峰值；"
          "编译时长含链接；校验和不符的负载不计入。同机同 commit 下比较才有效。" % args.runs)


if __name__ == "__main__":
    sys.exit(main())
