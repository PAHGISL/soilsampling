#!/usr/bin/env Rscript
# Script: prepare_covariates.R
# Objective: Download and prepare a masked analysis covariate stack for a farm polygon.
# Author: Yi Yu
# Created: 2026-04-10
# Last updated: 2026-04-10
# Inputs: Farm polygon path or YAML config path, Earth Engine credentials, downloader script.
# Outputs: Raw downloads, YAML request files, prepared analysis stack, run summary JSON.
# Usage: Rscript scripts/prepare_covariates.R <farm_polygon_or_config.yml>
# Dependencies: R packages jsonlite, yaml, terra, reticulate; python/gee_downloader.py

source_repo_files <- function(repo_root) {
  r_files <- list.files(file.path(repo_root, "R"), pattern = "[.][Rr]$", full.names = TRUE)
  for (path in sort(r_files)) {
    sys.source(path, envir = globalenv())
  }
}

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1) {
  stop("Usage: Rscript scripts/prepare_covariates.R <farm_polygon_or_config.yml>", call. = FALSE)
}

source_repo_files(repo_root)

resolved_input <- resolve_config_input(args[[1]], repo_root = repo_root)
cfg <- resolved_input$cfg
if (resolved_input$generated) {
  message("Generated config at ", resolved_input$config_path)
}

require_gee_project_id(cfg)
farm <- read_farm_polygon(cfg$farm_path)
dirs <- initialise_run_dirs(cfg$output_dir)
plan <- build_covariate_plan(cfg, farm, dirs$raw)

raster_paths <- execute_covariate_plan(
  plan = plan,
  python_script = file.path(repo_root, "python", "gee_downloader.py")
)

analysis_stack_path <- file.path(dirs$processed, "analysis_stack.tif")
analysis_stack <- align_and_mask_stack(raster_paths, farm, analysis_stack_path)

jsonlite::write_json(
  list(
    farm_path = cfg$farm_path,
    output_dir = cfg$output_dir,
    config_path = resolved_input$config_path,
    analysis_stack = analysis_stack_path,
    raster_paths = raster_paths,
    n_layers = terra::nlyr(analysis_stack)
  ),
  path = file.path(dirs$reports, "prepare_covariates.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)

message("Prepared analysis stack at ", analysis_stack_path)
