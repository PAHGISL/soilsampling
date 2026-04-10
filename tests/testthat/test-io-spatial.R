testthat::test_that("read_farm_polygon loads the example polygon in EPSG:4326", {
  farm <- read_farm_polygon(file.path(repo_root, "inst", "example", "nowley", "Nowley.shp"))

  testthat::expect_s4_class(farm, "SpatVector")
  testthat::expect_true(grepl("WGS 84", terra::crs(farm)))
  testthat::expect_true(all(c("GROWER", "FARM", "FIELD", "ID") %in% names(farm)))
})

testthat::test_that("read_farm_polygon accepts polygons without legacy metadata fields", {
  source_path <- file.path(repo_root, "inst", "example", "nowley", "Nowley.shp")
  minimal <- terra::vect(source_path)[, 0]
  path <- tempfile(fileext = ".shp")
  terra::writeVector(minimal, path, overwrite = TRUE)

  farm <- read_farm_polygon(path)

  testthat::expect_s4_class(farm, "SpatVector")
  testthat::expect_equal(terra::nrow(farm), terra::nrow(minimal))
})

testthat::test_that("initialise_run_dirs creates stable output folders", {
  root <- tempfile("soilsampling-run-")
  dirs <- initialise_run_dirs(root)

  testthat::expect_true(all(dir.exists(unlist(dirs))))
  testthat::expect_true(all(c("raw", "processed", "vectors", "tables", "reports") %in% names(dirs)))
})
