package main

import (
	"fmt"
	"os"
)

func mandel(cx, cy float64, maxIter int32) int32 {
	x, y := 0.0, 0.0
	var i int32 = 0
	for i < maxIter {
		x2 := x * x
		y2 := y * y
		if x2+y2 > 4.0 {
			return i
		}
		xt := x2 - y2 + cx
		y = 2.0*x*y + cy
		x = xt
		i++
	}
	return maxIter
}

func main() {
	n := int32(600)
	var total int64 = 0
	for py := int32(0); py < n; py++ {
		for px := int32(0); px < n; px++ {
			cx := float64(px)/float64(n)*3.0 - 2.0
			cy := float64(py)/float64(n)*2.0 - 1.0
			total += int64(mandel(cx, cy, 100))
		}
	}
	fmt.Println(total)
	var expected int64 = 10922953
	if total == expected {
		fmt.Println("CHECKSUM OK")
		os.Exit(0)
	} else {
		fmt.Println("CHECKSUM MISMATCH")
		os.Exit(1)
	}
}
