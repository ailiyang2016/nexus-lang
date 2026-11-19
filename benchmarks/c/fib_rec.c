#include <stdio.h>
#include <stdint.h>

static int32_t fib(int32_t n) {
    if (n <= 1) return n;
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    printf("%d\n", fib(40));
    return 0;
}