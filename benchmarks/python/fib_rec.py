import sys


def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)


def main():
    got = fib(40)
    print(got)
    expected = 102334155
    if got == expected:
        print("CHECKSUM OK")
        sys.exit(0)
    else:
        print("CHECKSUM MISMATCH")
        sys.exit(1)


if __name__ == "__main__":
    main()
