#include <cstdio>
#include <vector>
struct Point { long long x, y; };
int main(){ const long long n=2000000; std::vector<Point> pts; pts.reserve(n);
  for(long long i=0;i<n;i++) pts.push_back(Point{i, i*2});
  long long total=0; for(const auto& p: pts) total += p.x + p.y;
  printf("%lld\n", total); return 0; }