fn main() {
    let n: i64 = 384;
    let sz = (n * n) as usize;
    let mut a = vec![0i64; sz];
    let mut b = vec![0i64; sz];
    let mut c = vec![0i64; sz];
    for i in 0..n {
        for j in 0..n {
            a[(i * n + j) as usize] = (i * 7 + j * 3 + 3) % 13;
            b[(i * n + j) as usize] = (i * 5 + j + 1) % 11;
        }
    }
    for r in 0..n {
        for col in 0..n {
            let mut acc = 0i64;
            for k in 0..n {
                acc += a[(r * n + k) as usize] * b[(k * n + col) as usize];
            }
            c[(r * n + col) as usize] = acc;
        }
    }
    let total: i64 = c.iter().sum();
    println!("{}", total);
}