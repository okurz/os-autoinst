use image::{imageops, DynamicImage, GenericImage, ImageFormat};
use imageproc::template_matching::{match_template, MatchTemplateMethod};
use pyo3::prelude::*;
use std::io::Cursor;

fn to_ppm_bytes(img: &DynamicImage) -> PyResult<Vec<u8>> {
    let mut buf = Vec::new();
    img.write_to(&mut Cursor::new(&mut buf), ImageFormat::Pnm)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
    Ok(buf)
}

/// Finds the best match of the `needle` area within the `screen` image (near the expected location).
/// Both inputs are expected to be raw encoded image bytes (like PNG/PPM).
/// Returns (similarity, x, y) to be compatible with os-autoinst expectations.
#[pyfunction]
fn match_needle(
    screen_data: &[u8],
    needle_data: &[u8],
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    margin: u32,
) -> PyResult<Option<(f32, u32, u32)>> {
    let screen_img = image::load_from_memory(screen_data)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
    let needle_img = image::load_from_memory(needle_data)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;

    // Scale the position if object and scene have different sizes
    let scaled_x = (x as f32 * screen_img.width() as f32 / needle_img.width() as f32) as i32;
    let scaled_y = (y as f32 * screen_img.height() as f32 / needle_img.height() as f32) as i32;

    // Define ROI in screen
    let scene_x = (scaled_x - margin as i32).max(0) as u32;
    let scene_y = (scaled_y - margin as i32).max(0) as u32;
    let scene_right =
        (scaled_x + width as i32 + margin as i32).min(screen_img.width() as i32) as u32;
    let scene_bottom =
        (scaled_y + height as i32 + margin as i32).min(screen_img.height() as i32) as u32;

    if scene_right <= scene_x || scene_bottom <= scene_y {
        return Ok(None);
    }

    let scene_width = scene_right - scene_x;
    let scene_height = scene_bottom - scene_y;

    if scene_width < width || scene_height < height {
        return Ok(None);
    }

    // Crop images
    let screen_roi = screen_img.crop_imm(scene_x, scene_y, scene_width, scene_height);
    let needle_roi = needle_img.crop_imm(x, y, width, height);

    // Convert to grayscale for matching
    let screen_gray = screen_roi.into_luma8();
    let needle_gray = needle_roi.into_luma8();

    // Perform template matching (Sum of Squared Errors)
    let result = match_template(
        &screen_gray,
        &needle_gray,
        MatchTemplateMethod::SumOfSquaredErrors,
    );

    // Find the minimum error (best match for SSE)
    let mut min_val = f32::MAX;
    let mut best_loc = (0, 0);

    for (res_x, res_y, pixel) in result.enumerate_pixels() {
        if pixel[0] < min_val {
            min_val = pixel[0];
            best_loc = (res_x, res_y);
        }
    }

    // Convert SSE to MSE
    let num_pixels = (width * height) as f32;
    let mse = min_val / num_pixels;

    // Similarity mapping from C++: similarity = .9 + (40 - mse) / 380;
    let mut similarity = 0.9 + (40.0 - mse) / 380.0;
    if similarity < 0.0 {
        similarity = 0.0;
    }
    if similarity > 1.0 {
        similarity = 1.0;
    }

    // Final coordinates in screen space
    let final_x = best_loc.0 + scene_x;
    let final_y = best_loc.1 + scene_y;

    Ok(Some((similarity, final_x, final_y)))
}

/// Crops a rectangle from the image and returns it as PPM bytes.
#[pyfunction]
fn copy_rect(data: &[u8], x: u32, y: u32, w: u32, h: u32) -> PyResult<Vec<u8>> {
    let img = image::load_from_memory(data)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
    let cropped = img.crop_imm(x, y, w, h);
    to_ppm_bytes(&cropped)
}

/// Fills a rectangle with a color and returns the resulting image as PPM bytes.
#[pyfunction]
fn replace_rect(
    data: &[u8],
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    r: u8,
    g: u8,
    b: u8,
) -> PyResult<Vec<u8>> {
    let mut img = image::load_from_memory(data)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;

    // Create a color pixel
    let color = image::Rgba([r, g, b, 255]);

    for iy in y..(y + h) {
        for ix in x..(x + w) {
            if ix < img.width() && iy < img.height() {
                img.put_pixel(ix, iy, color);
            }
        }
    }

    to_ppm_bytes(&img)
}

/// Scales the image to the target width and height and returns it as PPM bytes.
#[pyfunction]
fn scale(data: &[u8], w: u32, h: u32) -> PyResult<Vec<u8>> {
    let img = image::load_from_memory(data)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
    let scaled = img.resize_exact(w, h, imageops::FilterType::Lanczos3);
    to_ppm_bytes(&scaled)
}

/// Formats the sum of two numbers as string. Just a test function.
#[pyfunction]
fn sum_as_string(a: usize, b: usize) -> PyResult<String> {
    Ok((a + b).to_string())
}

/// Saves the image data to a file.
#[pyfunction]
fn save_image(data: &[u8], path: &str) -> PyResult<()> {
    let img = image::load_from_memory(data)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
    img.save(path)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
    Ok(())
}

/// Reads an image from disk and returns it as PPM bytes.
#[pyfunction]
fn read_image(path: &str) -> PyResult<Vec<u8>> {
    let img = image::open(path)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
    to_ppm_bytes(&img)
}

/// Creates a new black image of given size and returns it as PPM bytes.
#[pyfunction]
fn new_image(w: u32, h: u32) -> PyResult<Vec<u8>> {
    let img = DynamicImage::ImageRgb8(image::ImageBuffer::new(w, h));
    to_ppm_bytes(&img)
}

/// A Python module implemented in Rust.
#[pymodule]
fn os_autoinst_core(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(match_needle, m)?)?;
    m.add_function(wrap_pyfunction!(sum_as_string, m)?)?;
    m.add_function(wrap_pyfunction!(save_image, m)?)?;
    m.add_function(wrap_pyfunction!(read_image, m)?)?;
    m.add_function(wrap_pyfunction!(new_image, m)?)?;
    m.add_function(wrap_pyfunction!(copy_rect, m)?)?;
    m.add_function(wrap_pyfunction!(replace_rect, m)?)?;
    m.add_function(wrap_pyfunction!(scale, m)?)?;
    Ok(())
}
