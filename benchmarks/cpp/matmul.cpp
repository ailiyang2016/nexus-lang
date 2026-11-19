#include <cstdio>
#include <vector>
int main(){ const long long n=384, sz=n*n;
  std::vector<double> a(sz), b(sz), c(sz,0.0);
  for(long long i=0;i<sz;i++){ a[i]=double((i*7+3)%13); b[i]=double((i*5+1)%11); }
  for(long long r=0;r<n;r++) for(long long col=0;col<n;col++){ double acc=0; for(long long k=0;k<n;k++) acc+=a[r*n+k]*b[k*n+col]; c[r*n+col]=acc; }
  double total=0; for(long long t=0;t<sz;t++) total+=c[t];
  printf("%lld\n",(long long)total); return 0; }