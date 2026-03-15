use pyo3::prelude::*;

/// A dummy needle matching function for the Rust core migration.
#[pyfunction]
fn match_needle(screen_data: &[u8], needle_data: &[u8]) -> PyResult<bool> {
    // For now, just return true if both are non-empty.
    // This is a placeholder for the actual OpenCV/C++ logic.
    Ok(!screen_data.is_empty() && !needle_data.is_empty())
}

/// Formats the sum of two numbers as string. Just a test function.
#[pyfunction]
fn sum_as_string(a: usize, b: usize) -> PyResult<String> {
    Ok((a + b).to_string())
}

/// A Python module implemented in Rust. The name of this function must match
/// the `lib.name` setting in the `Cargo.toml`, else Python will not be able to
/// import the module.
#[pymodule]
fn os_autoinst_core(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add_function(wrap_pyfunction!(match_needle, m)?)?;
    m.add_function(wrap_pyfunction!(sum_as_string, m)?)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_match_needle_empty() {
        let screen = vec![];
        let needle = vec![];
        assert_eq!(match_needle(&screen, &needle).unwrap(), false);
    }
}
