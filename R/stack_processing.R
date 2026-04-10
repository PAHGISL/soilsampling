align_single_raster <- function(x, template) {
  if (isTRUE(terra::compareGeom(x, template, stopOnError = FALSE))) {
    return(x)
  }

  x <- terra::project(x, template, method = "bilinear")
  terra::resample(x, template, method = "bilinear")
}

derive_covariates <- function(stack) {
  if ("terrain_elevation" %in% names(stack) && !("terrain_slope" %in% names(stack))) {
    slope <- terra::terrain(stack[["terrain_elevation"]], v = "slope", unit = "degrees")
    names(slope) <- "terrain_slope"
    stack <- c(stack, slope)
  }

  if ("terrain_elevation" %in% names(stack) && !("terrain_aspect" %in% names(stack))) {
    aspect <- terra::terrain(stack[["terrain_elevation"]], v = "aspect", unit = "degrees")
    names(aspect) <- "terrain_aspect"
    stack <- c(stack, aspect)
  }

  if ("terrain_aspect" %in% names(stack)) {
    aspect_radians <- stack[["terrain_aspect"]] * pi / 180
    aspect_sin <- sin(aspect_radians)
    aspect_cos <- cos(aspect_radians)
    names(aspect_sin) <- "aspect_sin"
    names(aspect_cos) <- "aspect_cos"
    stack <- c(stack, aspect_sin, aspect_cos)
    stack <- stack[[!names(stack) %in% "terrain_aspect"]]
  }

  if (all(c("B8", "B4") %in% names(stack)) && !("spectral_ndvi" %in% names(stack))) {
    ndvi <- (stack[["B8"]] - stack[["B4"]]) / (stack[["B8"]] + stack[["B4"]])
    names(ndvi) <- "spectral_ndvi"
    stack <- c(stack, ndvi)
  }

  if (all(c("VV", "VH") %in% names(stack)) && !("radar_vv_vh_ratio" %in% names(stack))) {
    ratio <- stack[["VV"]] - stack[["VH"]]
    names(ratio) <- "radar_vv_vh_ratio"
    stack <- c(stack, ratio)
  }

  stack
}

align_and_mask_stack <- function(raster_paths, farm, output_path) {
  if (length(raster_paths) == 0) {
    stop("Provide at least one raster path.", call. = FALSE)
  }

  template <- terra::rast(raster_paths[[1]])
  farm_template <- terra::project(farm, terra::crs(template))

  aligned_layers <- lapply(raster_paths, function(path) {
    align_single_raster(terra::rast(path), template)
  })

  stack <- aligned_layers[[1]]
  if (length(aligned_layers) > 1) {
    for (idx in 2:length(aligned_layers)) {
      stack <- c(stack, aligned_layers[[idx]])
    }
  }

  stack <- derive_covariates(stack)
  stack <- terra::crop(stack, farm_template, snap = "out")
  stack <- terra::mask(stack, farm_template)

  dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(stack, output_path, overwrite = TRUE)

  stack
}
