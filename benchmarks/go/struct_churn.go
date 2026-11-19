package main

import (
	"fmt"
	"os"
)

type Point struct {
	X, Y int64
}

func main() {
	var n int64 = 2000000
	pts := make([]Point, n)
	for i := int64(0); i < n; i++ {
		pts[i].X = i
		pts[i].Y = i * 2
	}
	var total int64 = 0
	for i := int64(0); i < n; i++ {
		total += pts[i].X + pts[i].Y
	}
	fmt.Println(total)
	var expected int64 = 5999997000000
	if total == expected {
		fmt.Println("CHECKSUM OK")
		os.Exit(0)
	} else {
		fmt.Println("CHECKSUM MISMATCH")
		os.Exit(1)
	}
}
