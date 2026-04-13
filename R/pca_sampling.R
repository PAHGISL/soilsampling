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

select_spaced_samples <- function(candidates, n, min_spacing_m, seed, occupied = NULL) {
  if (nrow(candidates) < n) {
    stop("Not enough candidate points to sample from.", call. = FALSE)
  }

  set.seed(seed)
  order_idx <- sample(seq_len(nrow(candidates)))
  selected_idx <- integer(0)
  occupied_x <- if (is.null(occupied) || nrow(occupied) == 0L) numeric(0) else occupied$x_proj
  occupied_y <- if (is.null(occupied) || nrow(occupied) == 0L) numeric(0) else occupied$y_proj

  for (idx in order_idx) {
    all_x <- c(occupied_x, candidates$x_proj[selected_idx])
    all_y <- c(occupied_y, candidates$y_proj[selected_idx])

    if (length(all_x) == 0L) {
      selected_idx <- c(selected_idx, idx)
    } else {
      dx <- all_x - candidates$x_proj[idx]
      dy <- all_y - candidates$y_proj[idx]
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
  excluded <- c("cell", "x", "y", "x_proj", "y_proj", "cluster", "sample_id", "sample_source", "point_id")
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

project_occupied_points <- function(points, target_crs) {
  if (is.null(points) || nrow(points) == 0L) {
    return(data.frame(x_proj = numeric(0), y_proj = numeric(0)))
  }

  points_proj <- terra::project(points, target_crs)
  coords <- terra::crds(points_proj)
  data.frame(x_proj = coords[, 1], y_proj = coords[, 2])
}

validate_legacy_samples_within_farm <- function(legacy_points, farm) {
  if (is.null(legacy_points) || nrow(legacy_points) == 0L) {
    return(invisible(TRUE))
  }

  farm_for_points <- terra::project(farm, terra::crs(legacy_points))
  inside <- legacy_points[farm_for_points]
  if (nrow(inside) != nrow(legacy_points)) {
    stop("Legacy samples must fall within the farm polygon.", call. = FALSE)
  }

  invisible(TRUE)
}

generate_sample_ids <- function(n, existing_ids = character()) {
  ids <- character(0)
  counter <- 1L

  while (length(ids) < n) {
    candidate <- sprintf("S%02d", counter)
    if (!(candidate %in% existing_ids) && !(candidate %in% ids)) {
      ids <- c(ids, candidate)
    }
    counter <- counter + 1L
  }

  ids
}

assign_clusters_to_scores <- function(scores, centers) {
  if (is.null(dim(scores))) {
    scores <- matrix(scores, nrow = 1)
  }

  distances <- vapply(
    seq_len(nrow(centers)),
    function(idx) {
      rowSums((scores - matrix(centers[idx, ], nrow(scores), ncol(scores), byrow = TRUE)) ^ 2)
    },
    numeric(nrow(scores))
  )
  if (is.null(dim(distances))) {
    distances <- matrix(distances, nrow = 1)
  }

  as.integer(max.col(-distances))
}

bind_sample_tables <- function(...) {
  tables <- Filter(Negate(is.null), list(...))
  if (length(tables) == 0L) {
    return(data.frame())
  }

  all_cols <- unique(unlist(lapply(tables, names), use.names = FALSE))
  aligned <- lapply(tables, function(tbl) {
    missing_cols <- setdiff(all_cols, names(tbl))
    for (col_name in missing_cols) {
      tbl[[col_name]] <- NA
    }

    tbl[, all_cols, drop = FALSE]
  })

  do.call(rbind, aligned)
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

enrich_legacy_samples <- function(stack, legacy_samples, pca, feature_cols, selected_components, km, target_crs) {
  if (is.null(legacy_samples) || nrow(legacy_samples$points) == 0L) {
    return(NULL)
  }

  legacy_points <- terra::project(legacy_samples$points, terra::crs(stack))
  extracted <- terra::extract(stack, legacy_points, ID = FALSE)
  extracted <- extracted[, feature_cols, drop = FALSE]
  if (any(!stats::complete.cases(extracted))) {
    stop("Legacy samples fall outside valid analysis stack cells.", call. = FALSE)
  }

  legacy_proj <- terra::project(legacy_points, target_crs)
  legacy_xy_proj <- terra::crds(legacy_proj)
  scores <- stats::predict(pca, newdata = extracted)[, seq_len(selected_components), drop = FALSE]

  legacy_table <- cbind(
    data.frame(
      cell = terra::cellFromXY(stack, legacy_samples$table[, c("x", "y"), drop = FALSE]),
      x = legacy_samples$table$x,
      y = legacy_samples$table$y,
      stringsAsFactors = FALSE
    ),
    extracted
  )
  legacy_table$point_id <- NA_integer_
  legacy_table$x_proj <- legacy_xy_proj[, 1]
  legacy_table$y_proj <- legacy_xy_proj[, 2]
  legacy_table$cluster <- assign_clusters_to_scores(scores, km$centers)
  legacy_table$sample_id <- legacy_samples$table$sample_id
  legacy_table$sample_source <- "legacy"

  legacy_table
}

sample_cluster_points <- function(candidate_features, allocation, cfg, occupied = NULL) {
  split_candidates <- split(candidate_features, candidate_features$cluster)
  sampled <- vector("list", length(split_candidates))
  occupied_coords <- occupied

  for (idx in seq_along(split_candidates)) {
    sampled[[idx]] <- select_spaced_samples(
      candidates = split_candidates[[idx]],
      n = allocation[[idx]],
      min_spacing_m = cfg$min_point_spacing_m,
      seed = cfg$random_seed + idx,
      occupied = occupied_coords
    )
    occupied_coords <- rbind(
      occupied_coords,
      sampled[[idx]][, c("x_proj", "y_proj"), drop = FALSE]
    )
  }

  do.call(rbind, sampled)
}

design_samples_from_stack <- function(stack, farm, cfg) {
  target_crs <- farm_utm_crs(farm)
  legacy_samples <- if (!is.null(cfg$legacy_samples_path)) {
    read_legacy_samples_csv(cfg$legacy_samples_path, target_crs = terra::crs(stack))
  } else {
    NULL
  }
  validate_legacy_samples_within_farm(
    legacy_points = if (is.null(legacy_samples)) NULL else legacy_samples$points,
    farm = farm
  )

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
  sampled_new <- sample_cluster_points(
    candidate_features = candidate_features,
    allocation = allocation,
    cfg = cfg,
    occupied = project_occupied_points(
      points = if (is.null(legacy_samples)) NULL else legacy_samples$points,
      target_crs = target_crs
    )
  )
  sampled_new <- sampled_new[order(sampled_new$cluster, sampled_new$point_id), , drop = FALSE]
  sampled_new$sample_id <- generate_sample_ids(
    nrow(sampled_new),
    existing_ids = if (is.null(legacy_samples)) character(0) else legacy_samples$table$sample_id
  )
  sampled_new$sample_source <- "new"
  sampled <- bind_sample_tables(
    enrich_legacy_samples(
      stack = stack,
      legacy_samples = legacy_samples,
      pca = pca,
      feature_cols = feature_cols,
      selected_components = selected_components,
      km = km,
      target_crs = target_crs
    ),
    sampled_new
  )

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
