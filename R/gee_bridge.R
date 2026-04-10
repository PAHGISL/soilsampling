gee_python_packages <- c(
  "earthengine-api",
  "requests",
  "pyyaml",
  "python-dateutil"
)

install_r_packages <- function(packages) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
  missing_packages <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_packages) > 0) {
    install.packages(missing_packages)
  }
  invisible(packages)
}

ensure_gee_python <- function(project_id = Sys.getenv("GEE_PROJECT_ID"), force_auth = FALSE) {
  if (!is.character(project_id) || length(project_id) != 1 || !nzchar(project_id)) {
    stop("Provide project_id or set GEE_PROJECT_ID before running downloads.", call. = FALSE)
  }

  install_r_packages(c("reticulate", "yaml"))

  Sys.setenv(
    RETICULATE_USE_MANAGED_VENV = "yes",
    GEE_PROJECT_ID = project_id
  )

  reticulate::py_require(packages = gee_python_packages, action = "set")
  ee <- reticulate::import("ee", delay_load = FALSE)

  if (isTRUE(force_auth)) {
    message("Refreshing Earth Engine browser authentication...")
    ee$Authenticate(force = TRUE)
  }

  init_ok <- TRUE
  tryCatch(
    ee$Initialize(project = project_id),
    error = function(e) {
      init_ok <<- FALSE
      message("Earth Engine authentication is required: ", conditionMessage(e))
    }
  )

  if (!init_ok) {
    message("Starting Earth Engine browser authentication...")
    ee$Authenticate()
    ee$Initialize(project = project_id)
  }

  invisible(reticulate::py_config())
}

write_gee_config <- function(config, path) {
  install_r_packages("yaml")

  if (!is.list(config)) {
    stop("config must be a named list.", call. = FALSE)
  }
  if (!is.character(path) || length(path) != 1 || !nzchar(path)) {
    stop("path must be a single output file path.", call. = FALSE)
  }

  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(config, path)
  normalizePath(path, winslash = "/", mustWork = FALSE)
}

vector_bbox_coords <- function(vector_path, target_crs = "EPSG:4326") {
  install_r_packages("terra")

  v <- terra::vect(vector_path)
  v_ll <- terra::project(v, target_crs)
  bbox <- terra::ext(v_ll)
  c(bbox[1], bbox[3], bbox[2], bbox[4])
}

split_iso_date <- function(x, arg_name) {
  if (inherits(x, "Date")) {
    x <- format(x, "%Y-%m-%d")
  }
  if (!is.character(x) || length(x) != 1 || !grepl("^\\d{4}-\\d{2}-\\d{2}$", x)) {
    stop(arg_name, " must be a single date in YYYY-MM-DD format.", call. = FALSE)
  }

  parts <- strsplit(x, "-", fixed = TRUE)[[1]]
  list(
    year = as.integer(parts[1]),
    month = as.integer(parts[2]),
    day = as.integer(parts[3])
  )
}

make_gee_config <- function(
  coords,
  download_dir,
  filename_prefix,
  project_id,
  bands,
  scale,
  collection = NULL,
  image = NULL,
  start_date = NULL,
  end_date = NULL,
  out_format = "tif",
  auth_mode = "browser",
  crs = "EPSG:4326",
  max_images = NULL,
  cloud_mask = list(enabled = FALSE),
  postprocess = list(maskval_to_na = TRUE, enforce_float32 = FALSE)
) {
  has_collection <- !is.null(collection)
  has_image <- !is.null(image)

  if (has_collection == has_image) {
    stop("Provide exactly one of collection or image.", call. = FALSE)
  }
  if (!is.numeric(coords) || length(coords) != 4) {
    stop("coords must be a numeric vector of length 4: c(min_lon, min_lat, max_lon, max_lat).", call. = FALSE)
  }
  if (!is.character(project_id) || length(project_id) != 1 || !nzchar(project_id)) {
    stop("Provide a single non-empty project_id.", call. = FALSE)
  }

  config <- list(
    coords = as.numeric(coords),
    download_dir = download_dir,
    filename_prefix = filename_prefix,
    project_id = project_id,
    bands = as.character(bands),
    scale = as.integer(scale),
    out_format = out_format,
    auth_mode = auth_mode,
    crs = crs
  )

  if (!is.null(max_images)) {
    config$max_images <- as.integer(max_images)
  }
  if (!is.null(cloud_mask)) {
    config$cloud_mask <- cloud_mask
  }
  if (!is.null(postprocess)) {
    config$postprocess <- postprocess
  }

  if (has_collection) {
    start_parts <- split_iso_date(start_date, "start_date")
    end_parts <- split_iso_date(end_date, "end_date")
    config$collection <- collection
    config$start_year <- start_parts$year
    config$start_month <- start_parts$month
    config$start_day <- start_parts$day
    config$end_year <- end_parts$year
    config$end_month <- end_parts$month
    config$end_day <- end_parts$day
  } else {
    config$image <- image
  }

  config
}

example_hlsl30_config <- function(
  download_dir = file.path("student_downloads", "HLSL30_Llara"),
  project_id = Sys.getenv("GEE_PROJECT_ID", unset = "your-google-cloud-project-id")
) {
  list(
    coords = c(149.8, -30.4, 150.0, -30.2),
    download_dir = download_dir,
    filename_prefix = "HLS_Landsat_30m",
    project_id = project_id,
    collection = "NASA/HLS/HLSL30/v002",
    start_year = 2025L,
    start_month = 1L,
    start_day = 1L,
    end_year = 2025L,
    end_month = 10L,
    end_day = 1L,
    bands = c("B4", "B5"),
    scale = 30L,
    out_format = "tif",
    auth_mode = "browser",
    max_images = 5L,
    cloud_mask = list(
      enabled = TRUE,
      band = "Fmask",
      type = "bits_any",
      bits = c(1L),
      keep = FALSE
    ),
    postprocess = list(
      maskval_to_na = TRUE,
      enforce_float32 = FALSE
    )
  )
}

authenticate_gee <- function(project_id = Sys.getenv("GEE_PROJECT_ID"), force = FALSE) {
  ensure_gee_python(project_id = project_id, force_auth = force)
}

gee_download <- function(
  config = NULL,
  config_path = NULL,
  python_script = "gee_downloader.py",
  project_id = NULL,
  show_output = TRUE
) {
  if (is.null(config) && is.null(config_path)) {
    stop("Provide either config or config_path.", call. = FALSE)
  }

  if (!is.null(config)) {
    if (!is.list(config)) {
      stop("config must be a named list.", call. = FALSE)
    }
    if (is.null(config_path)) {
      config_path <- file.path(tempdir(), "gee_download_config.yaml")
    }
    config_path <- write_gee_config(config, config_path)
  } else {
    install_r_packages("yaml")
    config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)
  }

  if (is.null(project_id)) {
    if (!is.null(config$project_id)) {
      project_id <- config$project_id
    } else {
      config_from_yaml <- yaml::read_yaml(config_path)
      project_id <- config_from_yaml$project_id %||% Sys.getenv("GEE_PROJECT_ID")
    }
  }

  ensure_gee_python(project_id = project_id)

  python_script <- normalizePath(python_script, winslash = "/", mustWork = TRUE)
  python_exe <- reticulate::py_exe()
  quoted_args <- shQuote(c(python_script, config_path))
  output <- system2(
    command = python_exe,
    args = quoted_args,
    stdout = TRUE,
    stderr = TRUE
  )

  status <- attr(output, "status")
  if (is.null(status)) {
    status <- 0
  }

  if (isTRUE(show_output) && length(output) > 0) {
    cat(paste(output, collapse = "\n"), "\n")
  }

  if (status != 0) {
    stop("gee_downloader.py failed. Check the printed output above.", call. = FALSE)
  }

  invisible(
    list(
      python = python_exe,
      python_script = python_script,
      config_path = config_path,
      output = output
    )
  )
}

`%||%` <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    return(y)
  }
  x
}

# Example:
# source("utils/gee_bridge.R")
# cfg <- example_hlsl30_config(project_id = "your-google-cloud-project-id")
# gee_download(
#   config = cfg,
#   config_path = file.path("student_hlsl30_config.yaml"),
#   python_script = file.path("utils", "gee_downloader.py")
# )
