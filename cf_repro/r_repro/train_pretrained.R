# train_pretrained.R  —  Train CF models on real datasets, save .rds artifacts
#
# Usage:
#   Rscript train_pretrained.R              # all available datasets
#   Rscript train_pretrained.R --only hillstrom
#   Rscript train_pretrained.R --only lenta
#   Rscript train_pretrained.R --only criteo
#
# Prerequisites: run prepare_real_data.R first.
#
# Output (results/real/):
#   {key}.rds        — model result list
#   {key}_cate.csv   — test-set predictions CSV

suppressPackageStartupMessages(library(grf))

args    <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  i <- which(args == flag); if (!length(i)) default else args[i + 1]
}
only <- get_arg("--only", "all")

sd_path <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) ".")
source(file.path(sd_path, "methods.R"))
RAW_DIR <- file.path(sd_path, "..", "results", "real")
OUT_DIR <- RAW_DIR

cat("=== train_pretrained.R ===\n")
cat(sprintf("Output: %s\n\n", normalizePath(OUT_DIR)))

# ── Core training function ────────────────────────────────────────────────────

train_and_save <- function(df, X_cols, W_col, Y_col, key,
                           num_trees      = 500,
                           sample_fraction = 0.5,
                           seed            = 42,
                           out_dir         = OUT_DIR,
                           force           = FALSE) {
  dest_rds <- file.path(out_dir, paste0(key, ".rds"))
  dest_csv <- file.path(out_dir, paste0(key, "_cate.csv"))
  if (file.exists(dest_rds) && !force) {
    cat(sprintf("[%s] Already trained, skipping. (use force=TRUE to retrain)\n\n", key))
    return(invisible(TRUE))
  }
  cat(sprintf("[%s] Training CF: n=%d, p=%d, trees=%d, Y=%s\n",
              key, nrow(df), length(X_cols), num_trees, Y_col))
  t0 <- proc.time()["elapsed"]

  # Prepare matrices
  X_mat <- as.matrix(df[, X_cols, drop = FALSE])
  for (j in seq_len(ncol(X_mat))) {
    if (!is.numeric(X_mat[, j]))
      X_mat[, j] <- as.numeric(factor(X_mat[, j]))
  }
  storage.mode(X_mat) <- "double"
  W_vec <- as.numeric(df[[W_col]])
  Y_vec <- as.numeric(df[[Y_col]])

  # Drop rows with NA
  ok <- complete.cases(X_mat) & !is.na(W_vec) & !is.na(Y_vec)
  X_mat <- X_mat[ok, ]; W_vec <- W_vec[ok]; Y_vec <- Y_vec[ok]

  # 80/20 train-test split
  set.seed(seed)
  n       <- nrow(X_mat)
  tr_idx  <- sample(n, floor(n * 0.8))
  te_idx  <- setdiff(seq_len(n), tr_idx)

  X_train <- X_mat[tr_idx, ]; W_train <- W_vec[tr_idx]; Y_train <- Y_vec[tr_idx]
  X_test  <- X_mat[te_idx, ]; W_test  <- W_vec[te_idx]; Y_test  <- Y_vec[te_idx]

  cat(sprintf("  train=%d  test=%d\n", nrow(X_train), nrow(X_test)))

  # Grow causal forest (from methods.R)
  cf <- grow_causal_forest(X_train, W_train, Y_train,
                           num_trees       = num_trees,
                           sample_fraction = sample_fraction,
                           seed            = seed)

  # Predict with variance on test set
  cat(sprintf("  Predicting on test set...\n"))
  preds   <- predict(cf, newdata = X_test, estimate.variance = TRUE)
  tau_hat <- as.numeric(preds$predictions)
  se_hat  <- sqrt(pmax(as.numeric(preds$variance.estimates), 0))

  # Clamp binary outcomes to [-1, 1]
  is_binary <- all(Y_vec %in% c(0, 1))
  if (is_binary) tau_hat <- pmax(-1, pmin(1, tau_hat))

  tau_lower <- tau_hat - 1.96 * se_hat
  tau_upper <- tau_hat + 1.96 * se_hat

  # Variable importance
  vi <- variable_importance(cf)
  vi_df <- data.frame(feature    = X_cols,
                      importance = as.numeric(vi),
                      stringsAsFactors = FALSE)
  vi_df <- vi_df[order(vi_df$importance, decreasing = TRUE), ]

  elapsed <- proc.time()["elapsed"] - t0
  cat(sprintf("  Done in %.1f s. Mean CATE = %.4f, SD = %.4f\n\n",
              elapsed, mean(tau_hat), sd(tau_hat)))

  # Save .rds
  saveRDS(list(
    tau_hat       = tau_hat,
    tau_lower     = tau_lower,
    tau_upper     = tau_upper,
    X_test        = X_test,
    W_test        = W_test,
    Y_test        = Y_test,
    X_cols        = X_cols,
    var_importance = vi_df,
    n_train       = nrow(X_train),
    n_test        = nrow(X_test),
    outcome       = Y_col,
    dataset_label = key,
    trained_at    = Sys.time()
  ), dest_rds)

  # Save _cate.csv
  cate_df           <- as.data.frame(X_test)
  colnames(cate_df) <- X_cols
  cate_df$W         <- W_test
  cate_df$Y         <- Y_test
  cate_df$tau_hat   <- tau_hat
  cate_df$tau_lower <- tau_lower
  cate_df$tau_upper <- tau_upper
  write.csv(cate_df, dest_csv, row.names = FALSE)

  invisible(TRUE)
}

# ── 1. Hillstrom ──────────────────────────────────────────────────────────────

train_hillstrom <- function() {
  raw_path <- file.path(RAW_DIR, "hillstrom_raw.rds")
  if (!file.exists(raw_path)) {
    cat("[Hillstrom] hillstrom_raw.rds not found. Run prepare_real_data.R first.\n\n")
    return(invisible(FALSE))
  }
  raw    <- readRDS(raw_path)
  X_cols <- raw$X_cols

  for (group in c("men", "women")) {
    df <- raw[[group]]
    for (Y_col in raw$Y_options) {
      key <- paste0("hillstrom_", group, "_", Y_col)
      train_and_save(df, X_cols, W_col = "W", Y_col = Y_col,
                     key        = key,
                     num_trees  = 1000,
                     sample_fraction = 0.5,
                     seed       = 42)
    }
  }
}

# ── 2. Lenta ──────────────────────────────────────────────────────────────────

train_lenta <- function() {
  raw_path <- file.path(RAW_DIR, "lenta_raw.rds")
  if (!file.exists(raw_path)) {
    cat("[Lenta] lenta_raw.rds not found. Run prepare_real_data.R first.\n\n")
    return(invisible(FALSE))
  }
  raw    <- readRDS(raw_path)
  df     <- raw$data
  X_cols <- raw$X_cols

  for (Y_name in names(raw$Y_options)) {
    Y_col <- if (Y_name == "response") "Y" else Y_name
    key   <- paste0("lenta_", Y_name)
    train_and_save(df, X_cols, W_col = "W", Y_col = Y_col,
                   key       = key,
                   num_trees = 500,
                   sample_fraction = 0.5,
                   seed      = 42)
  }
}

# ── 3. Criteo ─────────────────────────────────────────────────────────────────

train_criteo <- function() {
  raw_path <- file.path(RAW_DIR, "criteo_raw.rds")
  if (!file.exists(raw_path)) {
    cat("[Criteo] criteo_raw.rds not found. Run prepare_real_data.R first.\n\n")
    return(invisible(FALSE))
  }
  raw    <- readRDS(raw_path)
  df     <- raw$data
  X_cols <- raw$X_cols

  y_map <- c(visit = "Y_visit", conversion = "Y_conversion")
  for (Y_name in names(raw$Y_options)) {
    Y_col <- y_map[[Y_name]]
    key   <- paste0("criteo_", Y_name)
    train_and_save(df, X_cols, W_col = "W", Y_col = Y_col,
                   key       = key,
                   num_trees = 500,
                   sample_fraction = 0.5,
                   seed      = 42)
  }
}

# ── Run ───────────────────────────────────────────────────────────────────────

if (only %in% c("all", "hillstrom")) train_hillstrom()
if (only %in% c("all", "lenta"))     train_lenta()
if (only %in% c("all", "criteo"))    train_criteo()

cat("=== Done ===\n")
cat("Files in results/real/:\n")
for (f in list.files(OUT_DIR, pattern = "\\.rds$|\\.csv$")) {
  size <- file.size(file.path(OUT_DIR, f))
  cat(sprintf("  %-45s  %s\n", f, format(structure(size, class="object_size"), units="Mb")))
}
