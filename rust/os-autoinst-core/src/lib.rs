use pyo3::prelude::*;

#[pymodule]
fn os_autoinst_core(m: &Bound<'_, PyModule>) -> PyResult<()> {
    m.add("__version__", env!("CARGO_PKG_VERSION"))?;
    Ok(())
}
