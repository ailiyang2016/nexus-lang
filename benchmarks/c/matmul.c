#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(void) {
    int64_t n = 384, sz = n * n;
    double* a = malloc((size_t)sz * sizeof(double));
    double* b = malloc((size_t)sz * sizeof(double));
    double* c = malloc((size_t)sz * sizeof(double));
    for (int64_t i = 0; i < sz; i++) {
        a[i] = (double)((i * 7 + 3) % 13);
        b[i] = (double)((i * 5 + 1) % 11);
        c[i] = 0.0;
    }
    for (int64_t r = 0; r < n; r++) {
        for (int64_t col = 0; col < n; col++) {
            double acc = 0.0;
            for (int64_t k = 0; k < n; k++) acc += a[r * n + k] * b[k * n + col];
            c[r * n + col] = acc;
        }
    }
    double total = 0.0;
    for (int64_t t = 0; t < sz; t++) total += c[t];
    printf("%lld\n", (long long)total);
    free(a); free(b); free(c);
    return 0;
}