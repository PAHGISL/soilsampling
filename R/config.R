default_config <- function() {
  list(
    output_dir = file.path("outputs", "nowley"),
    gee_project_id = Sys.getenv("GEE_PROJECT_ID", unset = ""),
    legacy_samples_path = NULL,
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
  if (is.null(overrides)) {
    return(defaults)
  }

  utils::modifyList(defaults, overrides, keep.null = TRUE)
}

is_yaml_config_path <- function(path) {
  is.character(path) &&
    length(path) == 1 &&
    grepl("[.]ya?ml$", path, ignore.case = TRUE)
}

resolve_existing_input_path <- function(path, repo_root = NULL) {
  stopifnot(is.character(path), length(path) == 1)

  candidates <- c(path)
  if (!is.null(repo_root)) {
    candidates <- c(candidates, file.path(repo_root, path))
  }

  for (candidate in unique(candidates)) {
    if (file.exists(candidate)) {
      return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
    }
  }

  stop("Input path does not exist: ", path, call. = FALSE)
}

sanitize_run_name <- function(path) {
  run_name <- tools::file_path_sans_ext(basename(path))
  run_name <- gsub("[^A-Za-z0-9]+", "_", run_name)
  run_name <- tolower(gsub("(^_+|_+$)", "", run_name))

  if (!nzchar(run_name)) {
    return("run")
  }

  run_name
}

normalise_config_paths <- function(cfg, config_dir = NULL) {
  if (!is.null(config_dir)) {
    config_dir <- normalizePath(config_dir, winslash = "/", mustWork = TRUE)
  }

  if (!is.null(config_dir) && !grepl("^(/|[A-Za-z]:[/\\\\])", cfg$farm_path)) {
    cfg$farm_path <- file.path(config_dir, cfg$farm_path)
  }
  if (!is.null(config_dir) && !grepl("^(/|[A-Za-z]:[/\\\\])", cfg$output_dir)) {
    cfg$output_dir <- file.path(config_dir, cfg$output_dir)
  }
  if (!is.null(cfg$legacy_samples_path) &&
      nzchar(as.character(cfg$legacy_samples_path)) &&
      !is.null(config_dir) &&
      !grepl("^(/|[A-Za-z]:[/\\\\])", cfg$legacy_samples_path)) {
    cfg$legacy_samples_path <- file.path(config_dir, cfg$legacy_samples_path)
  }

  cfg$farm_path <- normalizePath(cfg$farm_path, winslash = "/", mustWork = FALSE)
  cfg$output_dir <- normalizePath(cfg$output_dir, winslash = "/", mustWork = FALSE)
  if (!is.null(cfg$legacy_samples_path) && nzchar(as.character(cfg$legacy_samples_path))) {
    cfg$legacy_samples_path <- normalizePath(cfg$legacy_samples_path, winslash = "/", mustWork = FALSE)
  } else {
    cfg$legacy_samples_path <- NULL
  }

  cfg
}

coerce_config_types <- function(cfg) {
  if (is.null(cfg$pca)) {
    cfg$pca <- default_config()$pca
  }
  if (is.null(cfg$sentinel1)) {
    cfg$sentinel1 <- default_config()$sentinel1
  }

  cfg$sample_count <- as.integer(cfg$sample_count)
  cfg$cluster_count <- as.integer(cfg$cluster_count)
  cfg$buffer_distance_m <- as.numeric(cfg$buffer_distance_m)
  cfg$min_point_spacing_m <- as.numeric(cfg$min_point_spacing_m)
  cfg$random_seed <- as.integer(cfg$random_seed)
  cfg$pca$variance_threshold <- as.numeric(cfg$pca$variance_threshold)
  cfg$pca$max_components <- as.integer(cfg$pca$max_components)
  cfg$sentinel1$enabled <- isTRUE(cfg$sentinel1$enabled)
  if (is.null(cfg$legacy_samples_path) || !nzchar(as.character(cfg$legacy_samples_path))) {
    cfg$legacy_samples_path <- NULL
  } else {
    cfg$legacy_samples_path <- as.character(cfg$legacy_samples_path)
  }

  cfg
}

finalise_config <- function(cfg, config_dir = NULL) {
  cfg <- normalise_config_paths(cfg, config_dir = config_dir)
  cfg <- coerce_config_types(cfg)
  validate_config(cfg)
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
  if (!is.null(cfg$legacy_samples_path) &&
      (!is.character(cfg$legacy_samples_path) || length(cfg$legacy_samples_path) != 1 || !nzchar(cfg$legacy_samples_path))) {
    stop("legacy_samples_path must be a single file path when provided.", call. = FALSE)
  }
  if (!is.null(cfg$legacy_samples_path) && !file.exists(cfg$legacy_samples_path)) {
    stop("legacy_samples_path does not exist: ", cfg$legacy_samples_path, call. = FALSE)
  }

  dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)
  cfg$farm_path <- normalizePath(cfg$farm_path, winslash = "/", mustWork = TRUE)
  cfg$output_dir <- normalizePath(cfg$output_dir, winslash = "/", mustWork = TRUE)
  if (!is.null(cfg$legacy_samples_path)) {
    cfg$legacy_samples_path <- normalizePath(cfg$legacy_samples_path, winslash = "/", mustWork = TRUE)
  }

  cfg
}

require_gee_project_id <- function(cfg) {
  if (!nzchar(cfg$gee_project_id)) {
    stop(
      "gee_project_id is required for download stages. Set GEE_PROJECT_ID or provide it in a YAML config.",
      call. = FALSE
    )
  }

  cfg
}

load_config <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = TRUE)
  overrides <- yaml::read_yaml(path)
  cfg <- merge_config(default_config(), overrides)
  finalise_config(cfg, config_dir = dirname(path))
}

build_config_from_farm_path <- function(farm_path, output_root, overrides = NULL) {
  farm_path <- normalizePath(farm_path, winslash = "/", mustWork = TRUE)
  output_root <- normalizePath(output_root, winslash = "/", mustWork = FALSE)

  cfg <- merge_config(default_config(), overrides)
  cfg$farm_path <- farm_path
  cfg$output_dir <- file.path(output_root, sanitize_run_name(farm_path))

  finalise_config(cfg)
}

write_pipeline_config <- function(cfg, path) {
  stopifnot(is.list(cfg), is.character(path), length(path) == 1)

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(cfg, path)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

resolve_config_input <- function(
  input_path,
  repo_root = NULL,
  output_root = NULL,
  generated_config_name = "auto_config.yml"
) {
  resolved_input <- resolve_existing_input_path(input_path, repo_root = repo_root)

  if (is_yaml_config_path(resolved_input)) {
    return(list(
      cfg = load_config(resolved_input),
      config_path = resolved_input,
      input_mode = "config",
      generated = FALSE
    ))
  }

  if (is.null(output_root)) {
    if (is.null(repo_root)) {
      output_root <- file.path("outputs")
    } else {
      output_root <- file.path(repo_root, "outputs")
    }
  }

  cfg <- build_config_from_farm_path(
    farm_path = resolved_input,
    output_root = output_root
  )
  config_path <- write_pipeline_config(
    cfg = cfg,
    path = file.path(cfg$output_dir, "reports", generated_config_name)
  )

  list(
    cfg = cfg,
    config_path = config_path,
    input_mode = "farm",
    generated = TRUE
  )
}
