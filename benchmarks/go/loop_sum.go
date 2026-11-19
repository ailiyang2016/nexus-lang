package main

import (
	"fmt"
	"os"
)

func main() {
	var s int64 = 0
	for i := int64(0); i < 1000000000; i++ {
		s += i
	}
	fmt.Println(s)
	var expected int64 = 499999999500000000
	if s == expected {
		fmt.Println("CHECKSUM OK")
		os.Exit(0)
	} else {
		fmt.Println("CHECKSUM MISMATCH")
		os.Exit(1)
	}
}
