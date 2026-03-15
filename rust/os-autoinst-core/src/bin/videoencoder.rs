use chrono::Local;
use std::fs;
use std::io::{self, BufRead, Read, Write};
use std::os::unix::fs::symlink;
use std::path::Path;
use std::process::{Child, Command, Stdio};

fn main() -> io::Result<()> {
    let mut output_video = true;
    let mut _xres = 1024;
    let mut _yres = 768;
    let mut output_path = String::new();

    let args: Vec<String> = std::env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-n" => output_video = false,
            "-x" => {
                i += 1;
                if i < args.len() {
                    _xres = args[i].parse().unwrap_or(1024);
                }
            }
            "-y" => {
                i += 1;
                if i < args.len() {
                    _yres = args[i].parse().unwrap_or(768);
                }
            }
            path => output_path = path.to_string(),
        }
        i += 1;
    }

    if output_path.is_empty() && output_video {
        eprintln!("Usage: videoencoder [-n] [-x width] [-y height] OUTPUT");
        std::process::exit(1);
    }

    let mut ffmpeg: Option<Child> = if output_video {
        let child = Command::new("ffmpeg")
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
                &output_path,
            ])
            .stdin(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| {
                io::Error::new(
                    io::ErrorKind::Other,
                    format!("Failed to start ffmpeg: {}", e),
                )
            })?;
        Some(child)
    } else {
        None
    };

    let stdin = io::stdin();
    let mut stdin_lock = stdin.lock();
    let mut last_frame: Vec<u8> = Vec::new();

    let mut line = String::new();
    while stdin_lock.read_line(&mut line)? > 0 {
        let cmd = line.trim();
        if cmd.starts_with('E') {
            let parts: Vec<&str> = cmd.split_whitespace().collect();
            if parts.len() < 2 {
                continue;
            }
            let len: usize = parts[1].parse().unwrap_or(0);
            let mut buf = vec![0u8; len];
            stdin_lock.read_exact(&mut buf)?;

            if let Some(ref mut child) = ffmpeg {
                if let Some(ref mut child_stdin) = child.stdin {
                    let _ = child_stdin.write_all(&buf);
                }
            }

            last_frame = buf;

            // Live log PNG
            if Path::new("live_log").exists() {
                let _ = save_live_log(&last_frame);
            }
        } else if cmd == "R" {
            if let Some(ref mut child) = ffmpeg {
                if let Some(ref mut child_stdin) = child.stdin {
                    if !last_frame.is_empty() {
                        let _ = child_stdin.write_all(&last_frame);
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

fn save_live_log(ppm_data: &[u8]) -> io::Result<()> {
    let now = Local::now();
    let timestamp = now.format("%s.%f").to_string();
    let path_str = format!("qemuscreenshot/{}.png", timestamp);
    let path = Path::new(&path_str);

    if let Ok(img) = image::load_from_memory(ppm_data) {
        let _ = fs::create_dir_all("qemuscreenshot");
        img.save(path)
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;
        let last_png = Path::new("qemuscreenshot/last.png");
        if last_png.exists() {
            let _ = fs::remove_file(last_png);
        }
        let _ = symlink(path.file_name().unwrap(), last_png);
    }
    Ok(())
}
