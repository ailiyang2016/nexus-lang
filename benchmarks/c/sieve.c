#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

int main(void) {
    int64_t n = 5000000;
    int64_t* flags = malloc((size_t)n * sizeof(int64_t));
    for (int64_t i = 0; i < n; i++) flags[i] = 1;
    for (int64_t p = 2; p * p < n; p++) {
        if (flags[p] == 1) {
            for (int64_t j = p * p; j < n; j += p) flags[j] = 0;
        }
    }
    int64_t count = 0;
    for (int64_t k = 2; k < n; k++) count += flags[k];
    printf("%lld\n", (long long)count);
    free(flags);
    return 0;
}