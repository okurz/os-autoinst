use image::GenericImageView;
use std::fs;
use std::io::{self, BufRead, Read, Write};
use std::os::unix::fs::symlink;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    let mut output_video = true;
    let mut output_file = String::new();

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-n" => output_video = false,
            "-x" | "-y" => {
                i += 1;
            }
            _ => {
                if output_file.is_empty() && !args[i].starts_with('-') {
                    output_file = args[i].clone();
                }
            }
        }
        i += 1;
    }

    let mut ffmpeg = if output_video && !output_file.is_empty() {
        Some(
            Command::new("ffmpeg")
                .args(&[
                    "-f",
                    "image2pipe",
                    "-vcodec",
                    "ppm",
                    "-r",
                    "24",
                    "-i",
                    "-",
                    "-vcodec",
                    "libtheora",
                    "-q:v",
                    "6",
                    "-y",
                    &output_file,
                ])
                .stdin(Stdio::piped())
                .stderr(Stdio::null())
                .spawn()?,
        )
    } else {
        None
    };

    let stdin = io::stdin();
    let mut stdin_lock = stdin.lock();
    let mut line = String::new();
    let mut last_frame_ppm: Vec<u8> = Vec::new();

    while stdin_lock.read_line(&mut line)? > 0 {
        let cmd = line.trim_end();
        if cmd.starts_with("E ") {
            if let Ok(len) = cmd[2..].parse::<usize>() {
                let mut buf = vec![0u8; len];
                stdin_lock.read_exact(&mut buf)?;

                if let Ok(img) = image::load_from_memory(&buf) {
                    let (w, h) = img.dimensions();
                    let mut ppm_buf = Vec::new();
                    write!(ppm_buf, "P6\n{} {}\n255\n", w, h)?;
                    ppm_buf.extend_from_slice(&img.to_rgb8());

                    if let Some(ref mut child) = ffmpeg {
                        if let Some(ref mut child_stdin) = child.stdin {
                            let _ = child_stdin.write_all(&ppm_buf);
                        }
                    }

                    if Path::new("live_log").exists() {
                        let now = SystemTime::now().duration_since(UNIX_EPOCH)?;
                        let path = format!(
                            "qemuscreenshot/{}.{}.png",
                            now.as_secs(),
                            now.subsec_micros()
                        );
                        let _ = fs::create_dir_all("qemuscreenshot");
                        let _ = img.save(&path);
                        let _ = fs::remove_file("qemuscreenshot/last.png");
                        if let Some(fname) = Path::new(&path).file_name() {
                            let _ = symlink(fname, "qemuscreenshot/last.png");
                        }
                    }
                    last_frame_ppm = ppm_buf;
                }
            }
        } else if cmd == "R" {
            if !last_frame_ppm.is_empty() {
                if let Some(ref mut child) = ffmpeg {
                    if let Some(ref mut child_stdin) = child.stdin {
                        let _ = child_stdin.write_all(&last_frame_ppm);
                    }
                }
            }
        }
        line.clear();
    }

    if let Some(mut child) = ffmpeg {
        drop(child.stdin.take());
        let _ = child.wait();
    }

    Ok(())
}
