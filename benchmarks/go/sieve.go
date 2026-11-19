package main

import (
	"fmt"
	"os"
)

func main() {
	var n int64 = 5000000
	flags := make([]int64, n)
	for i := int64(0); i < n; i++ {
		flags[i] = 1
	}
	for p := int64(2); p*p < n; p++ {
		if flags[p] == 1 {
			for j := p * p; j < n; j += p {
				flags[j] = 0
			}
		}
	}
	var count int64 = 0
	for k := int64(2); k < n; k++ {
		count += flags[k]
	}
	fmt.Println(count)
	var expected int64 = 348513
	if count == expected {
		fmt.Println("CHECKSUM OK")
		os.Exit(0)
	} else {
		fmt.Println("CHECKSUM MISMATCH")
		os.Exit(1)
	}
}
