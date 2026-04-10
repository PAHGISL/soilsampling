initialise_run_dirs <- function(root_dir) {
  root_dir <- normalizePath(root_dir, winslash = "/", mustWork = FALSE)

  dirs <- list(
    root = root_dir,
    raw = file.path(root_dir, "raw"),
    processed = file.path(root_dir, "processed"),
    vectors = file.path(root_dir, "vectors"),
    tables = file.path(root_dir, "tables"),
    reports = file.path(root_dir, "reports")
  )

  for (path in dirs) {
    dir.create(path, recursive = TRUE, showWarnings = FALSE)
  }

  dirs
}

write_run_summary_json <- function(summary, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(summary, path = path, auto_unbox = TRUE, pretty = TRUE)
  path
}

write_sample_outputs <- function(sample_points, dirs, farm_id) {
  csv_path <- file.path(dirs$tables, paste0(farm_id, "_samples.csv"))
  gpkg_path <- file.path(dirs$vectors, paste0(farm_id, "_samples.gpkg"))
  shp_path <- file.path(dirs$vectors, paste0(farm_id, "_samples.shp"))

  sample_table <- terra::as.data.frame(sample_points, geom = "XY")
  utils::write.csv(sample_table, csv_path, row.names = FALSE)
  terra::writeVector(sample_points, gpkg_path, filetype = "GPKG", overwrite = TRUE)
  terra::writeVector(sample_points, shp_path, filetype = "ESRI Shapefile", overwrite = TRUE)

  list(
    csv = csv_path,
    gpkg = gpkg_path,
    shp = shp_path
  )
}

write_design_outputs <- function(design, dirs, farm_id) {
  sample_paths <- write_sample_outputs(design$samples, dirs, farm_id)
  cluster_raster_path <- file.path(dirs$processed, "cluster_map.tif")
  cluster_summary_path <- file.path(dirs$tables, paste0(farm_id, "_cluster_summary.csv"))
  diagnostic_path <- file.path(dirs$reports, "design_diagnostics.png")
  summary_path <- file.path(dirs$reports, "run_summary.json")

  terra::writeRaster(design$cluster_raster, filename = cluster_raster_path, overwrite = TRUE)

  cluster_summary <- as.data.frame(table(design$sampled_table$cluster), stringsAsFactors = FALSE)
  names(cluster_summary) <- c("cluster", "n_samples")
  utils::write.csv(cluster_summary, cluster_summary_path, row.names = FALSE)

  grDevices::png(diagnostic_path, width = 1600, height = 1200, res = 200, family = "Arial")
  old_par <- graphics::par(no.readonly = TRUE)
  on.exit({
    graphics::par(old_par)
    grDevices::dev.off()
  }, add = TRUE)
  graphics::par(family = "Arial")
  terra::plot(design$cluster_raster, main = "Cluster Map And Sample Points")
  sample_coords <- terra::crds(design$samples)
  graphics::points(sample_coords[, 1], sample_coords[, 2], pch = 16, col = "black")

  write_run_summary_json(
    summary = list(
      farm_id = farm_id,
      sample_count = nrow(design$sampled_table),
      selected_components = design$selected_components,
      outputs = c(sample_paths, list(cluster_raster = cluster_raster_path, cluster_summary = cluster_summary_path, diagnostic = diagnostic_path))
    ),
    path = summary_path
  )

  c(
    sample_paths,
    list(
      cluster_raster = cluster_raster_path,
      cluster_summary = cluster_summary_path,
      diagnostic = diagnostic_path,
      summary = summary_path
    )
  )
}
