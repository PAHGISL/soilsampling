read_farm_polygon <- function(path, target_crs = "EPSG:4326") {
  if (!file.exists(path)) {
    stop("Farm polygon file does not exist: ", path, call. = FALSE)
  }

  farm <- terra::vect(path)

  if (nrow(farm) == 0) {
    stop("Farm polygon contains no features.", call. = FALSE)
  }
  if (!all(tolower(terra::geomtype(farm)) %in% c("polygons", "multipolygons"))) {
    stop("Farm input must contain polygon geometry.", call. = FALSE)
  }
  if (!nzchar(terra::crs(farm))) {
    stop("Farm polygon is missing a coordinate reference system.", call. = FALSE)
  }

  farm <- terra::project(farm, target_crs)

  farm
}
