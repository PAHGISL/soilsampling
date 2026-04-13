# Contours Legacy Samples Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add optional legacy-sample support so the sampler can generate new points while enforcing spacing against existing legacy points and writing one combined delivered sample set.

**Architecture:** Extend config parsing with an optional `legacy_samples_path`, read and validate legacy points through spatial I/O helpers, and update the PCA sampling stage so legacy points participate in spacing and final output assembly without changing the default workflow when no legacy CSV is supplied. Keep output writers and docs aligned with the new combined sample schema.

**Tech Stack:** R, terra, testthat, yaml, jsonlite

---

### Task 1: Config And Legacy CSV Input

**Files:**
- Modify: `R/config.R`
- Modify: `R/io_spatial.R`
- Modify: `tests/testthat/test-config.R`
- Modify: `tests/testthat/test-io-spatial.R`

- [ ] **Step 1: Write the failing config and CSV-reader tests**

```r
testthat::test_that("load_config resolves optional legacy_samples_path", {
  cfg <- load_config(file.path(repo_root, "config", "contours_config.yml"))

  testthat::expect_equal(
    basename(cfg$legacy_samples_path),
    "Contours_samples_legacy.csv"
  )
})

testthat::test_that("validate_config rejects missing legacy sample files", {
  cfg <- default_config()
  cfg$farm_path <- file.path(repo_root, "inst", "example", "nowley", "Nowley.shp")
  cfg$output_dir <- tempfile("soilsampling-output-")
  cfg$gee_project_id <- "demo-project"
  cfg$legacy_samples_path <- file.path(tempdir(), "missing.csv")

  testthat::expect_error(validate_config(cfg), "legacy_samples_path")
})

testthat::test_that("read_legacy_samples_csv loads point geometry", {
  samples <- read_legacy_samples_csv(
    file.path(repo_root, "specs", "Contours_samples_legacy.csv")
  )

  testthat::expect_s4_class(samples$points, "SpatVector")
  testthat::expect_equal(nrow(samples$table), 4L)
  testthat::expect_equal(samples$table$sample_id[[1]], "USN09")
})

testthat::test_that("read_legacy_samples_csv rejects duplicate sample IDs", {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(sample_id = c("A", "A"), x = c(150, 151), y = c(-31, -31.1)),
    path,
    row.names = FALSE
  )

  testthat::expect_error(read_legacy_samples_csv(path), "Duplicated legacy sample_id")
})
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run: `Rscript -e "source('tests/testthat.R')"` is too broad for red-green here, so run:

```bash
Rscript -e "repo_root <- normalizePath('.'); for (p in sort(list.files('R', pattern='[.][Rr]$', full.names=TRUE))) sys.source(p, envir = globalenv()); testthat::test_file('tests/testthat/test-config.R'); testthat::test_file('tests/testthat/test-io-spatial.R')"
```

Expected: FAIL because `legacy_samples_path` and `read_legacy_samples_csv()` do not exist yet.

- [ ] **Step 3: Write the minimal config and CSV-reader implementation**

```r
normalise_config_paths <- function(cfg, config_dir = NULL) {
  if (!is.null(config_dir)) {
    config_dir <- normalizePath(config_dir, winslash = "/", mustWork = TRUE)
  }

  if (!is.null(config_dir) && !grepl("^(/|[A-Za-z]:[/\\\\])", cfg$farm_path)) {
    cfg$farm_path <- file.path(config_dir, cfg$farm_path)
  }
  if (!is.null(config_dir) && !grepl("^(/|[A-Za-z]:[/\\\\])", cfg$output_dir)) {
    cfg$output_dir <- file.path(config_dir, cfg$output_dir)
  }
  if (!is.null(cfg$legacy_samples_path) &&
      nzchar(cfg$legacy_samples_path) &&
      !is.null(config_dir) &&
      !grepl("^(/|[A-Za-z]:[/\\\\])", cfg$legacy_samples_path)) {
    cfg$legacy_samples_path <- file.path(config_dir, cfg$legacy_samples_path)
  }

  cfg$farm_path <- normalizePath(cfg$farm_path, winslash = "/", mustWork = FALSE)
  cfg$output_dir <- normalizePath(cfg$output_dir, winslash = "/", mustWork = FALSE)
  if (!is.null(cfg$legacy_samples_path) && nzchar(cfg$legacy_samples_path)) {
    cfg$legacy_samples_path <- normalizePath(cfg$legacy_samples_path, winslash = "/", mustWork = FALSE)
  } else {
    cfg$legacy_samples_path <- NULL
  }

  cfg
}

validate_config <- function(cfg) {
  if (!is.null(cfg$legacy_samples_path) &&
      (!is.character(cfg$legacy_samples_path) || length(cfg$legacy_samples_path) != 1 || !nzchar(cfg$legacy_samples_path))) {
    stop("legacy_samples_path must be a single file path when provided.", call. = FALSE)
  }
  if (!is.null(cfg$legacy_samples_path) && !file.exists(cfg$legacy_samples_path)) {
    stop("legacy_samples_path does not exist: ", cfg$legacy_samples_path, call. = FALSE)
  }

  dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)

  cfg
}

read_legacy_samples_csv <- function(path, target_crs = "EPSG:4326") {
  if (!file.exists(path)) {
    stop("Legacy sample file does not exist: ", path, call. = FALSE)
  }

  samples <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required_cols <- c("sample_id", "x", "y")
  missing_cols <- setdiff(required_cols, names(samples))
  if (length(missing_cols) > 0) {
    stop("Legacy sample file is missing required columns: ", paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  sample_table <- samples[, required_cols, drop = FALSE]
  sample_table$sample_id <- trimws(as.character(sample_table$sample_id))
  sample_table$x <- suppressWarnings(as.numeric(sample_table$x))
  sample_table$y <- suppressWarnings(as.numeric(sample_table$y))

  if (any(!nzchar(sample_table$sample_id))) {
    stop("Legacy sample_id values must be non-empty.", call. = FALSE)
  }
  if (anyDuplicated(sample_table$sample_id)) {
    stop("Duplicated legacy sample_id values are not allowed.", call. = FALSE)
  }
  if (any(!is.finite(sample_table$x)) || any(!is.finite(sample_table$y))) {
    stop("Legacy samples must provide numeric x and y coordinates.", call. = FALSE)
  }

  points <- terra::vect(sample_table, geom = c("x", "y"), crs = "EPSG:4326", keepgeom = TRUE)
  points <- terra::project(points, target_crs)

  list(table = sample_table, points = points)
}
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run:

```bash
Rscript -e "repo_root <- normalizePath('.'); for (p in sort(list.files('R', pattern='[.][Rr]$', full.names=TRUE))) sys.source(p, envir = globalenv()); testthat::test_file('tests/testthat/test-config.R'); testthat::test_file('tests/testthat/test-io-spatial.R')"
```

Expected: PASS for the new legacy config and CSV-reader coverage.

- [ ] **Step 5: Commit**

```bash
git add R/config.R R/io_spatial.R tests/testthat/test-config.R tests/testthat/test-io-spatial.R
git commit -m "feat: add legacy sample config support"
```

### Task 2: Legacy-Aware Sampling

**Files:**
- Modify: `R/pca_sampling.R`
- Modify: `tests/testthat/test-pca-sampling.R`

- [ ] **Step 1: Write the failing spacing and combined-design tests**

```r
testthat::test_that("select_spaced_samples respects occupied legacy coordinates", {
  candidates <- data.frame(
    point_id = 1:4,
    x = c(0, 10, 25, 40),
    y = c(0, 0, 0, 0),
    x_proj = c(0, 10, 25, 40),
    y_proj = c(0, 0, 0, 0)
  )

  selected <- select_spaced_samples(
    candidates = candidates,
    n = 2L,
    min_spacing_m = 15,
    seed = 99L,
    occupied = data.frame(x_proj = 12, y_proj = 0)
  )

  testthat::expect_equal(nrow(selected), 2L)
  testthat::expect_false(any(selected$point_id %in% c(1L, 2L)))
})

testthat::test_that("design_samples_from_stack appends legacy samples and keeps spacing", {
  farm <- read_farm_polygon(file.path(repo_root, "inst", "example", "nowley", "Nowley.shp"))
  extent <- terra::ext(farm)
  template <- terra::rast(ncols = 20, nrows = 20, ext = extent, crs = "EPSG:4326")

  elevation <- ndvi <- slope <- template
  terra::values(elevation) <- seq_len(terra::ncell(elevation))
  terra::values(ndvi) <- seq(0.1, 0.9, length.out = terra::ncell(ndvi))
  terra::values(slope) <- seq(1, 10, length.out = terra::ncell(slope))

  names(elevation) <- "terrain_elevation"
  names(ndvi) <- "spectral_ndvi"
  names(slope) <- "terrain_slope"

  stack <- terra::mask(terra::crop(c(elevation, ndvi, slope), farm), farm)

  legacy_path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(
      sample_id = c("USN09", "USN10"),
      x = c(150.129292, 150.12448),
      y = c(-31.363595, -31.360293)
    ),
    legacy_path,
    row.names = FALSE
  )

  cfg <- load_config(file.path(repo_root, "config", "example_nowley.yml"))
  cfg$sample_count <- 3L
  cfg$cluster_count <- 2L
  cfg$buffer_distance_m <- 0
  cfg$min_point_spacing_m <- 20
  cfg$legacy_samples_path <- legacy_path

  design <- design_samples_from_stack(stack, farm, cfg)

  testthat::expect_equal(sum(design$sampled_table$sample_source == "new"), 3L)
  testthat::expect_equal(sum(design$sampled_table$sample_source == "legacy"), 2L)
  testthat::expect_true(all(c("USN09", "USN10") %in% design$sampled_table$sample_id))
})
```

- [ ] **Step 2: Run the focused sampling tests to verify they fail**

Run:

```bash
Rscript -e "repo_root <- normalizePath('.'); for (p in sort(list.files('R', pattern='[.][Rr]$', full.names=TRUE))) sys.source(p, envir = globalenv()); testthat::test_file('tests/testthat/test-pca-sampling.R')"
```

Expected: FAIL because spacing does not yet account for legacy points and no combined legacy output exists.

- [ ] **Step 3: Write the minimal legacy-aware sampling implementation**

```r
select_spaced_samples <- function(candidates, n, min_spacing_m, seed, occupied = NULL) {
  if (nrow(candidates) < n) {
    stop("Not enough candidate points to sample from.", call. = FALSE)
  }

  set.seed(seed)
  order_idx <- sample(seq_len(nrow(candidates)))
  selected_idx <- integer(0)
  occupied_x <- if (is.null(occupied)) numeric(0) else occupied$x_proj
  occupied_y <- if (is.null(occupied)) numeric(0) else occupied$y_proj

  for (idx in order_idx) {
    all_x <- c(occupied_x, candidates$x_proj[selected_idx])
    all_y <- c(occupied_y, candidates$y_proj[selected_idx])
    if (length(all_x) == 0L ||
        all(sqrt((all_x - candidates$x_proj[idx]) ^ 2 + (all_y - candidates$y_proj[idx]) ^ 2) >= min_spacing_m)) {
      selected_idx <- c(selected_idx, idx)
    }
    if (length(selected_idx) == n) {
      break
    }
  }

  if (length(selected_idx) < n) {
    stop("Unable to satisfy the minimum point spacing with the available candidates.", call. = FALSE)
  }

  candidates[selected_idx, , drop = FALSE]
}

assign_clusters_to_scores <- function(scores, centers) {
  distances <- vapply(
    seq_len(nrow(centers)),
    function(idx) rowSums((scores - matrix(centers[idx, ], nrow(scores), ncol(scores), byrow = TRUE)) ^ 2),
    numeric(nrow(scores))
  )
  max.col(-distances)
}

enrich_legacy_samples <- function(stack, legacy_points, pca, selected_components, km) {
  extracted <- terra::extract(stack, legacy_points, ID = FALSE)
  if (any(!stats::complete.cases(extracted))) {
    stop("Legacy samples fall outside valid analysis stack cells.", call. = FALSE)
  }

  sample_table <- cbind(terra::as.data.frame(legacy_points, geom = "XY"), extracted)
  scores <- stats::predict(pca, newdata = extracted)[, seq_len(selected_components), drop = FALSE]
  sample_table$cluster <- assign_clusters_to_scores(scores, km$centers)
  sample_table$sample_source <- "legacy"
  sample_table
}

design_samples_from_stack <- function(stack, farm, cfg) {
  legacy <- if (!is.null(cfg$legacy_samples_path)) read_legacy_samples_csv(cfg$legacy_samples_path) else NULL
  if (!is.null(legacy) && nrow(legacy$points[!farm]) > 0) {
    stop("Legacy samples must fall within the farm polygon.", call. = FALSE)
  }

  feature_table <- stack_to_feature_table(stack)
  candidate_features <- buffer_candidate_features(
    feature_table = feature_table,
    farm = farm,
    buffer_distance_m = cfg$buffer_distance_m,
    stack_crs = terra::crs(stack)
  )

  feature_cols <- covariate_columns(candidate_features)
  feature_cols <- drop_zero_variance_covariates(candidate_features, feature_cols)
  pca <- stats::prcomp(candidate_features[, feature_cols, drop = FALSE], center = TRUE, scale. = TRUE)
  selected_components <- select_pca_components(
    pca = pca,
    variance_threshold = cfg$pca$variance_threshold,
    max_components = cfg$pca$max_components
  )

  scores <- pca$x[, seq_len(selected_components), drop = FALSE]
  km <- stats::kmeans(scores, centers = cfg$cluster_count, nstart = 25)
  candidate_features$cluster <- km$cluster
  sampled_new <- sample_cluster_points(candidate_features, allocation, cfg, legacy_points = legacy)
  sampled_new$sample_source <- "new"
  sampled_new$sample_id <- generate_sample_ids(sampled_new, legacy_ids = legacy$table$sample_id)
  legacy_table <- if (is.null(legacy)) NULL else enrich_legacy_samples(stack, legacy$points, pca, selected_components, km)
  sampled <- rbind(legacy_table, sampled_new)

  list(
    samples = terra::vect(sampled, geom = c("x", "y"), crs = terra::crs(stack), keepgeom = TRUE),
    sampled_table = sampled,
    cluster_raster = build_cluster_raster(stack, candidate_features),
    pca = pca,
    selected_components = selected_components
  )
}
```

- [ ] **Step 4: Run the focused sampling tests to verify they pass**

Run:

```bash
Rscript -e "repo_root <- normalizePath('.'); for (p in sort(list.files('R', pattern='[.][Rr]$', full.names=TRUE))) sys.source(p, envir = globalenv()); testthat::test_file('tests/testthat/test-pca-sampling.R')"
```

Expected: PASS for spacing against legacy points and combined sample output counts.

- [ ] **Step 5: Commit**

```bash
git add R/pca_sampling.R tests/testthat/test-pca-sampling.R
git commit -m "feat: integrate legacy samples into spacing and design outputs"
```

### Task 3: Output Writers, Example Config, And Documentation

**Files:**
- Modify: `R/output_reports.R`
- Modify: `tests/testthat/test-output-reports.R`
- Modify: `config/contours_config.yml`
- Modify: `README.md`

- [ ] **Step 1: Write the failing output and documentation-oriented tests**

```r
testthat::test_that("write_sample_outputs preserves sample_source in CSV output", {
  sample_points <- terra::vect(
    data.frame(
      x = c(150.09, 150.11),
      y = c(-31.34, -31.35),
      cluster = c(1L, 2L),
      sample_id = c("USN09", "S01"),
      sample_source = c("legacy", "new")
    ),
    geom = c("x", "y"),
    crs = "EPSG:4326",
    keepgeom = TRUE
  )

  dirs <- initialise_run_dirs(tempfile("soilsampling-export-"))
  outputs <- write_sample_outputs(sample_points, dirs, farm_id = "contours")
  written <- utils::read.csv(outputs$csv, stringsAsFactors = FALSE)

  testthat::expect_equal(written$sample_source, c("legacy", "new"))
})
```

- [ ] **Step 2: Run the focused output tests to verify the current baseline**

Run:

```bash
Rscript -e "repo_root <- normalizePath('.'); for (p in sort(list.files('R', pattern='[.][Rr]$', full.names=TRUE))) sys.source(p, envir = globalenv()); testthat::test_file('tests/testthat/test-output-reports.R')"
```

Expected: PASS or FAIL depending on whether output helpers already preserve the new `sample_source` field; if it already passes, move directly to the implementation and doc updates.

- [ ] **Step 3: Write the minimal output and documentation updates**

```r
build_example_sample_points <- function() {
  point_table <- data.frame(
    x = c(150.09, 150.11),
    y = c(-31.34, -31.35),
    cluster = c(1L, 2L),
    sample_id = c("USN09", "S01"),
    sample_source = c("legacy", "new")
  )

  terra::vect(point_table, geom = c("x", "y"), crs = "EPSG:4326", keepgeom = TRUE)
}
```

```yaml
output_dir: /Users/yiyu/Library/CloudStorage/OneDrive-TheUniversityofSydney(Staff)/Work/Workspace/github/soilsampling/outputs/nowley_field5
gee_project_id: yiyu-research
sample_count: 8
legacy_samples_path: ../specs/Contours_samples_legacy.csv
cluster_count: 3
buffer_distance_m: 30.0
min_point_spacing_m: 20.0
random_seed: 17
date_window:
  start: '2025-01-01'
  end: '2025-12-31'
```

```md
- `legacy_samples_path`: optional CSV of previously sampled points to keep in the final deliverable
- When `legacy_samples_path` is supplied, `sample_count` means the number of newly generated points, and all spacing checks are enforced against both legacy and new points.
```

- [ ] **Step 4: Run the focused output tests to verify they pass**

Run:

```bash
Rscript -e "repo_root <- normalizePath('.'); for (p in sort(list.files('R', pattern='[.][Rr]$', full.names=TRUE))) sys.source(p, envir = globalenv()); testthat::test_file('tests/testthat/test-output-reports.R')"
```

Expected: PASS with `sample_source` preserved in written outputs.

- [ ] **Step 5: Run verification**

Run:

```bash
Rscript -e "repo_root <- normalizePath('.'); for (p in sort(list.files('R', pattern='[.][Rr]$', full.names=TRUE))) sys.source(p, envir = globalenv()); testthat::test_file('tests/testthat/test-config.R'); testthat::test_file('tests/testthat/test-io-spatial.R'); testthat::test_file('tests/testthat/test-pca-sampling.R'); testthat::test_file('tests/testthat/test-output-reports.R')"
Rscript tests/testthat.R
```

Expected:
- Focused tests PASS for the new feature.
- Full suite shows the feature tests passing and may still report the known pre-existing temp-path normalization failure in `tests/testthat/test-config.R` unless that unrelated issue is fixed separately during the work.

- [ ] **Step 6: Commit**

```bash
git add R/output_reports.R tests/testthat/test-output-reports.R config/contours_config.yml README.md docs/superpowers/plans/2026-04-13-contours-legacy-samples.md
git commit -m "feat: document and export contour legacy samples"
```
