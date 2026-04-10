# Soil Sampling Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable `soilsampling` repository that prepares a GEE-first covariate stack from a user-provided farm polygon and generates PCA plus k-means soil sample designs.

**Architecture:** Keep the repository R-first with focused modules under `R/`, thin CLI entrypoints under `scripts/`, tests under `tests/testthat/`, and a Python Earth Engine downloader under `python/`. Separate concerns into config parsing, spatial I/O, covariate preparation, stack processing, PCA sampling, and output writing so the core logic is testable without live Earth Engine access.

**Tech Stack:** R, testthat, yaml, jsonlite, terra, sf-compatible vector handling via terra, Python Earth Engine helper, YAML config files

---

### Task 1: Bootstrap Repository Layout And Config Loading

**Files:**
- Create: `DESCRIPTION`
- Create: `.Rprofile`
- Create: `README.md`
- Create: `tests/testthat.R`
- Create: `tests/testthat/helper-load.R`
- Create: `tests/testthat/test-config.R`
- Create: `R/config.R`
- Create: `config/example_nowley.yml`
- Create: `inst/example/nowley/Nowley.shp`
- Create: `inst/example/nowley/Nowley.shx`
- Create: `inst/example/nowley/Nowley.dbf`
- Create: `inst/example/nowley/Nowley.prj`
- Create: `inst/example/nowley/Nowley.cpg`
- Modify: `docs/superpowers/specs/2026-04-10-soil-sampling-pipeline-design.md`

- [ ] **Step 1: Write the failing config tests**

```r
test_that("load_config merges defaults with YAML overrides", {
  cfg <- load_config("config/example_nowley.yml")

  expect_equal(basename(cfg$farm_path), "Nowley.shp")
  expect_equal(cfg$sample_count, 9L)
  expect_equal(cfg$cluster_count, 3L)
  expect_true(cfg$sentinel1$enabled)
  expect_true(dir.exists(cfg$output_dir))
})

test_that("validate_config rejects impossible sampling settings", {
  cfg <- list(
    farm_path = "inst/example/nowley/Nowley.shp",
    output_dir = "outputs/example",
    gee_project_id = "demo-project",
    sample_count = 2L,
    cluster_count = 3L,
    buffer_distance_m = 30,
    min_point_spacing_m = 20,
    random_seed = 42L,
    pca = list(variance_threshold = 0.9, max_components = 6L),
    sentinel1 = list(enabled = TRUE)
  )

  expect_error(validate_config(cfg), "sample_count")
})
```

- [ ] **Step 2: Run the config tests to verify they fail**

Run: `Rscript tests/testthat.R`
Expected: FAIL with missing `load_config()` and `validate_config()`

- [ ] **Step 3: Write the minimal repository bootstrap and config implementation**

```r
default_config <- function() {
  list(
    output_dir = file.path("outputs", "nowley"),
    sample_count = 9L,
    cluster_count = 3L,
    buffer_distance_m = 30,
    min_point_spacing_m = 20,
    random_seed = 42L,
    gee_project_id = Sys.getenv("GEE_PROJECT_ID", unset = ""),
    date_window = list(start = "2024-01-01", end = "2024-12-31"),
    pca = list(variance_threshold = 0.9, max_components = 6L),
    sentinel1 = list(enabled = TRUE)
  )
}

load_config <- function(path) {
  cfg <- modify_list(default_config(), yaml::read_yaml(path))
  cfg$farm_path <- normalizePath(cfg$farm_path, winslash = "/", mustWork = FALSE)
  cfg$output_dir <- normalizePath(cfg$output_dir, winslash = "/", mustWork = FALSE)
  validate_config(cfg)
}

validate_config <- function(cfg) {
  if (!isTRUE(cfg$sample_count >= cfg$cluster_count)) {
    stop("sample_count must be greater than or equal to cluster_count.", call. = FALSE)
  }
  cfg
}
```

- [ ] **Step 4: Run the config tests to verify they pass**

Run: `Rscript tests/testthat.R`
Expected: PASS for `test-config.R`

- [ ] **Step 5: Commit**

```bash
git add DESCRIPTION .Rprofile README.md tests/testthat.R tests/testthat/helper-load.R tests/testthat/test-config.R R/config.R config/example_nowley.yml inst/example/nowley docs/superpowers/specs/2026-04-10-soil-sampling-pipeline-design.md
git commit -m "feat: bootstrap soilsampling repository"
```

### Task 2: Add Spatial I/O And Run Directory Management

**Files:**
- Create: `R/io_spatial.R`
- Create: `R/output_reports.R`
- Create: `tests/testthat/test-io-spatial.R`

- [ ] **Step 1: Write the failing spatial I/O tests**

```r
test_that("read_farm_polygon loads the example polygon in EPSG:4326", {
  farm <- read_farm_polygon("inst/example/nowley/Nowley.shp")

  expect_s3_class(farm, "SpatVector")
  expect_equal(as.character(terra::crs(farm, proj = TRUE)), "EPSG:4326")
  expect_true(all(c("GROWER", "FARM", "FIELD", "ID") %in% names(farm)))
})

test_that("initialise_run_dirs creates stable output folders", {
  root <- tempfile("soilsampling-run-")
  dirs <- initialise_run_dirs(root)

  expect_true(all(dir.exists(unlist(dirs))))
  expect_true(all(c("raw", "processed", "vectors", "tables", "reports") %in% names(dirs)))
})
```

- [ ] **Step 2: Run the spatial I/O tests to verify they fail**

Run: `Rscript tests/testthat.R`
Expected: FAIL with missing `read_farm_polygon()` and `initialise_run_dirs()`

- [ ] **Step 3: Write the minimal spatial I/O implementation**

```r
read_farm_polygon <- function(path) {
  farm <- terra::vect(path)
  if (!all(terra::geomtype(farm) %in% c("polygons", "multipolygons"))) {
    stop("Farm input must contain polygon geometry.", call. = FALSE)
  }
  terra::project(farm, "EPSG:4326")
}

initialise_run_dirs <- function(root_dir) {
  dirs <- list(
    root = root_dir,
    raw = file.path(root_dir, "raw"),
    processed = file.path(root_dir, "processed"),
    vectors = file.path(root_dir, "vectors"),
    tables = file.path(root_dir, "tables"),
    reports = file.path(root_dir, "reports")
  )
  invisible(lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE))
  dirs
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript tests/testthat.R`
Expected: PASS for `test-config.R` and `test-io-spatial.R`

- [ ] **Step 5: Commit**

```bash
git add R/io_spatial.R R/output_reports.R tests/testthat/test-io-spatial.R
git commit -m "feat: add spatial input and output directory helpers"
```

### Task 3: Add Covariate Preparation And Stack Processing

**Files:**
- Create: `R/gee_bridge.R`
- Create: `R/covariates.R`
- Create: `R/stack_processing.R`
- Create: `python/gee_downloader.py`
- Create: `python/requirements-gee.txt`
- Create: `scripts/prepare_covariates.R`
- Create: `tests/testthat/test-stack-processing.R`

- [ ] **Step 1: Write the failing stack-processing tests**

```r
test_that("align_and_mask_stack returns a named masked stack", {
  stack_info <- build_example_stack(tempdir())
  result <- align_and_mask_stack(
    raster_paths = stack_info$raster_paths,
    farm = stack_info$farm,
    output_path = tempfile(fileext = ".tif")
  )

  expect_s3_class(result, "SpatRaster")
  expect_true("terrain_slope" %in% names(result))
  expect_true(any(grepl("aspect_", names(result))))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript tests/testthat.R`
Expected: FAIL with missing `align_and_mask_stack()` and helper constructors

- [ ] **Step 3: Implement the covariate recipe and stack processor**

```r
build_covariate_plan <- function(cfg, farm) {
  list(
    terrain = list(
      image = "USGS/SRTMGL1_003",
      bands = c("elevation")
    ),
    sentinel2 = list(
      collection = "COPERNICUS/S2_SR_HARMONIZED",
      bands = c("B2", "B3", "B4", "B8", "B11", "B12")
    )
  )
}

align_and_mask_stack <- function(raster_paths, farm, output_path) {
  template <- terra::rast(raster_paths[[1]])
  aligned <- lapply(raster_paths, function(path) {
    x <- terra::rast(path)
    x <- terra::project(x, template)
    terra::resample(x, template, method = "bilinear")
  })
  stack <- terra::rast(aligned)
  stack <- derive_covariates(stack)
  stack <- terra::mask(terra::crop(stack, farm), farm)
  terra::writeRaster(stack, output_path, overwrite = TRUE)
  stack
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript tests/testthat.R`
Expected: PASS including `test-stack-processing.R`

- [ ] **Step 5: Commit**

```bash
git add R/gee_bridge.R R/covariates.R R/stack_processing.R python/gee_downloader.py python/requirements-gee.txt scripts/prepare_covariates.R tests/testthat/test-stack-processing.R
git commit -m "feat: add covariate preparation pipeline"
```

### Task 4: Add PCA Sampling Core And Sample Export

**Files:**
- Create: `R/pca_sampling.R`
- Create: `scripts/design_samples.R`
- Create: `scripts/run_pipeline.R`
- Create: `tests/testthat/test-pca-sampling.R`

- [ ] **Step 1: Write the failing PCA sampling tests**

```r
test_that("select_pca_components respects the variance threshold", {
  pca <- stats::prcomp(iris[, 1:4], center = TRUE, scale. = TRUE)
  expect_equal(select_pca_components(pca, 0.9), 2L)
})

test_that("allocate_cluster_samples returns one sample minimum per populated cluster", {
  allocation <- allocate_cluster_samples(c(20, 10, 5), sample_count = 6L)
  expect_equal(sum(allocation), 6)
  expect_true(all(allocation >= 1L))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript tests/testthat.R`
Expected: FAIL with missing PCA sampling functions

- [ ] **Step 3: Implement the minimal PCA sampling workflow**

```r
select_pca_components <- function(pca, variance_threshold) {
  explained <- cumsum((pca$sdev ^ 2) / sum(pca$sdev ^ 2))
  as.integer(which(explained >= variance_threshold)[1])
}

allocate_cluster_samples <- function(cluster_sizes, sample_count) {
  weights <- cluster_sizes / sum(cluster_sizes)
  alloc <- pmax(1L, floor(weights * sample_count))
  while (sum(alloc) < sample_count) {
    idx <- which.max(weights - (alloc / sample_count))
    alloc[idx] <- alloc[idx] + 1L
  }
  alloc
}

design_samples <- function(stack, farm, cfg) {
  features <- stack_to_feature_table(stack)
  pca <- stats::prcomp(features[, covariate_columns(features)], center = TRUE, scale. = TRUE)
  k <- cfg$cluster_count
  km <- stats::kmeans(pca$x[, seq_len(select_pca_components(pca, cfg$pca$variance_threshold)), drop = FALSE], centers = k)
  build_sampling_outputs(features, km$cluster, farm, cfg)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript tests/testthat.R`
Expected: PASS including `test-pca-sampling.R`

- [ ] **Step 5: Commit**

```bash
git add R/pca_sampling.R scripts/design_samples.R scripts/run_pipeline.R tests/testthat/test-pca-sampling.R
git commit -m "feat: add PCA-based sampling workflow"
```

### Task 5: Documentation, Diagnostics, And End-To-End Verification

**Files:**
- Modify: `README.md`
- Modify: `tests/testthat/test-config.R`
- Create: `tests/testthat/test-output-reports.R`

- [ ] **Step 1: Write the failing output tests**

```r
test_that("write_sample_outputs creates csv and geopackage outputs", {
  sample_points <- build_example_sample_points()
  dirs <- initialise_run_dirs(tempfile("soilsampling-export-"))

  outputs <- write_sample_outputs(sample_points, dirs, farm_id = "nowley")

  expect_true(file.exists(outputs$csv))
  expect_true(file.exists(outputs$gpkg))
})
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `Rscript tests/testthat.R`
Expected: FAIL with missing export helpers

- [ ] **Step 3: Implement export helpers and README usage**

```r
write_sample_outputs <- function(sample_points, dirs, farm_id) {
  csv_path <- file.path(dirs$tables, paste0(farm_id, "_samples.csv"))
  gpkg_path <- file.path(dirs$vectors, paste0(farm_id, "_samples.gpkg"))
  utils::write.csv(terra::as.data.frame(sample_points, geom = "XY"), csv_path, row.names = FALSE)
  terra::writeVector(sample_points, gpkg_path, overwrite = TRUE)
  list(csv = csv_path, gpkg = gpkg_path)
}
```

- [ ] **Step 4: Run the full verification suite**

Run: `Rscript tests/testthat.R`
Expected: PASS with all tests green

- [ ] **Step 5: Commit**

```bash
git add README.md R/output_reports.R tests/testthat/test-output-reports.R tests/testthat/test-config.R
git commit -m "docs: add usage and output verification"
```
