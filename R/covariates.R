farm_bbox_coords <- function(farm, target_crs = "EPSG:4326") {
  farm_ll <- terra::project(farm, target_crs)
  bbox <- terra::ext(farm_ll)
  c(bbox[1], bbox[3], bbox[2], bbox[4])
}

build_covariate_plan <- function(cfg, farm, raw_dir) {
  coords <- farm_bbox_coords(farm)

  plan <- list(
    terrain = make_gee_config(
      coords = coords,
      download_dir = file.path(raw_dir, "terrain"),
      filename_prefix = "terrain_elevation",
      project_id = cfg$gee_project_id,
      image = "USGS/SRTMGL1_003",
      bands = c("elevation"),
      scale = 30L,
      out_format = "tif",
      postprocess = list(maskval_to_na = FALSE, enforce_float32 = TRUE)
    ),
    sentinel2 = make_gee_config(
      coords = coords,
      download_dir = file.path(raw_dir, "sentinel2"),
      filename_prefix = "sentinel2",
      project_id = cfg$gee_project_id,
      collection = "COPERNICUS/S2_SR_HARMONIZED",
      start_date = cfg$date_window$start,
      end_date = cfg$date_window$end,
      bands = c("B2", "B3", "B4", "B8", "B11", "B12"),
      scale = 10L,
      out_format = "tif",
      max_images = 1L,
      cloud_mask = list(
        enabled = TRUE,
        band = "QA60",
        type = "bits_any",
        bits = c(10L, 11L),
        keep = FALSE
      )
    )
  )

  if (isTRUE(cfg$sentinel1$enabled)) {
    plan$sentinel1 <- make_gee_config(
      coords = coords,
      download_dir = file.path(raw_dir, "sentinel1"),
      filename_prefix = "sentinel1",
      project_id = cfg$gee_project_id,
      collection = "COPERNICUS/S1_GRD",
      start_date = cfg$date_window$start,
      end_date = cfg$date_window$end,
      bands = c("VV", "VH"),
      scale = 10L,
      out_format = "tif",
      max_images = 1L
    )
  }

  plan
}

first_downloaded_tif <- function(download_dir) {
  tif_paths <- list.files(
    download_dir,
    pattern = "[.]tif$",
    recursive = TRUE,
    full.names = TRUE
  )

  if (length(tif_paths) == 0) {
    stop("No GeoTIFF files were downloaded to: ", download_dir, call. = FALSE)
  }

  tif_paths[[1]]
}

execute_covariate_plan <- function(plan, python_script) {
  raster_paths <- character(0)

  for (name in names(plan)) {
    config_path <- file.path(plan[[name]]$download_dir, paste0(name, "_config.yaml"))
    gee_download(
      config = plan[[name]],
      config_path = config_path,
      python_script = python_script
    )
    raster_paths <- c(raster_paths, first_downloaded_tif(plan[[name]]$download_dir))
  }

  raster_paths
}
