// 并发业务基准：订单流水线（Go 对照版，与 orders_pipeline.nex 逐语义对齐）
//
// 通道：make(chan Order, 64) 输入背压 / make(chan Agg, 4) 输出
//   Go 的 buffered channel 天然是多生产者多消费者安全的，两个 worker
//   从同一个 chIn 竞争读，负载均衡由 Go runtime 调度器完成。
//   worker 停止：精确消费 N_PER_WORKER 条，不靠 close 信号。
//
// 编译：go build -o orders_pipeline_go orders_pipeline.go

package main

import (
	"fmt"
	"math"
)

const (
	N_ORDERS     int64 = 2000000
	N_PER_WORKER       int64 = N_ORDERS / 2
)

type Order struct {
	id     int64
	amount float64
	cat    int64
}

type Agg struct {
	total                 float64
	count                 int64
	cat0, cat1, cat2, cat3 float64
}

func absorb(agg *Agg, o Order) {
	agg.total += o.amount
	agg.count++
	switch o.cat {
	case 0:
		agg.cat0 += o.amount
	case 1:
		agg.cat1 += o.amount
	case 2:
		agg.cat2 += o.amount
	default:
		agg.cat3 += o.amount
	}
}

func merge(a, b Agg) Agg {
	return Agg{
		total: a.total + b.total,
		count: a.count + b.count,
		cat0:  a.cat0 + b.cat0,
		cat1:  a.cat1 + b.cat1,
		cat2:  a.cat2 + b.cat2,
		cat3:  a.cat3 + b.cat3,
	}
}

func worker(chIn <-chan Order, chOut chan<- Agg) {
	var agg Agg
	for i := int64(0); i < N_PER_WORKER; i++ {
		o := <-chIn
		absorb(&agg, o)
	}
	chOut <- agg
}

func main() {
	chIn  := make(chan Order, 64)
	chOut := make(chan Agg,   4)

	// 启动两个 worker（竞争消费同一 chIn）
	go worker(chIn, chOut)
	go worker(chIn, chOut)

	// producer：main goroutine 推送 N_ORDERS 笔订单
	for j := int64(0); j < N_ORDERS; j++ {
		chIn <- Order{
			id:     j,
			amount: float64(j%97) + 1.0,
			cat:    j % 4,
		}
	}

	// 收两个 worker 的聚合结果
	a1 := <-chOut
	a2 := <-chOut

	total := merge(a1, a2)

	fmt.Printf("count=%d\n", total.count)
	fmt.Printf("total=%.2f\n", total.total)

	// —— 闭式校验公式（与 Nexus 源码完全相同）——
	full        := float64(97 * 98 / 2)
	fullCycles  := float64(N_ORDERS / 97)
	rem         := float64(N_ORDERS % 97)
	expectTotal := fullCycles*full + rem*(rem+1)/2
	expectCount := N_ORDERS

	if total.count != expectCount {
		fmt.Printf("COUNT MISMATCH: got %d want %d\n", total.count, expectCount)
		return
	}
	if math.Abs(total.total-expectTotal) > 1e-6 {
		fmt.Printf("TOTAL MISMATCH: got %.2f want %.2f\n", total.total, expectTotal)
		return
	}

	fmt.Printf("cat0=%.2f cat1=%.2f cat2=%.2f cat3=%.2f\n",
		total.cat0, total.cat1, total.cat2, total.cat3)
	fmt.Println("CHECKSUM OK")
}
