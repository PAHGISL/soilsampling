#!/usr/bin/env Rscript
# Script: testthat.R
# Objective: Run the soilsampling test suite.
# Author: Yi Yu
# Created: 2026-04-10
# Last updated: 2026-04-10
# Inputs: Repository source files and test fixtures under tests/testthat.
# Outputs: Console test results and process exit status.
# Usage: Rscript tests/testthat.R
# Dependencies: R packages testthat

testthat::test_dir(
  "tests/testthat",
  reporter = testthat::SummaryReporter$new(),
  stop_on_failure = TRUE
)

