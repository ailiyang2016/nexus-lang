fn mandel(cx: f64, cy: f64, max_iter: i32) -> i32 {
    let mut x = 0.0f64; let mut y = 0.0f64; let mut i = 0;
    while i < max_iter { let x2 = x*x; let y2 = y*y; if x2+y2 > 4.0 { return i; } let xt = x2-y2+cx; y = 2.0*x*y+cy; x = xt; i += 1; }
    max_iter
}
fn main() { let n = 600; let mut total: i64 = 0;
    for py in 0..n { for px in 0..n { let cx = px as f64/n as f64*3.0-2.0; let cy = py as f64/n as f64*2.0-1.0; total += mandel(cx,cy,100) as i64; } }
    println!("{}", total); }