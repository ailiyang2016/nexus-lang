// 并发业务基准：订单流水线（Rust 对照版，与 orders_pipeline.nex 逐语义对齐）
//
// 通道：std::sync::mpsc::sync_channel（bounded）
//   输入  capacity = 64  （背压）
//   输出  capacity = 4
//   多 worker 竞争同一输入：sync_channel 的 Receiver 非 Clone，
//   因此用 Arc<Mutex<Receiver<Order>>> 包装，每次 recv 持锁直到拿到一条。
//   worker 停止：精确消费 N_PER_WORKER 条，不靠 poison pill / 通道关闭。
//
// 编译：rustc -O orders_pipeline.rs -o orders_pipeline_rs

use std::sync::{Arc, Mutex, mpsc};
use std::thread;

const N_ORDERS: i64     = 2000000;
const N_PER_WORKER: i64 = N_ORDERS / 2;

#[derive(Debug, Clone)]
struct Order {
    id: i64,
    amount: f64,
    cat: i64,
}

#[derive(Debug, Clone, Default)]
struct Agg {
    total: f64,
    count: i64,
    cat0: f64,
    cat1: f64,
    cat2: f64,
    cat3: f64,
}

impl Agg {
    fn absorb(&mut self, o: &Order) {
        self.total += o.amount;
        self.count += 1;
        match o.cat {
            0 => self.cat0 += o.amount,
            1 => self.cat1 += o.amount,
            2 => self.cat2 += o.amount,
            _ => self.cat3 += o.amount,
        }
    }
}

fn main() {
    let (tx_in, rx_in) = mpsc::sync_channel::<Order>(64);
    let (tx_out, rx_out) = mpsc::sync_channel::<Agg>(4);

    // 多 worker 竞争同一输入端：Receiver 用 Mutex 包起来
    let rx_in_shared = Arc::new(Mutex::new(rx_in));

    let mut handles = Vec::with_capacity(2);
    for _ in 0..2 {
        let rx_clone = Arc::clone(&rx_in_shared);
        let tx_clone = tx_out.clone();
        handles.push(thread::spawn(move || {
            let mut agg = Agg::default();
            for _ in 0..N_PER_WORKER {
                // 持锁等待一条 Order；sync_channel 阻塞直到有数据
                let rx = rx_clone.lock().unwrap();
                let o  = rx.recv().expect("producer 已退出但订单数不够");
                // 锁立即释放，允许另一个 worker 进来
                drop(rx);
                agg.absorb(&o);
            }
            tx_clone.send(agg).expect("输出通道另一端断开");
        }));
    }

    // producer：main 线程推送 N_ORDERS 笔订单
    for j in 0..N_ORDERS {
        tx_in.send(Order {
            id: j,
            amount: (j % 97) as f64 + 1.0,
            cat:    j % 4,
        }).expect("输入通道另一端断开");
    }

    // 收两个 worker 的聚合结果
    let a1 = rx_out.recv().expect("worker 1 未返回 Agg");
    let a2 = rx_out.recv().expect("worker 2 未返回 Agg");

    for h in handles {
        h.join().unwrap();
    }

    let total = Agg {
        total: a1.total + a2.total,
        count: a1.count + a2.count,
        cat0:  a1.cat0  + a2.cat0,
        cat1:  a1.cat1  + a2.cat1,
        cat2:  a1.cat2  + a2.cat2,
        cat3:  a1.cat3  + a2.cat3,
    };

    println!("count={}", total.count);
    println!("total={:.2}", total.total);

    // —— 闭式校验公式（与 Nexus 源码完全相同）——
    let full        = 97i64 * 98 / 2;            // 4753
    let full_cycles = N_ORDERS / 97;             // 5154
    let rem         = N_ORDERS % 97;             // 62
    let expect_total = (full_cycles * full + rem * (rem + 1) / 2) as f64;
    let expect_count = N_ORDERS;

    if total.count != expect_count {
        println!("COUNT MISMATCH: got {} want {}", total.count, expect_count);
        std::process::exit(1);
    }
    if (total.total - expect_total).abs() > 1e-6 {
        println!("TOTAL MISMATCH: got {:.2} want {:.2}", total.total, expect_total);
        std::process::exit(1);
    }

    println!(
        "cat0={:.2} cat1={:.2} cat2={:.2} cat3={:.2}",
        total.cat0, total.cat1, total.cat2, total.cat3
    );
    println!("CHECKSUM OK");
}
