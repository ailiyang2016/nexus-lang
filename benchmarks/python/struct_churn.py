import sys


class Point:
    __slots__ = ("x", "y")

    def __init__(self, x, y):
        self.x = x
        self.y = y


def main():
    n = 2000000
    pts = [None] * n
    for i in range(n):
        pts[i] = Point(i, i * 2)
    total = 0
    for i in range(n):
        total += pts[i].x + pts[i].y
    print(total)
    expected = 5999997000000
    if total == expected:
        print("CHECKSUM OK")
        sys.exit(0)
    else:
        print("CHECKSUM MISMATCH")
        sys.exit(1)


if __name__ == "__main__":
    main()
