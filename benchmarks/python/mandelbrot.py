import math
import sys


def mandel(cx, cy, max_iter):
    x, y = 0.0, 0.0
    i = 0
    while i < max_iter:
        x2 = x * x
        y2 = y * y
        if x2 + y2 > 4.0:
            return i
        xt = x2 - y2 + cx
        y = 2.0 * x * y + cy
        x = xt
        i += 1
    return max_iter


def main():
    n = 600
    total = 0
    for py in range(n):
        for px in range(n):
            cx = math.fma(px / n, 3.0, -2.0)
            cy = math.fma(py / n, 2.0, -1.0)
            total += mandel(cx, cy, 100)
    print(total)
    expected = 10922953
    if total == expected:
        print("CHECKSUM OK")
        sys.exit(0)
    else:
        print("CHECKSUM MISMATCH")
        sys.exit(1)


if __name__ == "__main__":
    main()
