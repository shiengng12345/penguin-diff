//! Development-only probe for trusted synthetic differential tests.
//! The shipped App uses the C ABI; this executable is never bundled.
use std::io::{self, BufRead};

fn main() {
    for line in io::stdin().lock().lines() {
        match line {
            Ok(request) => println!("{}", compare_core::process(&request)),
            Err(_) => std::process::exit(1),
        }
    }
}
