repo_root <- normalizePath(file.path("..", ".."), winslash = "/", mustWork = TRUE)
r_files <- list.files(
  file.path(repo_root, "R"),
  pattern = "[.][Rr]$",
  full.names = TRUE
)

for (path in sort(r_files)) {
  sys.source(path, envir = globalenv())
}

