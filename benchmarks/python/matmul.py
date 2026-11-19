import sys


def main():
    n = 384
    sz = n * n
    a = [float((i * 7 + 3) % 13) for i in range(sz)]
    b = [float((i * 5 + 1) % 11) for i in range(sz)]
    c = [0.0] * sz
    for r in range(n):
        for col in range(n):
            acc = 0.0
            for k in range(n):
                acc += a[r * n + k] * b[k * n + col]
            c[r * n + col] = acc
    total = 0.0
    for t in range(sz):
        total += c[t]
    print(int(total))
    expected = 1698681604
    if int(total) == expected:
        print("CHECKSUM OK")
        sys.exit(0)
    else:
        print("CHECKSUM MISMATCH")
        sys.exit(1)


if __name__ == "__main__":
    main()
