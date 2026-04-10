testthat::test_that("ensure_reticulate_python_packages uses py_require when available", {
  branch <- ensure_reticulate_python_packages(
    packages = c("earthengine-api"),
    has_py_require = function() TRUE,
    py_require_fn = function(packages, action) {
      testthat::expect_equal(packages, c("earthengine-api"))
      testthat::expect_equal(action, "set")
      invisible(NULL)
    },
    py_install_fn = function(...) {
      testthat::fail("py_install fallback should not be used when py_require is available.")
    }
  )

  testthat::expect_equal(branch, "py_require")
})

testthat::test_that("ensure_reticulate_python_packages falls back to py_install when py_require is unavailable", {
  branch <- ensure_reticulate_python_packages(
    packages = c("earthengine-api"),
    has_py_require = function() FALSE,
    py_require_fn = function(...) {
      testthat::fail("py_require should not be called when it is unavailable.")
    },
    py_install_fn = function(packages, envname, method, pip) {
      testthat::expect_equal(packages, c("earthengine-api"))
      testthat::expect_equal(envname, legacy_reticulate_envname())
      testthat::expect_equal(method, "auto")
      testthat::expect_true(pip)
      invisible(NULL)
    }
  )

  testthat::expect_equal(branch, "py_install")
})
