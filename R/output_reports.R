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

design_diagnostic_palette <- function(cluster_values) {
  cluster_values <- sort(unique(stats::na.omit(as.integer(cluster_values))))
  if (length(cluster_values) == 0) {
    return(stats::setNames(character(0), character(0)))
  }

  light_palette <- c(
    "#DCEAF7",
    "#F9E6D2",
    "#DDEFD9",
    "#EEE1F8",
    "#F8DCE5",
    "#FFF1C9",
    "#DCEEEF"
  )
  cluster_cols <- if (length(cluster_values) <= length(light_palette)) {
    light_palette[seq_along(cluster_values)]
  } else {
    grDevices::hcl.colors(length(cluster_values), palette = "Pastel 1")
  }

  stats::setNames(cluster_cols, cluster_values)
}

design_diagnostic_point_fill <- function(sample_table, cluster_lookup) {
  fills <- rep("#FFFFFF", nrow(sample_table))
  if (!("cluster" %in% names(sample_table)) || length(cluster_lookup) == 0) {
    return(fills)
  }

  matched_cols <- unname(cluster_lookup[as.character(sample_table$cluster)])
  fills[!is.na(matched_cols)] <- matched_cols[!is.na(matched_cols)]
  fills
}

design_diagnostic_title <- function(farm_id) {
  farm_label <- gsub("[_-]+", " ", farm_id)
  sprintf("%s Cluster Map With Sample Overlay", tools::toTitleCase(farm_label))
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

  cluster_values <- sort(unique(stats::na.omit(as.integer(terra::values(design$cluster_raster)[, 1]))))
  cluster_lookup <- design_diagnostic_palette(cluster_values)
  cluster_cols <- unname(cluster_lookup)
  sample_table <- terra::as.data.frame(design$samples)
  sample_coords <- terra::crds(design$samples)
  point_fill <- design_diagnostic_point_fill(sample_table, cluster_lookup)

  grDevices::png(diagnostic_path, width = 1800, height = 1400, res = 200, family = "Arial")
  old_par <- graphics::par(no.readonly = TRUE)
  on.exit({
    graphics::par(old_par)
    grDevices::dev.off()
  }, add = TRUE)
  graphics::par(mar = c(4.5, 4.5, 4, 8), xpd = NA, family = "Arial")
  terra::plot(
    design$cluster_raster,
    type = "classes",
    col = cluster_cols,
    main = design_diagnostic_title(farm_id),
    axes = TRUE,
    box = FALSE,
    legend = FALSE
  )
  graphics::points(
    sample_coords[, 1],
    sample_coords[, 2],
    pch = 21,
    bg = point_fill,
    col = "black",
    cex = 1.2,
    lwd = 0.8
  )
  if ("sample_id" %in% names(sample_table)) {
    graphics::text(
      sample_coords[, 1],
      sample_coords[, 2],
      labels = sample_table$sample_id,
      pos = 3,
      offset = 0.45,
      cex = 0.65,
      col = "black"
    )
  }
  raster_extent <- as.vector(terra::ext(design$cluster_raster))
  legend_x <- raster_extent[1] + 0.03 * (raster_extent[2] - raster_extent[1])
  legend_y <- raster_extent[4] - 0.02 * (raster_extent[4] - raster_extent[3])
  graphics::legend(
    x = legend_x,
    y = legend_y,
    legend = paste("Cluster", cluster_values),
    fill = cluster_cols,
    border = NA,
    bty = "n",
    xjust = 0,
    yjust = 1,
    cex = 0.9,
    title = "Raster classes"
  )

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
