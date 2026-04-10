#!/usr/bin/env Rscript
# Script: run_pipeline.R
# Objective: Run the soilsampling covariate preparation and sample design workflow end to end.
# Author: Yi Yu
# Created: 2026-04-10
# Last updated: 2026-04-10
# Inputs: YAML config path, farm polygon, Earth Engine credentials.
# Outputs: Prepared stack, cluster raster, and serialized design outputs.
# Usage: Rscript scripts/run_pipeline.R config/example_nowley.yml
# Dependencies: R packages jsonlite, terra, yaml, reticulate; python/gee_downloader.py

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
  stop("Usage: Rscript scripts/run_pipeline.R <config.yml>", call. = FALSE)
}

source_repo_files(repo_root)

config_path <- normalizePath(file.path(repo_root, args[[1]]), winslash = "/", mustWork = TRUE)
cfg <- load_config(config_path)
farm <- read_farm_polygon(cfg$farm_path)
dirs <- initialise_run_dirs(cfg$output_dir)

plan <- build_covariate_plan(cfg, farm, dirs$raw)
raster_paths <- execute_covariate_plan(
  plan = plan,
  python_script = file.path(repo_root, "python", "gee_downloader.py")
)

analysis_stack_path <- file.path(dirs$processed, "analysis_stack.tif")
analysis_stack <- align_and_mask_stack(raster_paths, farm, analysis_stack_path)
design <- design_samples_from_stack(analysis_stack, farm, cfg)
outputs <- write_design_outputs(
  design = design,
  dirs = dirs,
  farm_id = tools::file_path_sans_ext(basename(cfg$farm_path))
)
saveRDS(design, file = file.path(dirs$reports, "pipeline_result.rds"))

write_run_summary_json(
  summary = list(
    analysis_stack = analysis_stack_path,
    sample_count = nrow(design$sampled_table),
    outputs = outputs
  ),
  path = file.path(dirs$reports, "run_pipeline.json")
)

message("Pipeline run complete in ", dirs$root)
