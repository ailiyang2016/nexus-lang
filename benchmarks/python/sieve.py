import sys


def main():
    n = 5000000
    flags = [1] * n
    p = 2
    while p * p < n:
        if flags[p] == 1:
            j = p * p
            while j < n:
                flags[j] = 0
                j += p
        p += 1
    count = 0
    for k in range(2, n):
        count += flags[k]
    print(count)
    expected = 348513
    if count == expected:
        print("CHECKSUM OK")
        sys.exit(0)
    else:
        print("CHECKSUM MISMATCH")
        sys.exit(1)


if __name__ == "__main__":
    main()
