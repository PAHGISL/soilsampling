#!/usr/bin/env Rscript
# Script: build_config.R
# Objective: Build a reusable pipeline YAML config from a farm polygon path.
# Author: Yi Yu
# Created: 2026-04-10
# Last updated: 2026-04-10
# Inputs: Farm polygon path and optional output YAML path.
# Outputs: YAML config file for a future pipeline run.
# Usage: Rscript scripts/build_config.R <farm_polygon> [output_config.yml]
# Dependencies: R packages terra, yaml

source_repo_files <- function(repo_root) {
  r_files <- list.files(file.path(repo_root, "R"), pattern = "[.][Rr]$", full.names = TRUE)
  for (path in sort(r_files)) {
    sys.source(path, envir = globalenv())
  }
}

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])
repo_root <- normalizePath(file.path(dirname(script_path), ".."), winslash = "/", mustWork = TRUE)

args <- commandArgs(trailingOnly = TRUE)
if (!(length(args) %in% c(1, 2))) {
  stop("Usage: Rscript scripts/build_config.R <farm_polygon> [output_config.yml]", call. = FALSE)
}

source_repo_files(repo_root)

farm_path <- resolve_existing_input_path(args[[1]], repo_root = repo_root)
if (is_yaml_config_path(farm_path)) {
  stop("build_config.R expects a farm polygon path, not a YAML config.", call. = FALSE)
}

cfg <- build_config_from_farm_path(
  farm_path = farm_path,
  output_root = file.path(repo_root, "outputs")
)
invisible(read_farm_polygon(cfg$farm_path))

if (length(args) == 2) {
  config_path <- args[[2]]
  if (!grepl("^(/|[A-Za-z]:[/\\\\])", config_path)) {
    config_path <- file.path(repo_root, config_path)
  }
} else {
  config_path <- file.path(cfg$output_dir, "reports", "auto_config.yml")
}

config_path <- write_pipeline_config(cfg, config_path)

message("Wrote config to ", config_path)
