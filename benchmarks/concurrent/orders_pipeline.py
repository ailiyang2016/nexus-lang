# 并发业务基准：订单流水线（Python 对照版，与 orders_pipeline.nex 逐语义对齐）
# 运行：python3 orders_pipeline.py
# 说明：CPython 受 GIL 影响——queue.Queue 的并发是线程切换型而非并行型；
#       这是语言运行时的真实行为差异，基准如实呈现（不刻意绕开）。
import queue
import threading

N_ORDERS = 20000
N_PER_WORKER = 10000

class Order:
    __slots__ = ("id", "amount", "cat")
    def __init__(self, id, amount, cat):
        self.id = id; self.amount = amount; self.cat = cat

ch_in = queue.Queue(maxsize=64)   # bounded 背压，与 Nexus Channel::bounded(64) 同语义
ch_out = queue.Queue(maxsize=4)

def worker():
    total = 0.0; count = 0; cat0 = cat1 = cat2 = cat3 = 0.0
    for _ in range(N_PER_WORKER):
        o = ch_in.get()
        total += o.amount; count += 1
        if o.cat == 0: cat0 += o.amount
        elif o.cat == 1: cat1 += o.amount
        elif o.cat == 2: cat2 += o.amount
        else: cat3 += o.amount
    ch_out.put((total, count, cat0, cat1, cat2, cat3))

def main():
    w1 = threading.Thread(target=worker); w2 = threading.Thread(target=worker)
    w1.start(); w2.start()
    for i in range(N_ORDERS):
        ch_in.put(Order(i, (i % 97) + 1.0, i % 4))
    a1 = ch_out.get(); a2 = ch_out.get()
    w1.join(); w2.join()
    total = a1[0] + a2[0]; count = a1[1] + a2[1]
    print(f"count={count}")
    print(f"total={total:.2f}")
    full = 97 * 98 // 2; cycles = N_ORDERS // 97; rem = N_ORDERS % 97
    expect = cycles * full + rem * (rem + 1) // 2
    if count != N_ORDERS or abs(total - expect) > 1e-6:
        print("MISMATCH"); raise SystemExit(1)
    print(f"cat0={a1[2]+a2[2]:.2f} cat1={a1[3]+a2[3]:.2f} cat2={a1[4]+a2[4]:.2f} cat3={a1[5]+a2[5]:.2f}")
    print("CHECKSUM OK")

main()
