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

testthat::test_that("design_diagnostic_palette follows the Nowley color order", {
  palette <- design_diagnostic_palette(c(3L, 1L, 2L))

  testthat::expect_equal(
    unname(palette),
    c("#DCEAF7", "#F9E6D2", "#DDEFD9")
  )
  testthat::expect_equal(names(palette), c("1", "2", "3"))
})

testthat::test_that("design_diagnostic_point_fill colors samples by cluster", {
  sample_table <- data.frame(cluster = c(2L, 1L, NA))
  cluster_lookup <- design_diagnostic_palette(c(1L, 2L))

  fills <- design_diagnostic_point_fill(sample_table, cluster_lookup)

  testthat::expect_equal(fills, c("#F9E6D2", "#DCEAF7", "#FFFFFF"))
})

testthat::test_that("write_sample_outputs creates csv and geopackage outputs", {
  sample_points <- build_example_sample_points()
  dirs <- initialise_run_dirs(tempfile("soilsampling-export-"))

  outputs <- write_sample_outputs(sample_points, dirs, farm_id = "nowley")

  testthat::expect_true(file.exists(outputs$csv))
  testthat::expect_true(file.exists(outputs$gpkg))
})

testthat::test_that("write_sample_outputs preserves sample_source in csv output", {
  sample_points <- build_example_sample_points()
  dirs <- initialise_run_dirs(tempfile("soilsampling-export-"))

  outputs <- write_sample_outputs(sample_points, dirs, farm_id = "contours")
  written <- utils::read.csv(outputs$csv, stringsAsFactors = FALSE)

  testthat::expect_equal(written$sample_source, c("legacy", "new"))
})

testthat::test_that("write_design_outputs creates diagnostic and summary outputs", {
  sample_points <- build_example_sample_points()
  dirs <- initialise_run_dirs(tempfile("soilsampling-design-export-"))
  cluster_raster <- terra::rast(ncols = 5, nrows = 5, xmin = 0, xmax = 1, ymin = 0, ymax = 1, crs = "EPSG:4326")
  terra::values(cluster_raster) <- rep(1:5, each = 5)

  design <- list(
    samples = sample_points,
    sampled_table = terra::as.data.frame(sample_points, geom = "XY"),
    cluster_raster = cluster_raster,
    selected_components = 2L
  )

  outputs <- write_design_outputs(design, dirs, farm_id = "nowley")

  testthat::expect_true(file.exists(outputs$diagnostic))
  testthat::expect_true(file.exists(outputs$summary))
})
