use anyhow::Context;
use hound::WavReader;
use image::{GrayImage, Luma};
use rustfft::num_complex::Complex;
use rustfft::FftPlanner;
use std::env;

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        anyhow::bail!("Usage: snd2png soundfile imagefile");
    }

    let input_path = &args[1];
    let output_path = &args[2];

    let mut reader = WavReader::open(input_path).context("Failed to open WAV file")?;
    let spec = reader.spec();
    let samplerate = spec.sample_rate;
    let channels = spec.channels as usize;

    let mut all_samples: Vec<f32> = Vec::new();
    match spec.sample_format {
        hound::SampleFormat::Int => match spec.bits_per_sample {
            16 => {
                for s in reader.samples::<i16>() {
                    all_samples.push(s.unwrap_or(0) as f32 / 32768.0);
                }
            }
            24 => {
                for s in reader.samples::<i32>() {
                    all_samples.push(s.unwrap_or(0) as f32 / 8388608.0);
                }
            }
            32 => {
                for s in reader.samples::<i32>() {
                    all_samples.push(s.unwrap_or(0) as f32 / 2147483648.0);
                }
            }
            _ => anyhow::bail!("Unsupported bit depth: {}", spec.bits_per_sample),
        },
        hound::SampleFormat::Float => {
            for s in reader.samples::<f32>() {
                all_samples.push(s.unwrap_or(0.0));
            }
        }
    }

    let mut data: Vec<f32> = Vec::new();
    if channels == 1 {
        data = all_samples;
    } else {
        for chunk in all_samples.chunks(channels) {
            let avg = chunk.iter().sum::<f32>() / channels as f32;
            data.push(avg);
        }
    }

    // 10ms per chunk
    let window_size = (samplerate / 100) as usize;
    let overlap = window_size / 2;
    let n_dft_samples = window_size + overlap * 2;

    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(n_dft_samples);

    let times = if data.len() > n_dft_samples {
        (data.len() - n_dft_samples) / window_size
    } else {
        0
    };
    if times == 0 {
        anyhow::bail!("Audio too short");
    }

    let max_freq = 3200.0;
    let fft_max_freq = samplerate as f64 / 2.0;
    let last_bin = (((max_freq / fft_max_freq * (n_dft_samples as f64 / 2.0)).ceil() as usize + 1)
        .min(n_dft_samples / 2 + 1))
    .max(1);
    let fft_bw = fft_max_freq / (n_dft_samples as f64 / 2.0);

    let mut points = vec![vec![0.0f64; last_bin]; times];
    let mut global_max_value = 0.0f64;

    for t in 0..times {
        let start = t * window_size;
        let mut buffer: Vec<Complex<f64>> = vec![Complex::default(); n_dft_samples];
        for i in 0..n_dft_samples {
            if start + i < data.len() {
                buffer[i] = Complex::new(data[start + i] as f64, 0.0);
            }
        }

        fft.process(&mut buffer);

        for i in 0..last_bin {
            let val = buffer[i].norm();
            points[t][i] = val;
            if val > global_max_value {
                global_max_value = val;
            }
        }
    }

    if global_max_value == 0.0 {
        global_max_value = 1.0;
    }

    let mut first_non_silence = 0;
    while first_non_silence < times {
        let max_in_row = points[first_non_silence]
            .iter()
            .cloned()
            .fold(0.0, f64::max);
        if max_in_row > global_max_value * 0.1 {
            break;
        }
        first_non_silence += 1;
    }

    let mut last_non_silence = times.saturating_sub(1);
    while last_non_silence > first_non_silence {
        let max_in_row = points[last_non_silence].iter().cloned().fold(0.0, f64::max);
        if max_in_row > global_max_value * 0.1 {
            break;
        }
        last_non_silence -= 1;
    }

    let height = 768;
    let width = 1024;
    let scale_factor = 3;
    let freqs = height / scale_factor;

    let mut img = GrayImage::new(width, height);
    for p in img.pixels_mut() {
        *p = Luma([255]);
    }

    let display_len = (last_non_silence - first_non_silence).min(width as usize);

    for i in 1..freqs {
        let freq = i as f64 * max_freq / freqs as f64;
        let bin_f = freq / fft_bw;
        let bin = bin_f.ceil() as usize;
        let ratio = bin as f64 - bin_f;

        for t_off in 0..display_len {
            let t = first_non_silence + t_off;
            let val = if bin == 0 {
                points[t][0]
            } else if bin < last_bin {
                ratio * points[t][bin - 1] + (1.0 - ratio) * points[t][bin]
            } else {
                points[t][last_bin - 1]
            };

            let scaled = 255 - (255.0 * val / global_max_value).min(255.0) as u8;
            for j in 0..scale_factor {
                let y = height - 1 - i * scale_factor + j;
                if y < height {
                    img.put_pixel(t_off as u32, y as u32, Luma([scaled]));
                }
            }
        }
    }

    img.save(output_path)?;

    Ok(())
}
