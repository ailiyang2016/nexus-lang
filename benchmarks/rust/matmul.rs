fn main(){ let n: i64 = 384; let sz = (n*n) as usize;
    let mut a = vec![0f64; sz]; let mut b = vec![0f64; sz]; let mut c = vec![0f64; sz];
    for i in 0..sz { a[i] = ((i as i64*7+3)%13) as f64; b[i] = ((i as i64*5+1)%11) as f64; }
    for r in 0..n { for col in 0..n { let mut acc = 0f64; for k in 0..n { acc += a[(r*n+k) as usize]*b[(k*n+col) as usize]; } c[(r*n+col) as usize] = acc; } }
    let mut total = 0f64; for t in 0..sz { total += c[t]; }
    println!("{}", total as i64); }