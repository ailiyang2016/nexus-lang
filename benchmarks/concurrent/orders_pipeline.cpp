// 并发业务基准：订单流水线（C++ 对照版，与 orders_pipeline.nex 逐语义对齐）
//
// 场景：producer 推 200000 笔 Order{id, amount=(j%97)+1.0, cat=j%4}，
// 两个 worker 从同一输入 channel 竞争消费（各 250000 条），
// 各自聚合本地 Agg{total, count, cat0..cat3}，推给输出 channel，
// 主线程合并后按闭式公式校验 checksum。
//
// 通道：bounded(64) 输入背压 / bounded(4) 输出；
// 同步原语：std::thread + std::mutex + std::condition_variable（简单即可，
// 不依赖 C++20 counting_semaphore）；
// worker 停止：精确消费 250000 条，不靠 poison pill / close。
//
// 编译：clang++ -std=c++17 -O2 -pthread orders_pipeline.cpp -o orders_pipeline_cpp

#include <cstdio>
#include <cstdint>
#include <deque>
#include <mutex>
#include <condition_variable>
#include <thread>
#include <cmath>

constexpr int64_t N_ORDERS     = 2000000;
constexpr int64_t N_PER_WORKER = N_ORDERS / 2;

struct Order { int64_t id; double amount; int64_t cat; };
struct Agg {
    double total = 0.0;
    int64_t count = 0;
    double cat0 = 0.0, cat1 = 0.0, cat2 = 0.0, cat3 = 0.0;
};

// BoundedQueue —— 与 Nexus `Channel<T>::bounded(N)` 同语义：
//   send: 队列满时阻塞；recv: 队列空时阻塞。capacity 固定，无 close/EOF 语义。
template <typename T>
struct BoundedQueue {
    std::deque<T> q;
    std::mutex m;
    std::condition_variable cv;
    size_t cap;
    explicit BoundedQueue(size_t c) : cap(c) {}

    void send(const T& v) {
        std::unique_lock<std::mutex> lk(m);
        cv.wait(lk, [&] { return q.size() < cap; });
        q.push_back(v);
        cv.notify_one();
    }

    T recv() {
        std::unique_lock<std::mutex> lk(m);
        cv.wait(lk, [&] { return !q.empty(); });
        T v = std::move(q.front());
        q.pop_front();
        cv.notify_one();
        return v;
    }
};

BoundedQueue<Order> ch_in(64);
BoundedQueue<Agg>   ch_out(4);

void worker() {
    Agg agg;
    for (int64_t i = 0; i < N_PER_WORKER; ++i) {
        Order o = ch_in.recv();
        agg.total += o.amount;
        agg.count += 1;
        if      (o.cat == 0) agg.cat0 += o.amount;
        else if (o.cat == 1) agg.cat1 += o.amount;
        else if (o.cat == 2) agg.cat2 += o.amount;
        else                 agg.cat3 += o.amount;
    }
    ch_out.send(agg);
}

int main() {
    std::thread w1(worker);
    std::thread w2(worker);

    // producer：在 main 线程推送 N_ORDERS 笔订单
    for (int64_t j = 0; j < N_ORDERS; ++j) {
        ch_in.send(Order{ j, (double)(j % 97) + 1.0, j % 4 });
    }

    Agg a1 = ch_out.recv();
    Agg a2 = ch_out.recv();

    w1.join();
    w2.join();

    Agg total{
        a1.total + a2.total,
        a1.count + a2.count,
        a1.cat0 + a2.cat0,
        a1.cat1 + a2.cat1,
        a1.cat2 + a2.cat2,
        a1.cat3 + a2.cat3,
    };

    printf("count=%lld\n",   (long long)total.count);
    printf("total=%.2f\n",   total.total);

    // —— 闭式校验公式（与 Nexus 源码完全相同）——
    // amount_j = (j % 97) + 1.0
    // full        = 1 + 2 + ... + 97 = 97*98/2 = 4753
    // full_cycles = 200000 / 97 = 5154
    // rem         = 200000 % 97 = 62
    // expect_total = full_cycles * full + rem*(rem+1)/2
    int64_t full        = 97LL * 98 / 2;  // 4753
    int64_t full_cycles = N_ORDERS / 97;
    int64_t rem         = N_ORDERS % 97;
    double  expect_total = (double)(full_cycles * full)
                         + (double)(rem * (rem + 1) / 2);
    const int64_t expect_count = N_ORDERS;

    if (total.count != expect_count) {
        printf("COUNT MISMATCH: got %lld want %lld\n",
               (long long)total.count, (long long)expect_count);
        return 1;
    }
    if (std::fabs(total.total - expect_total) > 1e-6) {
        printf("TOTAL MISMATCH: got %.2f want %.2f\n", total.total, expect_total);
        return 1;
    }

    printf("cat0=%.2f cat1=%.2f cat2=%.2f cat3=%.2f\n",
           total.cat0, total.cat1, total.cat2, total.cat3);
    printf("CHECKSUM OK\n");
    return 0;
}
