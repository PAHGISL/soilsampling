select_pca_components <- function(pca, variance_threshold, max_components = NULL) {
  explained <- cumsum((pca$sdev ^ 2) / sum(pca$sdev ^ 2))
  selected <- which(explained >= variance_threshold)[1]

  if (is.na(selected)) {
    selected <- length(explained)
  }
  if (!is.null(max_components)) {
    selected <- min(selected, as.integer(max_components))
  }

  as.integer(selected)
}

allocate_cluster_samples <- function(cluster_sizes, sample_count) {
  cluster_sizes <- as.numeric(cluster_sizes)
  populated <- cluster_sizes > 0

  if (!all(populated)) {
    cluster_sizes <- cluster_sizes[populated]
  }
  if (sample_count < length(cluster_sizes)) {
    stop("sample_count must be at least the number of populated clusters.", call. = FALSE)
  }

  weights <- cluster_sizes / sum(cluster_sizes)
  allocation <- rep(1L, length(cluster_sizes))
  remaining <- as.integer(sample_count - sum(allocation))

  if (remaining > 0L) {
    quota <- weights * remaining
    allocation <- allocation + floor(quota)
    leftovers <- as.integer(sample_count - sum(allocation))

    if (leftovers > 0L) {
      order_idx <- order(quota - floor(quota), decreasing = TRUE)
      for (idx in seq_len(leftovers)) {
        allocation[order_idx[idx]] <- allocation[order_idx[idx]] + 1L
      }
    }
  }

  allocation
}

select_spaced_samples <- function(candidates, n, min_spacing_m, seed) {
  if (nrow(candidates) < n) {
    stop("Not enough candidate points to sample from.", call. = FALSE)
  }

  set.seed(seed)
  order_idx <- sample(seq_len(nrow(candidates)))
  selected_idx <- integer(0)

  for (idx in order_idx) {
    if (length(selected_idx) == 0L) {
      selected_idx <- c(selected_idx, idx)
    } else {
      dx <- candidates$x_proj[selected_idx] - candidates$x_proj[idx]
      dy <- candidates$y_proj[selected_idx] - candidates$y_proj[idx]
      if (all(sqrt(dx ^ 2 + dy ^ 2) >= min_spacing_m)) {
        selected_idx <- c(selected_idx, idx)
      }
    }

    if (length(selected_idx) == n) {
      break
    }
  }

  if (length(selected_idx) < n) {
    stop("Unable to satisfy the minimum point spacing with the available candidates.", call. = FALSE)
  }

  candidates[selected_idx, , drop = FALSE]
}

stack_to_feature_table <- function(stack) {
  terra::as.data.frame(stack, xy = TRUE, cells = TRUE, na.rm = TRUE)
}

covariate_columns <- function(feature_table) {
  excluded <- c("cell", "x", "y", "x_proj", "y_proj", "cluster", "sample_id")
  setdiff(names(feature_table), excluded)
}

drop_zero_variance_covariates <- function(feature_table, feature_cols) {
  variances <- vapply(
    feature_table[, feature_cols, drop = FALSE],
    stats::var,
    numeric(1),
    na.rm = TRUE
  )

  feature_cols[is.finite(variances) & variances > 0]
}

farm_utm_crs <- function(farm) {
  centroid <- terra::centroids(terra::project(farm, "EPSG:4326"))
  coords <- terra::crds(centroid)
  zone <- floor((coords[1, 1] + 180) / 6) + 1
  epsg <- if (coords[1, 2] >= 0) {
    32600 + zone
  } else {
    32700 + zone
  }

  paste0("EPSG:", epsg)
}

buffer_candidate_features <- function(feature_table, farm, buffer_distance_m, stack_crs) {
  feature_table$point_id <- seq_len(nrow(feature_table))

  points_ll <- terra::vect(feature_table, geom = c("x", "y"), crs = stack_crs, keepgeom = TRUE)
  target_crs <- farm_utm_crs(farm)
  points_proj <- terra::project(points_ll, target_crs)
  farm_proj <- terra::project(farm, target_crs)

  if (buffer_distance_m > 0) {
    farm_proj <- terra::buffer(farm_proj, width = -buffer_distance_m)
    if (nrow(farm_proj) == 0) {
      stop("buffer_distance_m removes the entire farm extent.", call. = FALSE)
    }
  }

  candidate_points <- points_proj[farm_proj]
  if (nrow(candidate_points) == 0) {
    stop("No candidate points remain after buffering the farm polygon.", call. = FALSE)
  }

  point_lookup <- feature_table[match(candidate_points$point_id, feature_table$point_id), , drop = FALSE]
  coords_proj <- terra::crds(candidate_points)
  point_lookup$x_proj <- coords_proj[, 1]
  point_lookup$y_proj <- coords_proj[, 2]

  point_lookup
}

build_cluster_raster <- function(template, feature_table) {
  cluster_raster <- template[[1]]
  cluster_values <- rep(NA_integer_, terra::ncell(cluster_raster))
  cluster_values[feature_table$cell] <- as.integer(feature_table$cluster)
  terra::values(cluster_raster) <- cluster_values
  names(cluster_raster) <- "cluster"
  cluster_raster
}

sample_cluster_points <- function(candidate_features, allocation, cfg) {
  split_candidates <- split(candidate_features, candidate_features$cluster)
  sampled <- vector("list", length(split_candidates))

  for (idx in seq_along(split_candidates)) {
    sampled[[idx]] <- select_spaced_samples(
      candidates = split_candidates[[idx]],
      n = allocation[[idx]],
      min_spacing_m = cfg$min_point_spacing_m,
      seed = cfg$random_seed + idx
    )
  }

  do.call(rbind, sampled)
}

design_samples_from_stack <- function(stack, farm, cfg) {
  feature_table <- stack_to_feature_table(stack)
  candidate_features <- buffer_candidate_features(
    feature_table = feature_table,
    farm = farm,
    buffer_distance_m = cfg$buffer_distance_m,
    stack_crs = terra::crs(stack)
  )

  feature_cols <- covariate_columns(candidate_features)
  feature_cols <- drop_zero_variance_covariates(candidate_features, feature_cols)
  if (length(feature_cols) == 0) {
    stop("No non-constant covariates remain after masking and buffering.", call. = FALSE)
  }

  pca <- stats::prcomp(candidate_features[, feature_cols, drop = FALSE], center = TRUE, scale. = TRUE)
  selected_components <- select_pca_components(
    pca = pca,
    variance_threshold = cfg$pca$variance_threshold,
    max_components = cfg$pca$max_components
  )

  scores <- pca$x[, seq_len(selected_components), drop = FALSE]
  set.seed(cfg$random_seed)
  km <- stats::kmeans(scores, centers = cfg$cluster_count, nstart = 25)
  candidate_features$cluster <- km$cluster

  cluster_sizes <- as.integer(table(candidate_features$cluster))
  allocation <- allocate_cluster_samples(cluster_sizes, cfg$sample_count)
  sampled <- sample_cluster_points(candidate_features, allocation, cfg)
  sampled <- sampled[order(sampled$cluster, sampled$point_id), , drop = FALSE]
  sampled$sample_id <- sprintf("S%02d", seq_len(nrow(sampled)))

  sample_points <- terra::vect(sampled, geom = c("x", "y"), crs = terra::crs(stack), keepgeom = TRUE)
  cluster_raster <- build_cluster_raster(stack, candidate_features)

  list(
    samples = sample_points,
    sampled_table = sampled,
    cluster_raster = cluster_raster,
    pca = pca,
    selected_components = selected_components
  )
}
