# Contours Legacy Samples Design

## Goal

Extend the existing sampling workflow so a run can optionally include a CSV of legacy sample points, enforce `min_point_spacing_m` against those existing locations, generate the requested number of new points in addition to the legacy points, and write one combined delivered sample set.

## Decisions

- Add an optional `legacy_samples_path` field to YAML configs.
- If `legacy_samples_path` is absent, the workflow behaves exactly as it does today.
- If `legacy_samples_path` is present, `sample_count` continues to mean the number of new points to generate.
- Legacy points are treated as fixed occupied locations during selection, so new points must satisfy `min_point_spacing_m` against both legacy points and newly selected points.
- Final outputs contain both legacy and new points in one combined dataset.
- Legacy rows retain their existing `sample_id` values from the input CSV.
- New rows continue to use generated sample IDs from the current workflow.
- Combined outputs include a `sample_source` field with values `legacy` and `new`.
- Legacy points are validated against the farm polygon, but the inward buffer is only applied to new candidate generation.
- Legacy covariates, projected coordinates, and cluster membership are re-derived from the current analysis stack so the combined output schema stays consistent.
- Cluster summary outputs count the full delivered sample set rather than only the newly generated subset.

## Required Legacy CSV Schema

The optional legacy CSV must provide:

- `sample_id`
- `x`
- `y`

The `x` and `y` columns are interpreted as longitude and latitude in the same geographic CRS used by current sample outputs.

Extra columns may be present, but the workflow only depends on the required fields above.

## Data Flow

1. Config loading resolves and validates `legacy_samples_path` when present.
2. The legacy CSV is read into a normalized table and converted into point geometry.
3. Legacy points are checked for missing coordinates, duplicated `sample_id` values, and farm inclusion.
4. The analysis stack is converted into sampling candidates as it is today.
5. Candidate selection uses the legacy point locations as pre-existing occupied coordinates when enforcing `min_point_spacing_m`.
6. The workflow generates exactly `sample_count` new points, not counting any legacy rows.
7. Legacy points are enriched from the current stack so the combined output contains consistent coordinates, covariates, and cluster assignments.
8. New and legacy rows are merged into one final sample table and one final point layer.
9. Output writers serialize the combined sample set and updated summaries and diagnostics.

## Failure Handling

- Fail early if `legacy_samples_path` does not exist or cannot be read.
- Fail early if the legacy CSV is missing `sample_id`, `x`, or `y`.
- Fail early if any legacy row has missing or non-numeric coordinates.
- Fail early if any legacy `sample_id` values are duplicated.
- Fail early if any legacy point falls outside the farm polygon.
- Fail early if spacing constraints against legacy points make the requested number of new points impossible.
- Keep the current failures for impossible buffer, missing stack, or insufficient candidate points.

## Code Integration

- `R/config.R`
  - Add optional config support for `legacy_samples_path`.
  - Resolve the path relative to the YAML file location.
  - Validate it only when provided.
- `R/io_spatial.R`
  - Add a reader for the legacy CSV that returns a validated point table and spatial object.
- `R/pca_sampling.R`
  - Update spacing-aware sample selection to respect legacy points.
  - Enrich legacy rows from the current stack and fitted PCA plus cluster model.
  - Return combined sample outputs with `sample_source`.
- `R/output_reports.R`
  - Write combined vectors and tables.
  - Summarize all delivered samples by cluster.
  - Plot both legacy and new points in diagnostics.
- `scripts/design_samples.R`
  - Consume the optional legacy input through the resolved config with no new CLI flags.
- `scripts/run_pipeline.R`
  - Consume the optional legacy input through the resolved config with no new CLI flags.
- `config/contours_config.yml`
  - Provide the contour example using the new optional field.
- `README.md`
  - Document the optional legacy-sample workflow and clarify that `sample_count` refers to newly generated points when legacy samples are supplied.

## Testing

- Add config tests for optional `legacy_samples_path` parsing and validation.
- Add legacy CSV I/O tests for valid input and malformed input.
- Add sampling tests proving new points respect spacing against legacy points.
- Add sampling tests proving final output count equals `sample_count + n_legacy`.
- Add output tests proving combined outputs preserve legacy IDs and include `sample_source`.
- Update or add example config coverage for the contour workflow.

## Contours Example

For the Contours run:

- `sample_count: 8` means eight newly generated points.
- `legacy_samples_path` points to `specs/Contours_samples_legacy.csv`.
- The four legacy rows remain in the final delivered dataset.
- Final outputs therefore contain 12 total points.
