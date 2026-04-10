# Soil Sampling Pipeline Design

## Goal

Refactor the legacy `archive/sampling_plan` workflow into a new standalone repository at `/g/data/ym05/github/soilsampling` that supports arbitrary user-provided farm polygons, removes the `dataharvester` dependency, relies primarily on Google Earth Engine for covariates, and generates reproducible soil sampling designs using `PCA + k-means`.

## Context

The legacy workflow currently splits the job across:

- `/g/data/ym05/archive/sampling_plan/Soil_Sample_Design_Downloads_1.6.R`
- `/g/data/ym05/archive/sampling_plan/Soil_Sample_Design_1.5.R`
- multiple sourced helper scripts under `/g/data/ym05/archive/sampling_plan/05 Source`
- modern Earth Engine bridge utilities under `/g/data/ym05/archive/sampling_plan/utils`

The usable core behavior is:

1. prepare a farm extent
2. download and assemble covariates
3. reduce covariate dimensionality
4. stratify the farm
5. place sample points

The legacy implementation is tightly coupled to one workstation through `setwd()`, hard-coded OneDrive paths, sourced scripts with hidden globals, and `dataharvester`. The new repository should preserve the useful sampling logic while removing those coupling points.

## Scope

### In scope

- standalone repository under `/g/data/ym05/github`
- user interface driven by a provided farm polygon plus sampling parameters
- GEE-first covariate download and preparation
- reusable R modules with thin CLI scripts
- Python Earth Engine downloader retained as a helper backend
- PCA-based dimensionality reduction
- k-means stratification plus buffered sample selection
- example data using `/g/data/ym05/archive/sampling_plan/shapefile`
- automated tests for non-GEE core logic

### Out of scope for v1

- legacy `dataharvester` YAML compatibility
- dependence on legacy zone, region, aggname, samplecode, or zonecode metadata
- Australian local raster dependencies as core requirements
- mapview-heavy report generation
- preserving exact legacy file names or folder layout

## User-Facing Workflow

The repository will expose three scripts:

1. `scripts/prepare_covariates.R`
   Reads a farm polygon, validates geometry and CRS, builds the Earth Engine request configuration, downloads the baseline covariate stack, aligns rasters, and writes a single analysis-ready stack.

2. `scripts/design_samples.R`
   Reads the prepared stack, converts valid pixels into a feature table, scales continuous covariates, runs PCA, performs `k-means` clustering in PCA space, and selects sample points from an inward-buffered farm polygon.

3. `scripts/run_pipeline.R`
   Convenience wrapper that runs both stages end-to-end.

The runtime interface will require only:

- `farm_path`: polygon vector file path
- `output_dir`: run output directory
- `gee_project_id`: Google Cloud project for Earth Engine
- `sample_count`
- `cluster_count`
- `buffer_distance_m`
- `min_point_spacing_m`
- `random_seed`
- covariate time window settings
- optional PCA controls such as fixed component count or cumulative variance threshold

No legacy metadata fields such as `region`, `zone`, `zonecode`, `aggname`, or `samplecode` are required.

## Repository Structure

The repository will be R-first, with the GEE downloader kept in Python:

- `scripts/prepare_covariates.R`
- `scripts/design_samples.R`
- `scripts/run_pipeline.R`
- `R/config.R`
- `R/io_spatial.R`
- `R/gee_bridge.R`
- `R/covariates.R`
- `R/stack_processing.R`
- `R/pca_sampling.R`
- `R/output_reports.R`
- `python/gee_downloader.py`
- `inst/example/nowley/`
- `tests/testthat/`
- `config/example_nowley.yml`
- `README.md`

Responsibilities:

- `config.R`: parse YAML and CLI inputs, normalise defaults, validate required options
- `io_spatial.R`: read farm polygons, validate schema, repair simple geometry issues, transform CRS, and write outputs
- `gee_bridge.R`: adapt the refreshed helper from `archive/sampling_plan/utils`
- `covariates.R`: define the baseline Earth Engine covariate stack and config writers
- `stack_processing.R`: align rasters, crop and mask to the farm polygon, derive secondary layers, and build the analysis stack
- `pca_sampling.R`: feature scaling, PCA, cluster creation, buffered candidate filtering, and final point selection
- `output_reports.R`: export rasters, vectors, CSV summaries, and lightweight diagnostics

## Covariate Strategy

v1 will use a smaller modern GEE-first baseline stack rather than mirroring the legacy mixture of local Australian datasets.

Default baseline stack:

- terrain elevation
- terrain slope
- terrain aspect transformed into continuous sine/cosine representations
- terrain ruggedness or local relief metric
- Sentinel-2 dry-period composite bands and spectral indices
- optional Sentinel-1 VV/VH summary layers where available

Design rules:

- prefer globally available datasets from Earth Engine
- keep the default stack compact enough to remain operational for arbitrary farm polygons
- avoid categorical layers in v1 unless they are globally available and clearly useful
- structure the stack definition so alternate covariate recipes can be added later without changing the sampling code

## Data Flow

1. Read the farm polygon and transform it to `EPSG:4326` for GEE requests.
2. Create a run directory with stable subfolders for raw downloads, processed rasters, vectors, and reports.
3. Build Earth Engine configs from the farm extent plus requested covariate recipe.
4. Download raw rasters with the Python downloader through the R bridge.
5. Align all rasters to a common template grid and mask them to the farm polygon.
6. Convert aligned valid pixels into a feature table.
7. Scale continuous features and run PCA.
8. Choose PCA dimensions using a configured count or cumulative explained variance rule.
9. Cluster pixels in PCA space with `k-means`.
10. Apply an inward polygon buffer and minimum spacing constraints to derive valid sample candidates.
11. Select final sample points by cluster-balanced random sampling from buffered candidates.
12. Export final outputs and diagnostics.

## Sampling Method

The sampling method for v1 is intentionally simpler than the legacy FAMD workflow:

- use continuous covariates only by default
- standardise covariates before PCA
- perform PCA to reduce correlation and dimensionality
- run `k-means` on PCA scores
- allocate samples across clusters
- select points from the buffered interior while enforcing a minimum point spacing

This preserves the legacy idea of environmental stratification while replacing `FAMD` with a method better suited to a mostly continuous GEE-derived stack.

## Output Contract

Each run will write predictable outputs such as:

- `processed/analysis_stack.tif`
- `processed/pca_scores.tif`
- `processed/cluster_map.tif`
- `vectors/samples.gpkg`
- `vectors/samples.shp`
- `tables/samples.csv`
- `tables/cluster_summary.csv`
- `reports/design_diagnostics.png`
- `reports/run_summary.json`

The example Nowley farm polygon from `/g/data/ym05/archive/sampling_plan/shapefile/Nowley.shp` will be bundled as the reference example for documentation and smoke testing.

## Error Handling

The new repository should fail early and clearly for the problems that are currently implicit in the legacy scripts.

Expected validations:

- farm polygon file missing or unreadable
- non-polygon geometry or empty geometry
- invalid geometry that cannot be repaired safely
- output directory not writable
- Earth Engine project ID missing
- no imagery returned for requested date range
- aligned stack contains too few valid pixels after masking
- requested sample count exceeds the number of valid spaced candidates
- requested cluster count is incompatible with valid pixel count

Failure messages should explain both what failed and what the user should adjust.

## Testing Strategy

Testing should focus on deterministic core logic and avoid making the suite dependent on live Earth Engine requests.

Planned tests:

- config parsing and default resolution
- farm polygon validation and CRS handling
- raster alignment and masking on small local fixtures
- PCA dimension selection rules
- cluster allocation behavior
- minimum-spacing and buffer enforcement
- output table schema and sample ID generation

Test layers:

- `testthat` unit tests for R modules
- small local raster fixtures for stack and sampling tests
- one smoke-test config using the bundled Nowley example

Live GEE download testing should remain an opt-in smoke workflow rather than a mandatory local test.

## Migration Notes

The legacy repository pieces to mine directly are:

- farm polygon preparation pattern from `/g/data/ym05/archive/sampling_plan/Soil_Sample_Design_1.5.R`
- sample design intent from `/g/data/ym05/archive/sampling_plan/05 Source/NoFieldFAMD510Clustfunction_1.7.R`
- Earth Engine bridge utilities from `/g/data/ym05/archive/sampling_plan/utils/gee_bridge.R`
- Python downloader from `/g/data/ym05/archive/sampling_plan/utils/gee_downloader.py`

The main pieces to discard are:

- `dataharvester`
- hard-coded workstation paths
- sourced functions that rely on hidden globals
- legacy zone-specific assumptions

## Implementation Notes

Implementation should follow these constraints:

- new and revised scripts must use the required script header standard
- R style should remain base-R first
- avoid `setwd()`
- keep Python limited to Earth Engine download responsibilities
- use user-provided polygons as the only required spatial input

## Recommended Next Step

Create an implementation plan that builds the repository in small, testable tasks, starting with project scaffolding and the example-driven spatial I/O layer, then the GEE bridge and covariate preparation, then the PCA sampling engine, and finally the end-to-end wrapper and documentation.
