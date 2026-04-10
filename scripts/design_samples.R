#!/usr/bin/env Rscript
# Script: design_samples.R
# Objective: Generate PCA plus k-means sampling outputs from a prepared analysis stack.
# Author: Yi Yu
# Created: 2026-04-10
# Last updated: 2026-04-10
# Inputs: YAML config path, prepared analysis stack, farm polygon.
# Outputs: Cluster raster and serialized sampling design results.
# Usage: Rscript scripts/design_samples.R config/example_nowley.yml
# Dependencies: R packages jsonlite, terra

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
  stop("Usage: Rscript scripts/design_samples.R <config.yml>", call. = FALSE)
}

source_repo_files(repo_root)

config_path <- normalizePath(file.path(repo_root, args[[1]]), winslash = "/", mustWork = TRUE)
cfg <- load_config(config_path)
farm <- read_farm_polygon(cfg$farm_path)
dirs <- initialise_run_dirs(cfg$output_dir)
stack_path <- file.path(dirs$processed, "analysis_stack.tif")

if (!file.exists(stack_path)) {
  stop("Prepared analysis stack does not exist: ", stack_path, call. = FALSE)
}

design <- design_samples_from_stack(terra::rast(stack_path), farm, cfg)
outputs <- write_design_outputs(
  design = design,
  dirs = dirs,
  farm_id = tools::file_path_sans_ext(basename(cfg$farm_path))
)
saveRDS(design, file = file.path(dirs$reports, "sampling_design.rds"))

message("Wrote sampling design outputs to ", outputs$summary)
