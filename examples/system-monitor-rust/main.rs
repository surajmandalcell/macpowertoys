use std::env;
use std::process::Command;

fn main() {
    if env::args().nth(1).as_deref() != Some("--macpowertoys-monitor-sample") {
        eprintln!("Run this app from MacPowerToys System Monitor > Plugins.");
        std::process::exit(2);
    }

    let output = Command::new("/usr/sbin/sysctl")
        .args(["-n", "hw.memsize"])
        .output()
        .expect("sysctl did not start");
    if !output.status.success() {
        eprintln!("sysctl failed");
        std::process::exit(1);
    }
    let bytes: u64 = String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse()
        .expect("hw.memsize was not a number");
    let gib = bytes as f64 / 1_073_741_824.0;
    println!(
        "{{\"formatVersion\":1,\"values\":{{\"physical-memory\":{{\"value\":\"{gib:.1} GiB\",\"detail\":\"Installed RAM\"}}}}}}"
    );
}
