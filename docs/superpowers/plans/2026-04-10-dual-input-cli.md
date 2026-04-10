# Dual-Input CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dual-input CLI that accepts either a farm polygon or a YAML config, persist generated configs for polygon-driven runs, and make the GEE bridge work with older `reticulate` versions.

**Architecture:** Centralize input resolution and config generation in `R/config.R` so the three CLI scripts remain thin wrappers. Keep the GEE compatibility logic isolated in `R/gee_bridge.R` behind small helper functions so unit tests can verify the behavior without requiring live package installs.

**Tech Stack:** R, testthat, yaml, terra, reticulate

---

### Task 1: Cover input resolution with tests

**Files:**
- Modify: `tests/testthat/test-config.R`

- [ ] **Step 1: Write failing tests for polygon input resolution and generated config persistence**
- [ ] **Step 2: Run the config tests and verify they fail for the new expectations**
- [ ] **Step 3: Implement the minimal config helpers in `R/config.R`**
- [ ] **Step 4: Run the config tests and verify they pass**

### Task 2: Cover reticulate compatibility with tests

**Files:**
- Create: `tests/testthat/test-gee-bridge.R`
- Modify: `R/gee_bridge.R`

- [ ] **Step 1: Write failing tests for `py_require()` detection and fallback selection**
- [ ] **Step 2: Run the gee bridge tests and verify they fail**
- [ ] **Step 3: Implement the minimal compatibility helpers**
- [ ] **Step 4: Run the gee bridge tests and verify they pass**

### Task 3: Wire the new CLI path through the scripts

**Files:**
- Modify: `scripts/prepare_covariates.R`
- Modify: `scripts/design_samples.R`
- Modify: `scripts/run_pipeline.R`
- Create: `scripts/build_config.R`

- [ ] **Step 1: Update headers and usage strings**
- [ ] **Step 2: Replace direct config loading with shared input resolution**
- [ ] **Step 3: Add the standalone config builder script**
- [ ] **Step 4: Run targeted smoke checks for the scripts**

### Task 4: Refresh documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Move configuration earlier in the README**
- [ ] **Step 2: Document shapefile-first usage and generated config behavior**
- [ ] **Step 3: Keep YAML usage as the explicit reusable mode**

### Task 5: Verification

**Files:**
- Modify: `R/config.R`
- Modify: `R/gee_bridge.R`
- Modify: `scripts/prepare_covariates.R`
- Modify: `scripts/design_samples.R`
- Modify: `scripts/run_pipeline.R`
- Create: `scripts/build_config.R`
- Modify: `README.md`
- Modify: `tests/testthat/test-config.R`
- Create: `tests/testthat/test-gee-bridge.R`

- [ ] **Step 1: Run targeted tests for config and gee bridge behavior**
- [ ] **Step 2: Run the full test suite**
- [ ] **Step 3: Run a CLI smoke check for `build_config.R` with the bundled example polygon**
