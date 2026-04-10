build_example_stack <- function(tmp_dir) {
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

  elevation_path <- file.path(tmp_dir, "terrain_elevation.tif")
  slope_path <- file.path(tmp_dir, "terrain_slope.tif")
  aspect_path <- file.path(tmp_dir, "terrain_aspect.tif")
  ndvi_path <- file.path(tmp_dir, "spectral_ndvi.tif")

  terra::writeRaster(elevation, elevation_path, overwrite = TRUE)
  terra::writeRaster(slope, slope_path, overwrite = TRUE)
  terra::writeRaster(aspect, aspect_path, overwrite = TRUE)
  terra::writeRaster(ndvi, ndvi_path, overwrite = TRUE)

  list(
    raster_paths = c(elevation_path, slope_path, aspect_path, ndvi_path),
    farm = farm
  )
}

testthat::test_that("align_and_mask_stack returns a named masked stack", {
  stack_info <- build_example_stack(tempdir())
  result <- align_and_mask_stack(
    raster_paths = stack_info$raster_paths,
    farm = stack_info$farm,
    output_path = tempfile(fileext = ".tif")
  )

  testthat::expect_s4_class(result, "SpatRaster")
  testthat::expect_true("terrain_slope" %in% names(result))
  testthat::expect_true(all(c("aspect_sin", "aspect_cos") %in% names(result)))
  testthat::expect_true("spectral_ndvi" %in% names(result))
})
