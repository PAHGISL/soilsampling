# Soil Sampling Design Pipeline

[![R 4.3.1](https://img.shields.io/badge/R-4.3.1-276DC3?style=flat&logo=R&logoColor=white)](https://www.r-project.org/)
[![Google Earth Engine](https://img.shields.io/badge/Google%20Earth%20Engine-Workflow-34A853?style=flat&logo=googleearthengine&logoColor=white)](https://earthengine.google.com/)
[![University of Sydney](https://img.shields.io/badge/The%20University%20of%20Sydney-Profile-B7452B?style=flat)](https://profiles.sydney.edu.au/yi.yu1)

## Contents

- [Repository structure](#repository-structure)
- [Overview](#overview)
- [Workflow](#workflow)
- [Configuration](#configuration)
- [Outputs](#outputs)
- [Testing](#testing)
- [Current scope](#current-scope)

## Repository structure

The current repository layout is:

```text
soilsampling/
├── R/                               Reusable pipeline modules
│   ├── config.R                     Config defaults, parsing, and validation
│   ├── covariates.R                 GEE covariate plans and download orchestration
│   ├── gee_bridge.R                 R bridge to the Python Earth Engine downloader
│   ├── io_spatial.R                 Farm polygon reading and validation
│   ├── output_reports.R             Output writers and diagnostic reporting
│   ├── pca_sampling.R               PCA, clustering, and sample selection logic
│   └── stack_processing.R           Raster alignment, masking, and derived covariates
├── config/
│   └── example_nowley.yml           Example run configuration using the bundled Nowley polygon
├── inst/
│   └── example/nowley/              Example farm polygon assets
├── python/
│   ├── gee_downloader.py            Earth Engine download backend
│   └── requirements-gee.txt         Python package requirements for the downloader
├── scripts/
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

## Overview

`soilsampling` is a reusable pipeline for generating soil sampling designs from user-provided farm polygons. The project was refactored from a legacy workflow under `archive/sampling_plan` into a cleaner repository that:

- removes the `dataharvester` dependency
- uses a smaller Google Earth Engine-first covariate stack
- prepares an analysis-ready raster stack for an arbitrary farm polygon
- applies `PCA + k-means` to define environmental strata
- selects buffered sample points with a minimum spacing rule

The repository is R-first, with Python limited to the Earth Engine download backend.

## Workflow

The standard workflow has two explicit stages plus a wrapper:

1. `scripts/prepare_covariates.R`
   Reads the farm polygon, builds the requested GEE covariate plan, downloads source rasters, aligns them to a common grid, derives secondary layers, and writes `processed/analysis_stack.tif`.

2. `scripts/design_samples.R`
   Reads the prepared stack, drops constant covariates, runs PCA, performs `k-means` clustering in PCA space, applies buffer and spacing constraints, and writes sample outputs plus diagnostics.

3. `scripts/run_pipeline.R`
   Runs both stages end to end.

For the bundled example, run from the repository root:

```bash
Rscript scripts/prepare_covariates.R config/example_nowley.yml
Rscript scripts/design_samples.R config/example_nowley.yml
```

Or run the full pipeline in one step:

```bash
Rscript scripts/run_pipeline.R config/example_nowley.yml
```

## Configuration

The example configuration file is:

```text
config/example_nowley.yml
```

The main inputs are:

- `farm_path`: polygon file to sample within
- `output_dir`: run directory for rasters, vectors, tables, and reports
- `gee_project_id`: Google Cloud project ID for Earth Engine
- `sample_count`: number of final sample points
- `cluster_count`: number of PCA-space strata
- `buffer_distance_m`: inward buffer used before candidate selection
- `min_point_spacing_m`: minimum spacing between selected sample points
- `random_seed`: seed for reproducibility
- `date_window`: temporal window for imagery-based covariates

The bundled example points to:

```text
inst/example/nowley/Nowley.shp
```

Earth Engine authentication is handled through the R bridge and Python downloader. On first use, authentication may require an interactive browser step.

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
