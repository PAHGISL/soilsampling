# Soil sampling design pipeline

[![R 4.3.1](https://img.shields.io/badge/R-4.3.1-276DC3?style=flat&logo=R&logoColor=white)](https://www.r-project.org/)
[![Google Earth Engine](https://img.shields.io/badge/Google%20Earth%20Engine-Workflow-34A853?style=flat&logo=googleearthengine&logoColor=white)](https://earthengine.google.com/)
[![University of Sydney](https://img.shields.io/badge/The%20University%20of%20Sydney-Profile-B7452B?style=flat)](https://profiles.sydney.edu.au/yi.yu1)

## Contents

- [Overview](#overview)
- [Configuration](#configuration)
- [Workflow](#workflow)
- [Repository structure](#repository-structure)
- [Outputs](#outputs)
- [Testing](#testing)
- [Current scope](#current-scope)

## Overview

`soilsampling` is a reusable pipeline for generating soil sampling designs from user-provided farm polygons. The project was refactored from a legacy workflow under `archive/sampling_plan` into a cleaner repository that:

- removes the `dataharvester` dependency
- uses a smaller Google Earth Engine-first covariate stack
- prepares an analysis-ready raster stack for an arbitrary farm polygon
- applies `PCA + k-means` to define environmental strata
- selects buffered sample points with a minimum spacing rule

The repository is R-first, with Python limited to the Earth Engine download backend.

## Configuration

Configuration is now the main entrypoint to the workflow.

Each pipeline script accepts either:

- a farm polygon path, for example `inst/example/nowley/Nowley.shp`
- a pre-written YAML config, for example `config/example_nowley.yml`

The shapefile-first workflow is the recommended default because it requires less setup. When you pass a farm polygon path, the script automatically builds a run config from the repository defaults, writes that config to `reports/auto_config.yml` inside the run output directory, and then continues with the pipeline.

If you use shapefile input for a download stage, you must also provide the Google Earth Engine project ID through the environment:

```bash
export GEE_PROJECT_ID="your-google-cloud-project-id"
Rscript scripts/prepare_covariates.R path/to/farm.shp
```

Or as a one-line command:

```bash
GEE_PROJECT_ID="your-google-cloud-project-id" Rscript scripts/run_pipeline.R path/to/farm.shp
```

`scripts/design_samples.R` does not need `GEE_PROJECT_ID` if the prepared raster stack already exists. `scripts/prepare_covariates.R` and `scripts/run_pipeline.R` do need it because they trigger Earth Engine downloads.

If you want to materialize the generated config without running the full pipeline, use:

```bash
Rscript scripts/build_config.R path/to/farm.shp
```

The generated run config is different from the internal downloader request files written under `raw/*/*_config.yaml`. Users edit or reuse the run config. The downloader request YAML files are generated automatically by the pipeline and should not be edited manually.

If you want to pin settings explicitly, create or edit a YAML config and pass that file to the scripts. The repository includes this example:

```text
config/example_nowley.yml
```

Use a YAML config when you want to pin settings explicitly or rerun the exact same setup later. The main fields are:

- `farm_path`: polygon file to sample within
- `output_dir`: run directory for rasters, vectors, tables, and reports
- `gee_project_id`: Google Cloud project ID for Earth Engine
- `sample_count`: number of final sample points
- `cluster_count`: number of PCA-space strata
- `buffer_distance_m`: inward buffer used before candidate selection
- `min_point_spacing_m`: minimum spacing between selected sample points
- `random_seed`: seed for reproducibility
- `date_window`: temporal window for imagery-based covariates

Earth Engine authentication is handled through the R bridge and Python downloader. On first use, authentication may require an interactive browser step.

## Workflow

Choose one of these workflows.

1. Stage-by-stage workflow.

`scripts/prepare_covariates.R` reads the farm polygon, builds the requested GEE covariate plan, downloads source rasters, aligns them to a common grid, derives secondary layers, and writes `processed/analysis_stack.tif`.

`scripts/design_samples.R` reads the prepared stack, drops constant covariates, runs PCA, performs `k-means` clustering in PCA space, applies buffer and spacing constraints, and writes sample outputs plus diagnostics.

Example with shapefile input:

```bash
export GEE_PROJECT_ID="your-google-cloud-project-id"
Rscript scripts/prepare_covariates.R path/to/farm.shp
Rscript scripts/design_samples.R path/to/farm.shp
```

2. End-to-end workflow.

`scripts/run_pipeline.R` runs both stages in one command.

Example with shapefile input:

```bash
GEE_PROJECT_ID="your-google-cloud-project-id" Rscript scripts/run_pipeline.R path/to/farm.shp
```

In both cases, you can replace the shapefile path with a YAML config path:

```bash
Rscript scripts/prepare_covariates.R path/to/config.yml
Rscript scripts/design_samples.R path/to/config.yml
```

or:

```bash
Rscript scripts/run_pipeline.R path/to/config.yml
```

## Repository structure

The current repository layout is:

```text
soilsampling/
├── R/                               Reusable pipeline modules
│   ├── config.R                     Config defaults, parsing, validation, and input resolution
│   ├── covariates.R                 GEE covariate plans and download orchestration
│   ├── gee_bridge.R                 R bridge to the Python Earth Engine downloader
│   ├── io_spatial.R                 Farm polygon reading and validation
│   ├── output_reports.R             Output writers and diagnostic reporting
│   ├── pca_sampling.R               PCA, clustering, and sample selection logic
│   └── stack_processing.R           Raster alignment, masking, and derived covariates
├── config/
│   └── example_nowley.yml           Example reusable run configuration using the bundled Nowley polygon
├── inst/
│   └── example/nowley/              Example farm polygon assets
├── python/
│   ├── gee_downloader.py            Earth Engine download backend
│   └── requirements-gee.txt         Python package requirements for the downloader
├── scripts/
│   ├── build_config.R               Materialize a reusable config from a farm polygon path
│   ├── prepare_covariates.R         Stage 1: download and prepare the analysis stack
│   ├── design_samples.R             Stage 2: run PCA and build the sample design
│   └── run_pipeline.R               Convenience wrapper for the full workflow
├── tests/
│   ├── testthat/                    Unit tests and synthetic fixtures
│   └── testthat.R                   Test runner
├── DESCRIPTION                      Package-style metadata
├── README.md                        Project overview and usage
└── .Rprofile                        Repo-local R defaults
```

## Outputs

Each run creates a stable directory tree under the configured `output_dir`, including:

- `raw/` for downloaded source rasters and YAML request files
- `processed/analysis_stack.tif` for the aligned covariate stack
- `processed/cluster_map.tif` for the final cluster raster
- `vectors/*.gpkg` and `vectors/*.shp` for sample points
- `tables/*_samples.csv` for tabular sample outputs
- `tables/*_cluster_summary.csv` for per-cluster sample counts
- `reports/design_diagnostics.png` for a quick diagnostic figure
- `reports/run_summary.json` for machine-readable run metadata

## Testing

Run the full test suite from the repository root:

```bash
Rscript tests/testthat.R
```

The current tests cover:

- config parsing and validation
- polygon input handling
- raster alignment and derived covariates
- PCA component selection and cluster allocation
- spacing-constrained point selection
- output writing and diagnostics

## Current scope

The repository currently focuses on a practical v1 workflow:

- a compact GEE-first baseline covariate stack
- a reusable polygon-driven interface
- deterministic tests using bundled and synthetic fixtures

The core R pipeline and output generation are verified locally. The live Earth Engine downloader path is implemented, but its full end-to-end success still depends on valid Earth Engine credentials and the availability of requested collections at runtime.
