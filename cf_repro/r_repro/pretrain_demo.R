# pretrain_demo.R  —  Pre-train all 6 learners for live demo speed
#
# Usage:
#   Rscript pretrain_demo.R                       # default: hillstrom × men × visit
#   Rscript pretrain_demo.R --dataset hillstrom --group men --outcome visit
#   Rscript pretrain_demo.R --all                 # pre-train all combinations
#
# Output: results/demo_pretrained/<key>.rds
# Each rds contains the full results list expected by app_demo.R.

suppressPackageStartupMessages({
  library(grf); library(ranger); library(FNN)
})

SD <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) ".")
source(file.path(SD, "metrics.R"))
source(file.path(SD, "learners.R"))
source(file.path(SD, "dgp.R"))

RAW_DIR      <- file.path(SD, "..", "results", "real")
PRETRAIN_DIR <- file.path(SD, "..", "results", "demo_pretrained")
dir.create(PRETRAIN_DIR, recursive = TRUE, showWarnings = FALSE)

# ── Helpers (duplicated from app_demo.R for standalone use) ──────────────────

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a[1])) a else b

coerce_X_matrix <- function(df, X_cols) {
  X <- as.matrix(df[, X_cols, drop = FALSE])
  for (j in seq_len(ncol(X))) {
    if (!is.numeric(X[, j])) X[, j] <- as.numeric(factor(X[, j]))
  }
  storage.mode(X) <- "double"
  X
}

LEARNER_ORDER <- c("standard_clf","s_learner","t_learner",
                   "x_learner","causal_tree","causal_forest")
LEARNER_LABELS <- c(
  standard_clf  = "Standard Classifier", s_learner = "S-Learner",
  t_learner = "T-Learner", x_learner = "X-Learner",
  causal_tree = "Causal Tree (50)", causal_forest = "Causal Forest"
)

DATASET_META <- list(
  hillstrom = list(label = "Hillstrom MineThatData", max_n = 45000L,
                   outcomes = c("visit", "conversion", "spend"),
                   groups   = c("men", "women")),
  lenta     = list(label = "Lenta RetailHero", max_n = 100000L,
                   outcomes = c("response"), groups = NULL),
  criteo    = list(label = "Criteo Uplift v2.1", max_n = 100000L,
                   outcomes = c("visit", "conversion"), groups = NULL)
)

pretrain_key <- function(ds, group, outcome) {
  if (ds == "hillstrom") paste0("hillstrom_", group, "_", outcome)
  else                   paste0(ds, "_", outcome)
}

pretrain_one <- function(ds, group, outcome, num_trees = 500L) {
  key <- pretrain_key(ds, group, outcome)
  out_path <- file.path(PRETRAIN_DIR, paste0(key, ".rds"))

  cat(sprintf("\n=== %s ===\n", key))

  raw_path <- file.path(RAW_DIR, paste0(ds, "_raw.rds"))
  if (!file.exists(raw_path)) {
    cat(sprintf("  SKIP — raw data not found: %s\n", raw_path))
    return(invisible(NULL))
  }
  raw <- readRDS(raw_path)

  if (ds == "hillstrom") {
    df <- raw[[group]]
    X_cols <- raw$X_cols
    Y_col  <- outcome
    outcome_label <- switch(outcome,
                            visit = "Visit (binary)",
                            conversion = "Conversion (binary)",
                            spend = "Spend (continuous)",
                            outcome)
  } else if (ds == "criteo") {
    df <- raw$data; X_cols <- raw$X_cols
    Y_col <- paste0("Y_", outcome)
    outcome_label <- sprintf("%s (binary)", outcome)
  } else {
    df <- raw$data; X_cols <- raw$X_cols
    Y_col <- "Y"
    outcome_label <- sprintf("%s (binary)", outcome)
  }

  meta <- DATASET_META[[ds]]
  if (!is.null(meta$max_n) && nrow(df) > meta$max_n) {
    set.seed(42)
    df <- df[sample(nrow(df), meta$max_n), ]
  }

  X <- coerce_X_matrix(df, X_cols)
  W <- as.numeric(df[["W"]])
  Y <- as.numeric(df[[Y_col]])
  ok <- complete.cases(X) & !is.na(W) & !is.na(Y)
  X <- X[ok, , drop = FALSE]; W <- W[ok]; Y <- Y[ok]
  n <- nrow(X)
  set.seed(42)
  tr_idx <- sample(n, floor(n * 0.8))
  te_idx <- setdiff(seq_len(n), tr_idx)

  X_train <- X[tr_idx, , drop = FALSE]; W_train <- W[tr_idx]; Y_train <- Y[tr_idx]
  X_test  <- X[te_idx, , drop = FALSE]; W_test  <- W[te_idx]; Y_test  <- Y[te_idx]

  cat(sprintf("  Train n=%s, Test n=%s, Features=%d\n",
              format(length(W_train), big.mark = ","),
              format(length(W_test),  big.mark = ","),
              length(X_cols)))

  t0 <- Sys.time()
  learners <- train_all_learners(X_train, W_train, Y_train, X_test,
                                  num_trees = num_trees, seed = 42L,
                                  progress_fn = function(i, total, lbl) {
                                    cat(sprintf("  [%d/%d] Training %s...\n", i, total, lbl))
                                  })
  total_time <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cat(sprintf("  Total training: %.1fs\n", total_time))

  # Metrics
  metrics_df <- do.call(rbind, lapply(names(learners), function(nm) {
    lr <- learners[[nm]]
    if (!isTRUE(lr$ok)) {
      return(data.frame(method = LEARNER_LABELS[[nm]], auuc = NA, qini = NA,
                        auc = NA, ok = FALSE, train_time = lr$train_time,
                        stringsAsFactors = FALSE))
    }
    tau <- lr$pred$tau_hat
    auc_val <- if (nm == "standard_clf" && !is.null(lr$pred$prob)) {
      auc_score(lr$pred$prob, Y_test)
    } else NA_real_
    auuc_val <- if (nm == "standard_clf") NA_real_
                else auuc(tau, W_test, Y_test)
    qini_val <- if (nm == "standard_clf") NA_real_
                else qini(tau, W_test, Y_test)
    data.frame(method = LEARNER_LABELS[[nm]],
               auuc = auuc_val, qini = qini_val, auc = auc_val, ok = TRUE,
               train_time = lr$train_time, stringsAsFactors = FALSE)
  }))

  # Print summary
  cat("\n  === Metrics ===\n")
  print(metrics_df, row.names = FALSE)

  vi_df <- if (!is.null(learners$causal_forest$fit)) {
    compute_var_importance(learners$causal_forest$fit, X_cols)
  } else NULL

  result <- list(
    dataset_key   = ds,
    dataset_label = meta$label,
    outcome       = Y_col,
    outcome_label = outcome_label,
    group         = group,
    n_train       = nrow(X_train),
    n_test        = nrow(X_test),
    X_cols        = X_cols,
    X_train = X_train, W_train = W_train, Y_train = Y_train,
    X_test  = X_test,  W_test  = W_test,  Y_test  = Y_test,
    learners      = learners,
    metrics       = metrics_df,
    var_importance = vi_df,
    is_binary_Y   = length(unique(Y_test[!is.na(Y_test)])) == 2 &&
                    all(sort(unique(Y_test[!is.na(Y_test)])) == c(0, 1)),
    trained_at    = Sys.time(),
    mode          = "pretrained",
    num_trees     = num_trees
  )

  saveRDS(result, out_path)
  cat(sprintf("  ✅ Saved: %s\n", out_path))
  invisible(out_path)
}

# ── Simulation Designs (Design 1/2/3) ────────────────────────────────────────

SIM_META <- list(
  design1 = list(
    label  = "Simulation: Design 1 (Confounding — τ=0)",
    sim_fn = gen_design1,
    d_vals = c(2L, 5L, 10L, 20L),
    max_n  = 5000L
  ),
  design2 = list(
    label  = "Simulation: Design 2 (Smooth τ)",
    sim_fn = gen_design2,
    d_vals = c(2L, 3L, 4L, 5L, 6L, 8L),
    max_n  = 5000L
  ),
  design3 = list(
    label  = "Simulation: Design 3 (Sharp τ)",
    sim_fn = gen_design3,
    d_vals = c(2L, 3L, 4L, 5L, 6L, 8L),
    max_n  = 5000L
  )
)

pretrain_sim <- function(ds, d, num_trees = 500L) {
  meta     <- SIM_META[[ds]]
  key      <- sprintf("%s_d%d", ds, d)
  out_path <- file.path(PRETRAIN_DIR, paste0(key, ".rds"))

  cat(sprintf("\n=== %s (d=%d) ===\n", meta$label, d))

  dat    <- meta$sim_fn(meta$max_n, d, seed = 42L)
  X_cols <- paste0("X", seq_len(d))
  df     <- as.data.frame(dat$X); colnames(df) <- X_cols
  df$W   <- dat$W; df$Y <- dat$Y

  X <- coerce_X_matrix(df, X_cols)
  W <- as.numeric(df$W)
  Y <- as.numeric(df$Y)
  ok <- complete.cases(X) & !is.na(W) & !is.na(Y)
  X <- X[ok, , drop = FALSE]; W <- W[ok]; Y <- Y[ok]
  tau_all <- dat$tau[ok]

  n <- nrow(X); set.seed(42L)
  tr_idx <- sample(n, floor(n * 0.8))
  te_idx <- setdiff(seq_len(n), tr_idx)

  X_train <- X[tr_idx, , drop=FALSE]; W_train <- W[tr_idx]; Y_train <- Y[tr_idx]
  X_test  <- X[te_idx, , drop=FALSE]; W_test  <- W[te_idx]; Y_test  <- Y[te_idx]
  tau_true_test <- tau_all[te_idx]

  cat(sprintf("  Train n=%d, Test n=%d, d=%d\n", nrow(X_train), nrow(X_test), d))

  t0 <- Sys.time()
  learners <- train_all_learners(X_train, W_train, Y_train, X_test,
                                  num_trees = num_trees, seed = 42L,
                                  progress_fn = function(i, total, lbl) {
                                    cat(sprintf("  [%d/%d] %s\n", i, total, lbl))
                                  })
  cat(sprintf("  Total: %.1fs\n", as.numeric(difftime(Sys.time(), t0, units="secs"))))

  metrics_df <- do.call(rbind, lapply(names(learners), function(nm) {
    lr <- learners[[nm]]
    if (!isTRUE(lr$ok))
      return(data.frame(method=LEARNER_LABELS[[nm]], auuc=NA, qini=NA,
                        auc=NA, ok=FALSE, train_time=lr$train_time,
                        stringsAsFactors=FALSE))
    tau_hat <- lr$pred$tau_hat
    auc_val  <- if (nm=="standard_clf" && !is.null(lr$pred$prob))
                  auc_score(lr$pred$prob, Y_test) else NA_real_
    auuc_val <- if (nm=="standard_clf") NA_real_ else auuc(tau_hat, W_test, Y_test)
    qini_val <- if (nm=="standard_clf") NA_real_ else qini(tau_hat, W_test, Y_test)
    data.frame(method=LEARNER_LABELS[[nm]], auuc=auuc_val, qini=qini_val,
               auc=auc_val, ok=TRUE, train_time=lr$train_time,
               stringsAsFactors=FALSE)
  }))
  print(metrics_df[, c("method","auuc","qini","train_time")], row.names=FALSE)

  vi_df <- if (!is.null(learners$causal_forest$fit))
    compute_var_importance(learners$causal_forest$fit, X_cols) else NULL

  result <- list(
    dataset_key   = ds,
    dataset_label = meta$label,
    outcome       = "Y",
    outcome_label = sprintf("Y (simulated, d=%d)", d),
    group         = NULL,
    n_train       = nrow(X_train),
    n_test        = nrow(X_test),
    X_cols        = X_cols,
    X_train=X_train, W_train=W_train, Y_train=Y_train,
    X_test=X_test,   W_test=W_test,   Y_test=Y_test,
    learners      = learners,
    metrics       = metrics_df,
    var_importance = vi_df,
    is_binary_Y   = FALSE,
    tau_true      = tau_true_test,
    is_sim        = TRUE,
    sim_d         = d,
    trained_at    = Sys.time(),
    mode          = "pretrained",
    num_trees     = num_trees
  )

  saveRDS(result, out_path)
  cat(sprintf("  Saved: %s\n", out_path))
  invisible(out_path)
}

# ── CLI ──────────────────────────────────────────────────────────────────────

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  i <- which(args == flag); if (length(i) == 0) default else args[i + 1]
}
do_all     <- "--all"     %in% args
do_all_sim <- "--all-sim" %in% args
do_sim     <- "--sim"     %in% args

if (do_all_sim || do_sim) {
  nt <- as.integer(get_arg("--trees", 500L))
  if (do_all_sim) {
    cat("=== Pre-training all simulation designs ===\n")
    for (ds in names(SIM_META))
      for (d in SIM_META[[ds]]$d_vals)
        pretrain_sim(ds, d, num_trees = nt)
  } else {
    ds <- get_arg("--dataset", "design1")
    d  <- as.integer(get_arg("--d", SIM_META[[ds]]$d_vals[2]))
    pretrain_sim(ds, d, num_trees = nt)
  }
} else if (do_all) {
  cat("=== Pre-training all real-data combinations ===\n")
  for (ds in names(DATASET_META)) {
    meta <- DATASET_META[[ds]]
    if (!is.null(meta$groups)) {
      for (g in meta$groups) for (o in meta$outcomes) pretrain_one(ds, g, o)
    } else {
      for (o in meta$outcomes) pretrain_one(ds, NULL, o)
    }
  }
} else {
  ds  <- get_arg("--dataset", "hillstrom")
  grp <- get_arg("--group",   "men")
  oc  <- get_arg("--outcome", "visit")
  pretrain_one(ds, grp, oc)
}

cat("\nDone.\n")
