fn main() { let n: i64 = 5_000_000; let mut flags = vec![1i64; n as usize];
    let mut p: i64 = 2; while p*p < n { if flags[p as usize] == 1 { let mut j = p*p; while j < n { flags[j as usize] = 0; j += p; } } p += 1; }
    let mut count: i64 = 0; let mut k: i64 = 2; while k < n { count += flags[k as usize]; k += 1; }
    println!("{}", count); }