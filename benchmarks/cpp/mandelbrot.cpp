#include <cstdio>
static int mandel(double cx, double cy, int max_iter){
  double x=0,y=0; int i=0;
  while(i<max_iter){ double x2=x*x,y2=y*y; if(x2+y2>4.0) return i; double xt=x2-y2+cx; y=2.0*x*y+cy; x=xt; i++; }
  return max_iter;
}
int main(){ int n=600; long long total=0;
  for(int py=0;py<n;py++) for(int px=0;px<n;px++){ double cx=(double)px/n*3.0-2.0, cy=(double)py/n*2.0-1.0; total+=mandel(cx,cy,100); }
  printf("%lld\n",total); return 0; }