package main

import (
	"fmt"
	"os"
)

func fib(n int32) int32 {
	if n <= 1 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func main() {
	got := fib(40)
	fmt.Println(got)
	expected := int32(102334155)
	if got == expected {
		fmt.Println("CHECKSUM OK")
		os.Exit(0)
	} else {
		fmt.Println("CHECKSUM MISMATCH")
		os.Exit(1)
	}
}
