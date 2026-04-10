# Dual-Input CLI Design

## Goal

Allow the pipeline scripts to accept either a user-authored YAML config or a farm polygon path directly, while preserving a reproducible config artifact for every run and keeping the Earth Engine bridge compatible with older `reticulate` releases.

## Decisions

- The public CLI accepts one positional argument in each script.
- If the argument ends in `.yml` or `.yaml`, the existing config-driven workflow is used.
- Otherwise, the argument is treated as a farm polygon path and a config is generated from repository defaults plus the resolved shapefile path.
- Auto-generated configs are written into the run output directory so users can inspect and reuse the exact configuration that ran.
- A dedicated `scripts/build_config.R` entrypoint is added for users who want to materialize a config without running the full pipeline.
- The Google Earth Engine bridge uses `reticulate::py_require()` when available, and falls back to `reticulate::py_install()` for older `reticulate` versions.

## Data Flow

1. Script receives a single input path.
2. Input resolver classifies it as YAML config or farm polygon.
3. YAML input is loaded and validated as before.
4. Farm polygon input is converted into a config by combining `default_config()` with:
   - `farm_path` set to the resolved polygon path
   - `output_dir` set to `outputs/<farm_name>`
   - `run_name` inferred from the polygon basename
5. The resolved config is normalized, validated, and written to `reports/auto_config.yml`.
6. Downstream pipeline stages continue to consume only the resolved config object.

## Testing

- Config tests cover both YAML input and polygon input.
- Auto-generated config persistence is verified.
- The reticulate compatibility helper is tested at the branch-selection level so no live Python package installation is required in unit tests.

## Documentation

- README moves configuration guidance earlier in the document.
- Usage examples lead with `Rscript scripts/<script>.R <farm.shp>`.
- YAML config usage remains documented as the reproducible advanced mode.
