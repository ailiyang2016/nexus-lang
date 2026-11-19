import sys


def main():
    s = 0
    for i in range(1000000000):
        s += i
    print(s)
    expected = 499999999500000000
    if s == expected:
        print("CHECKSUM OK")
        sys.exit(0)
    else:
        print("CHECKSUM MISMATCH")
        sys.exit(1)


if __name__ == "__main__":
    main()
