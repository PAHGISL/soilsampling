testthat::test_that("load_config merges defaults with YAML overrides", {
  cfg <- load_config(file.path(repo_root, "config", "example_nowley.yml"))

  testthat::expect_equal(basename(cfg$farm_path), "Nowley.shp")
  testthat::expect_equal(cfg$sample_count, 9L)
  testthat::expect_equal(cfg$cluster_count, 3L)
  testthat::expect_true(cfg$sentinel1$enabled)
  testthat::expect_true(dir.exists(cfg$output_dir))
})

testthat::test_that("resolve_config_input returns loaded YAML config", {
  resolved <- resolve_config_input("config/example_nowley.yml", repo_root = repo_root)

  testthat::expect_equal(resolved$input_mode, "config")
  testthat::expect_false(resolved$generated)
  testthat::expect_equal(
    resolved$config_path,
    normalizePath(file.path(repo_root, "config", "example_nowley.yml"), winslash = "/", mustWork = TRUE)
  )
  testthat::expect_equal(basename(resolved$cfg$farm_path), "Nowley.shp")
})

testthat::test_that("resolve_config_input builds and persists config for farm polygon input", {
  output_root <- file.path(tempdir(), "soilsampling-config-test")
  farm_path <- file.path(repo_root, "inst", "example", "nowley", "Nowley.shp")

  unlink(output_root, recursive = TRUE, force = TRUE)
  on.exit(unlink(output_root, recursive = TRUE, force = TRUE), add = TRUE)

  resolved <- resolve_config_input(
    input_path = farm_path,
    repo_root = repo_root,
    output_root = output_root
  )

  generated_cfg <- load_config(resolved$config_path)

  testthat::expect_equal(resolved$input_mode, "farm")
  testthat::expect_true(resolved$generated)
  testthat::expect_equal(resolved$cfg$farm_path, normalizePath(farm_path, winslash = "/", mustWork = TRUE))
  testthat::expect_equal(basename(resolved$cfg$output_dir), "nowley")
  testthat::expect_equal(basename(resolved$config_path), "auto_config.yml")
  testthat::expect_true(file.exists(resolved$config_path))
  testthat::expect_equal(generated_cfg$farm_path, resolved$cfg$farm_path)
  testthat::expect_equal(generated_cfg$output_dir, resolved$cfg$output_dir)
})

testthat::test_that("validate_config rejects impossible sampling settings", {
  cfg <- list(
    farm_path = file.path(repo_root, "inst", "example", "nowley", "Nowley.shp"),
    output_dir = "outputs/example",
    gee_project_id = "demo-project",
    sample_count = 2L,
    cluster_count = 3L,
    buffer_distance_m = 30,
    min_point_spacing_m = 20,
    random_seed = 42L,
    date_window = list(start = "2024-01-01", end = "2024-12-31"),
    pca = list(variance_threshold = 0.9, max_components = 6L),
    sentinel1 = list(enabled = TRUE)
  )

  testthat::expect_error(validate_config(cfg), "sample_count")
})
