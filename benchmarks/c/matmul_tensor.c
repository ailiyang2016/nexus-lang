#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(void) {
    int64_t n = 384, sz = n * n;
    int64_t* a = malloc((size_t)sz * sizeof(int64_t));
    int64_t* b = malloc((size_t)sz * sizeof(int64_t));
    int64_t* c = calloc((size_t)sz, sizeof(int64_t));
    for (int64_t i = 0; i < n; i++)
        for (int64_t j = 0; j < n; j++) {
            a[i * n + j] = (i * 7 + j * 3 + 3) % 13;
            b[i * n + j] = (i * 5 + j + 1) % 11;
        }
    for (int64_t r = 0; r < n; r++)
        for (int64_t col = 0; col < n; col++) {
            int64_t acc = 0;
            for (int64_t k = 0; k < n; k++) acc += a[r * n + k] * b[k * n + col];
            c[r * n + col] = acc;
        }
    int64_t total = 0;
    for (int64_t t = 0; t < sz; t++) total += c[t];
    printf("%lld\n", (long long)total);
    free(a); free(b); free(c);
    return 0;
}