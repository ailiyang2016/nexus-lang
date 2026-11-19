#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct { int64_t x, y; } Point;

int main(void) {
    int64_t n = 2000000;
    Point* pts = malloc((size_t)n * sizeof(Point));
    for (int64_t i = 0; i < n; i++) { pts[i].x = i; pts[i].y = i * 2; }
    int64_t total = 0;
    for (int64_t i = 0; i < n; i++) total += pts[i].x + pts[i].y;
    printf("%lld\n", (long long)total);
    free(pts);
    return 0;
}