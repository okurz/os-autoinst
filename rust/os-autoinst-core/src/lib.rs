use image::{DynamicImage, GenericImageView, ImageBuffer, Luma, RgbaImage};
use imageproc::template_matching::{match_template, MatchTemplateMethod};
use pyo3::prelude::*;

/// Finds the best match of the `needle` image within the `screen` image.
/// Both inputs are expected to be raw RGB/RGBA image bytes, but for simplicity
/// here we can assume they are encoded image bytes (like PNG/PPM) if using `load_from_memory`.
/// Let's accept encoded image bytes (PNG/PPM/etc) for now.
#[pyfunction]
fn match_needle(screen_data: &[u8], needle_data: &[u8]) -> PyResult<Option<(u32, u32, f32)>> {
    let screen_img = image::load_from_memory(screen_data)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
    let needle_img = image::load_from_memory(needle_data)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;

    // Convert to grayscale for matching
    let screen_gray = screen_img.into_luma8();
    let needle_gray = needle_img.into_luma8();

    if screen_gray.width() < needle_gray.width() || screen_gray.height() < needle_gray.height() {
        return Ok(None); // Needle is larger than screen
    }

    // Perform template matching (Sum of Squared Errors)
    let result = match_template(
        &screen_gray,
        &needle_gray,
        MatchTemplateMethod::SumOfSquaredErrors,
    );

    // Find the minimum error (best match for SSE)
    let mut min_val = f32::MAX;
    let mut best_loc = (0, 0);

    for (x, y, pixel) in result.enumerate_pixels() {
        if pixel[0] < min_val {
            min_val = pixel[0];
            best_loc = (x, y);
        }
    }

    // A similarity score could be derived from min_val, but we just return it for now.
    Ok(Some((best_loc.0, best_loc.1, min_val)))
}

/// Formats the sum of two numbers as string. Just a test function.
#[pyfunction]
fn sum_as_string(a: usize, b: usize) -> PyResult<String> {
    Ok((a + b).to_string())
}

/// A Python module implemented in Rust.
#[pymodule]
fn os_autoinst_core(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(match_needle, m)?)?;
    m.add_function(wrap_pyfunction!(sum_as_string, m)?)?;
    Ok(())
}
