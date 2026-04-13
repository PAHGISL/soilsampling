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

read_legacy_samples_csv <- function(path, target_crs = "EPSG:4326") {
  if (!file.exists(path)) {
    stop("Legacy sample file does not exist: ", path, call. = FALSE)
  }

  samples <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  required_cols <- c("sample_id", "x", "y")
  missing_cols <- setdiff(required_cols, names(samples))
  if (length(missing_cols) > 0) {
    stop(
      "Legacy sample file is missing required columns: ",
      paste(missing_cols, collapse = ", "),
      call. = FALSE
    )
  }

  sample_table <- samples[, required_cols, drop = FALSE]
  sample_table$sample_id <- trimws(as.character(sample_table$sample_id))
  sample_table$x <- suppressWarnings(as.numeric(sample_table$x))
  sample_table$y <- suppressWarnings(as.numeric(sample_table$y))

  if (anyNA(sample_table$sample_id) || any(!nzchar(sample_table$sample_id))) {
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

  list(
    table = sample_table,
    points = points
  )
}
