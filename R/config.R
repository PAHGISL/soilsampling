default_config <- function() {
  list(
    output_dir = file.path("outputs", "nowley"),
    gee_project_id = Sys.getenv("GEE_PROJECT_ID", unset = ""),
    sample_count = 9L,
    cluster_count = 3L,
    buffer_distance_m = 30,
    min_point_spacing_m = 20,
    random_seed = 42L,
    date_window = list(
      start = "2024-01-01",
      end = "2024-12-31"
    ),
    pca = list(
      variance_threshold = 0.9,
      max_components = 6L
    ),
    sentinel1 = list(
      enabled = TRUE
    )
  )
}

merge_config <- function(defaults, overrides) {
  utils::modifyList(defaults, overrides, keep.null = TRUE)
}

normalise_config <- function(cfg, config_path) {
  config_dir <- dirname(normalizePath(config_path, winslash = "/", mustWork = TRUE))

  if (!grepl("^(/|[A-Za-z]:[/\\\\])", cfg$farm_path)) {
    cfg$farm_path <- file.path(config_dir, cfg$farm_path)
  }
  if (!grepl("^(/|[A-Za-z]:[/\\\\])", cfg$output_dir)) {
    cfg$output_dir <- file.path(config_dir, cfg$output_dir)
  }

  cfg$farm_path <- normalizePath(cfg$farm_path, winslash = "/", mustWork = FALSE)
  cfg$output_dir <- normalizePath(cfg$output_dir, winslash = "/", mustWork = FALSE)

  cfg$sample_count <- as.integer(cfg$sample_count)
  cfg$cluster_count <- as.integer(cfg$cluster_count)
  cfg$buffer_distance_m <- as.numeric(cfg$buffer_distance_m)
  cfg$min_point_spacing_m <- as.numeric(cfg$min_point_spacing_m)
  cfg$random_seed <- as.integer(cfg$random_seed)
  cfg$pca$variance_threshold <- as.numeric(cfg$pca$variance_threshold)
  cfg$pca$max_components <- as.integer(cfg$pca$max_components)
  cfg$sentinel1$enabled <- isTRUE(cfg$sentinel1$enabled)

  cfg
}

validate_config <- function(cfg) {
  required_fields <- c(
    "farm_path",
    "output_dir",
    "gee_project_id",
    "sample_count",
    "cluster_count",
    "buffer_distance_m",
    "min_point_spacing_m",
    "random_seed",
    "date_window",
    "pca",
    "sentinel1"
  )

  missing_fields <- required_fields[!required_fields %in% names(cfg)]
  if (length(missing_fields) > 0) {
    stop(
      sprintf(
        "Missing required config fields: %s",
        paste(missing_fields, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  if (!isTRUE(cfg$sample_count >= cfg$cluster_count)) {
    stop("sample_count must be greater than or equal to cluster_count.", call. = FALSE)
  }
  if (!isTRUE(cfg$sample_count > 0L)) {
    stop("sample_count must be positive.", call. = FALSE)
  }
  if (!isTRUE(cfg$cluster_count > 0L)) {
    stop("cluster_count must be positive.", call. = FALSE)
  }
  if (!nzchar(cfg$gee_project_id)) {
    stop("gee_project_id must be provided.", call. = FALSE)
  }
  if (!isTRUE(cfg$buffer_distance_m >= 0)) {
    stop("buffer_distance_m must be non-negative.", call. = FALSE)
  }
  if (!isTRUE(cfg$min_point_spacing_m >= 0)) {
    stop("min_point_spacing_m must be non-negative.", call. = FALSE)
  }
  if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", cfg$date_window$start)) {
    stop("date_window$start must use YYYY-MM-DD.", call. = FALSE)
  }
  if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", cfg$date_window$end)) {
    stop("date_window$end must use YYYY-MM-DD.", call. = FALSE)
  }
  if (!isTRUE(cfg$pca$variance_threshold > 0 && cfg$pca$variance_threshold <= 1)) {
    stop("pca$variance_threshold must be between 0 and 1.", call. = FALSE)
  }
  if (!isTRUE(cfg$pca$max_components > 0L)) {
    stop("pca$max_components must be positive.", call. = FALSE)
  }
  if (!nzchar(cfg$farm_path)) {
    stop("farm_path must be provided.", call. = FALSE)
  }
  if (!file.exists(cfg$farm_path)) {
    stop("farm_path does not exist: ", cfg$farm_path, call. = FALSE)
  }

  dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)

  cfg
}

load_config <- function(path) {
  overrides <- yaml::read_yaml(path)
  cfg <- merge_config(default_config(), overrides)
  cfg <- normalise_config(cfg, path)
  validate_config(cfg)
}
