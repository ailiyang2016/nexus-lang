#include <stdio.h>
#include <stdint.h>

static int32_t mandel(double cx, double cy, int32_t max_iter) {
    double x = 0.0, y = 0.0;
    int32_t i = 0;
    while (i < max_iter) {
        double x2 = x * x, y2 = y * y;
        if (x2 + y2 > 4.0) return i;
        double xt = x2 - y2 + cx;
        y = 2.0 * x * y + cy;
        x = xt;
        i++;
    }
    return max_iter;
}

int main(void) {
    int32_t n = 600;
    int64_t total = 0;
    for (int32_t py = 0; py < n; py++) {
        for (int32_t px = 0; px < n; px++) {
            double cx = (double)px / (double)n * 3.0 - 2.0;
            double cy = (double)py / (double)n * 2.0 - 1.0;
            total += (int64_t)mandel(cx, cy, 100);
        }
    }
    printf("%lld\n", (long long)total);
    return 0;
}