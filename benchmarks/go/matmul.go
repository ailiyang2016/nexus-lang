package main

import (
	"fmt"
	"os"
)

func main() {
	var n int64 = 384
	sz := n * n
	a := make([]float64, sz)
	b := make([]float64, sz)
	c := make([]float64, sz)
	for i := int64(0); i < sz; i++ {
		a[i] = float64((i*7+3)%13)
		b[i] = float64((i*5+1)%11)
		c[i] = 0.0
	}
	for r := int64(0); r < n; r++ {
		for col := int64(0); col < n; col++ {
			var acc float64 = 0.0
			for k := int64(0); k < n; k++ {
				acc += a[r*n+k] * b[k*n+col]
			}
			c[r*n+col] = acc
		}
	}
	var total float64 = 0.0
	for t := int64(0); t < sz; t++ {
		total += c[t]
	}
	fmt.Println(int64(total))
	var expected int64 = 1698681604
	if int64(total) == expected {
		fmt.Println("CHECKSUM OK")
		os.Exit(0)
	} else {
		fmt.Println("CHECKSUM MISMATCH")
		os.Exit(1)
	}
}
