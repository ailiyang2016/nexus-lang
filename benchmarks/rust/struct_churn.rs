#[derive(Clone, Copy)]
struct Point { x: i64, y: i64 }
fn main(){ let n: i64 = 2_000_000; let mut pts: Vec<Point> = Vec::with_capacity(n as usize);
    for i in 0..n { pts.push(Point{ x: i, y: i*2 }); }
    let mut total: i64 = 0; for p in &pts { total += p.x + p.y; }
    println!("{}", total); }