use hound;
use image::{ImageBuffer, Luma};
use rustfft::{num_complex::Complex, FftPlanner};
use std::env;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: snd2png soundfile imagefile");
        std::process::exit(1);
    }

    let input_file = &args[1];
    let output_file = &args[2];

    let mut reader = match hound::WavReader::open(input_file) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Unable to open input file \"{}\": {}", input_file, e);
            std::process::exit(1);
        }
    };

    let spec = reader.spec();
    let samplerate = spec.sample_rate;
    let channels = spec.channels as usize;
    let num_frames = reader.len() as usize;

    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => reader.samples::<f32>().map(|s| s.unwrap_or(0.0)).collect(),
        hound::SampleFormat::Int => reader
            .samples::<i16>()
            .map(|s| s.unwrap_or(0) as f32 / 32768.0)
            .collect(),
    };

    let mut mono_samples = Vec::with_capacity(num_frames);
    for chunk in samples.chunks(channels) {
        let avg = chunk.iter().sum::<f32>() / channels as f32;
        mono_samples.push(avg);
    }

    let window_size = (samplerate / 100) as usize; // 10ms
    let overlap = window_size / 2;
    let dft_samples = window_size + overlap * 2;

    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(dft_samples);

    let times = num_frames / window_size - 1;
    let times = if times * window_size + overlap > num_frames {
        times - 1
    } else {
        times
    };

    let max_freq = 3200.0;
    let fft_max_freq = samplerate as f64 / 2.0;
    let num_bins = dft_samples / 2 + 1;
    let last_bin = (1.0 + (max_freq / fft_max_freq * (dft_samples as f64 / 2.0)).ceil()) as usize;
    let last_bin = last_bin.min(num_bins);
    let fft_bw = fft_max_freq / (dft_samples as f64 / 2.0);

    let mut points: Vec<Vec<f64>> = Vec::with_capacity(times);
    let mut global_max_value = 0.0;

    for t in 0..times {
        let mut buffer: Vec<Complex<f32>> = Vec::with_capacity(dft_samples);
        let start = t * window_size;
        for i in 0..dft_samples {
            if start + i < mono_samples.len() {
                buffer.push(Complex::new(mono_samples[start + i], 0.0));
            } else {
                buffer.push(Complex::new(0.0, 0.0));
            }
        }

        fft.process(&mut buffer);

        let mut row = Vec::with_capacity(last_bin);
        for i in 0..last_bin {
            let val = buffer[i].norm() as f64;
            row.push(val);
            if val > global_max_value {
                global_max_value = val;
            }
        }
        points.push(row);
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

    let scale_factor = 3;
    let height = 768;
    let freqs = height / scale_factor;
    let width = 1024;

    let mut img: ImageBuffer<Luma<u8>, Vec<u8>> =
        ImageBuffer::from_pixel(width, height, Luma([255]));

    if (last_non_silence as i32 - first_non_silence as i32) > width as i32 {
        last_non_silence = first_non_silence + width as usize;
    }

    for i in 1..freqs {
        let freq = i as f64 * max_freq / freqs as f64;
        let bin_f = freq / fft_bw;
        let bin = bin_f.ceil() as usize;
        let ratio = bin as f64 - bin_f;

        for t in first_non_silence..last_non_silence {
            if t >= points.len() {
                break;
            }
            let row = &points[t];
            let value = if bin == 0 {
                row[0]
            } else if bin < row.len() {
                ratio * row[bin - 1] + (1.0 - ratio) * row[bin]
            } else {
                row[row.len() - 1]
            };

            let scaled = (255.0 - (255.0 * value / global_max_value)) as u8;
            let x = (t - first_non_silence) as u32;
            if x < width {
                for j in 0..scale_factor {
                    let y = height as u32 - 1 - (i as u32 * scale_factor as u32) + j as u32;
                    if y < height as u32 {
                        img.put_pixel(x, y, Luma([scaled]));
                    }
                }
            }
        }
    }

    if let Err(e) = img.save(output_file) {
        eprintln!("Failed to save image {}: {}", output_file, e);
        std::process::exit(1);
    }
}
