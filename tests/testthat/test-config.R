testthat::test_that("load_config merges defaults with YAML overrides", {
  cfg <- load_config(file.path(repo_root, "config", "example_nowley.yml"))

  testthat::expect_equal(basename(cfg$farm_path), "Nowley.shp")
  testthat::expect_equal(cfg$sample_count, 9L)
  testthat::expect_equal(cfg$cluster_count, 3L)
  testthat::expect_true(cfg$sentinel1$enabled)
  testthat::expect_true(dir.exists(cfg$output_dir))
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
