#include <cstdio>
#include <vector>
int main(){ long long n=5000000; std::vector<long long> flags(n,1);
  for(long long p=2;p*p<n;p++) if(flags[p]==1) for(long long j=p*p;j<n;j+=p) flags[j]=0;
  long long count=0; for(long long k=2;k<n;k++) count+=flags[k];
  printf("%lld\n",count); return 0; }