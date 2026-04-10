testthat::test_that("select_pca_components respects the variance threshold", {
  pca <- stats::prcomp(iris[, 1:4], center = TRUE, scale. = TRUE)

  testthat::expect_equal(select_pca_components(pca, 0.9), 2L)
})

testthat::test_that("allocate_cluster_samples returns one sample minimum per populated cluster", {
  allocation <- allocate_cluster_samples(c(20, 10, 5), sample_count = 6L)

  testthat::expect_equal(sum(allocation), 6)
  testthat::expect_true(all(allocation >= 1L))
})

testthat::test_that("select_spaced_samples enforces minimum spacing", {
  candidates <- data.frame(
    x = c(0, 3, 8, 20),
    y = c(0, 0, 0, 0),
    x_proj = c(0, 3, 8, 20),
    y_proj = c(0, 0, 0, 0)
  )

  selected <- select_spaced_samples(candidates, n = 2L, min_spacing_m = 5, seed = 99L)

  testthat::expect_equal(nrow(selected), 2)
  distances <- utils::combn(seq_len(nrow(selected)), 2, function(idx) {
    sqrt((selected$x_proj[idx[1]] - selected$x_proj[idx[2]]) ^ 2 +
      (selected$y_proj[idx[1]] - selected$y_proj[idx[2]]) ^ 2)
  })
  testthat::expect_true(all(distances >= 5))
})

testthat::test_that("design_samples_from_stack drops zero-variance covariates before PCA", {
  farm <- read_farm_polygon(file.path(repo_root, "inst", "example", "nowley", "Nowley.shp"))
  extent <- terra::ext(farm)
  template <- terra::rast(ncols = 20, nrows = 20, ext = extent, crs = "EPSG:4326")

  elevation <- slope <- aspect <- ndvi <- template
  terra::values(elevation) <- seq_len(terra::ncell(elevation))
  terra::values(slope) <- rep(5, terra::ncell(slope))
  terra::values(aspect) <- seq(0, 359, length.out = terra::ncell(aspect))
  terra::values(ndvi) <- seq(0.1, 0.9, length.out = terra::ncell(ndvi))

  names(elevation) <- "terrain_elevation"
  names(slope) <- "terrain_slope"
  names(aspect) <- "terrain_aspect"
  names(ndvi) <- "spectral_ndvi"

  stack <- c(elevation, slope, aspect, ndvi)
  stack <- terra::mask(terra::crop(stack, farm), farm)

  cfg <- load_config(file.path(repo_root, "config", "example_nowley.yml"))
  cfg$sample_count <- 4L
  cfg$cluster_count <- 2L
  cfg$buffer_distance_m <- 0
  cfg$min_point_spacing_m <- 1

  design <- design_samples_from_stack(stack, farm, cfg)

  testthat::expect_equal(nrow(design$sampled_table), 4)
})
