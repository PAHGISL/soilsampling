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

testthat::test_that("read_legacy_samples_csv loads point geometry in EPSG:4326", {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(
      sample_id = c("USN09", "USN10"),
      x = c(150.129292, 150.12448),
      y = c(-31.363595, -31.360293)
    ),
    path,
    row.names = FALSE
  )

  samples <- read_legacy_samples_csv(path)

  testthat::expect_s4_class(samples$points, "SpatVector")
  testthat::expect_equal(nrow(samples$table), 2L)
  testthat::expect_equal(samples$table$sample_id, c("USN09", "USN10"))
  testthat::expect_true(grepl("WGS 84", terra::crs(samples$points)))
})

testthat::test_that("read_legacy_samples_csv rejects duplicated sample IDs", {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(
      sample_id = c("USN09", "USN09"),
      x = c(150.129292, 150.12448),
      y = c(-31.363595, -31.360293)
    ),
    path,
    row.names = FALSE
  )

  testthat::expect_error(
    read_legacy_samples_csv(path),
    "Duplicated legacy sample_id"
  )
})

testthat::test_that("read_legacy_samples_csv rejects missing required columns", {
  path <- tempfile(fileext = ".csv")
  utils::write.csv(
    data.frame(sample_id = "USN09", x = 150.129292),
    path,
    row.names = FALSE
  )

  testthat::expect_error(
    read_legacy_samples_csv(path),
    "required columns"
  )
})
