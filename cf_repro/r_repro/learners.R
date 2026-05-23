# learners.R  —  6 uplift learners
#
# Each learner exposes:
#   fit_<name>(X, W, Y, num_trees, ...) -> fit object
#   predict_<name>(fit, X_test)        -> list(tau_hat, ci_lower, ci_upper)
#
# Standard Classifier additionally returns prob_test for AUC.
# Meta-learners (S/T/X) return NA for CI (no closed-form variance).
# Causal Tree/Forest use grf's IJ variance.

suppressPackageStartupMessages({
  library(ranger)
  library(grf)
})

# Helper: handle ranger output for both classification (probability) and regression
.ranger_predict <- function(model, newdata, is_binary) {
  pred <- predict(model, data = newdata)
  if (is_binary && !is.null(pred$predictions) && is.matrix(pred$predictions)) {
    # probability=TRUE returns matrix with columns "0", "1"
    col <- which(colnames(pred$predictions) == "1")
    if (length(col) == 0) col <- 2L
    as.numeric(pred$predictions[, col])
  } else {
    as.numeric(pred$predictions)
  }
}

.is_binary_outcome <- function(Y) {
  u <- unique(Y[!is.na(Y)])
  length(u) == 2 && all(sort(as.numeric(u)) == c(0, 1))
}

# Ensure X has column names — ranger needs them for formula matching
.ensure_X_named <- function(X) {
  if (is.null(colnames(X))) {
    colnames(X) <- paste0("V", seq_len(ncol(X)))
  }
  X
}

# --------------------------------------------------------------------------
# 1. Standard Classifier (baseline, AUC only)
# --------------------------------------------------------------------------
fit_standard_clf <- function(X, W, Y, num_trees = 500, seed = 42, ...) {
  is_binary <- .is_binary_outcome(Y)
  X <- .ensure_X_named(X)
  df <- data.frame(X, .Y = if (is_binary) factor(Y, levels = c(0, 1)) else Y)
  if (is_binary) {
    model <- ranger(.Y ~ ., data = df, num.trees = num_trees,
                    probability = TRUE, seed = seed,
                    num.threads = max(1L, parallel::detectCores() - 1L))
  } else {
    model <- ranger(.Y ~ ., data = df, num.trees = num_trees, seed = seed,
                    num.threads = max(1L, parallel::detectCores() - 1L))
  }
  list(model = model, is_binary = is_binary, type = "standard_clf")
}

predict_standard_clf <- function(fit, X_test) {
  X_test <- .ensure_X_named(X_test)
  prob <- .ranger_predict(fit$model, as.data.frame(X_test), fit$is_binary)
  list(
    tau_hat  = rep(NA_real_, nrow(X_test)),  # not an uplift model
    ci_lower = rep(NA_real_, nrow(X_test)),
    ci_upper = rep(NA_real_, nrow(X_test)),
    prob     = prob
  )
}

# --------------------------------------------------------------------------
# 2. S-Learner  (single model with W as feature)
# --------------------------------------------------------------------------
fit_s_learner <- function(X, W, Y, num_trees = 500, seed = 42, ...) {
  is_binary <- .is_binary_outcome(Y)
  X <- .ensure_X_named(X)
  df <- data.frame(X, .W = as.numeric(W),
                   .Y = if (is_binary) factor(Y, levels = c(0, 1)) else Y)
  if (is_binary) {
    model <- ranger(.Y ~ ., data = df, num.trees = num_trees,
                    probability = TRUE, seed = seed,
                    num.threads = max(1L, parallel::detectCores() - 1L))
  } else {
    model <- ranger(.Y ~ ., data = df, num.trees = num_trees, seed = seed,
                    num.threads = max(1L, parallel::detectCores() - 1L))
  }
  list(model = model, is_binary = is_binary, type = "s_learner")
}

predict_s_learner <- function(fit, X_test) {
  X_test <- .ensure_X_named(X_test)
  X_df <- as.data.frame(X_test)
  X1 <- cbind(X_df, .W = 1); X0 <- cbind(X_df, .W = 0)
  p1 <- .ranger_predict(fit$model, X1, fit$is_binary)
  p0 <- .ranger_predict(fit$model, X0, fit$is_binary)
  list(
    tau_hat  = p1 - p0,
    ci_lower = rep(NA_real_, nrow(X_test)),
    ci_upper = rep(NA_real_, nrow(X_test))
  )
}

# --------------------------------------------------------------------------
# 3. T-Learner  (two separate models)
# --------------------------------------------------------------------------
fit_t_learner <- function(X, W, Y, num_trees = 500, seed = 42, ...) {
  is_binary <- .is_binary_outcome(Y)
  X <- .ensure_X_named(X)
  idx0 <- which(W == 0); idx1 <- which(W == 1)
  X_df <- as.data.frame(X)

  make_model <- function(idx) {
    df_sub <- data.frame(X_df[idx, , drop = FALSE],
                         .Y = if (is_binary) factor(Y[idx], levels = c(0, 1)) else Y[idx])
    if (is_binary) {
      ranger(.Y ~ ., data = df_sub, num.trees = num_trees,
             probability = TRUE, seed = seed,
             num.threads = max(1L, parallel::detectCores() - 1L))
    } else {
      ranger(.Y ~ ., data = df_sub, num.trees = num_trees, seed = seed,
             num.threads = max(1L, parallel::detectCores() - 1L))
    }
  }
  list(m0 = make_model(idx0), m1 = make_model(idx1),
       is_binary = is_binary, type = "t_learner")
}

predict_t_learner <- function(fit, X_test) {
  X_test <- .ensure_X_named(X_test)
  X_df <- as.data.frame(X_test)
  p0 <- .ranger_predict(fit$m0, X_df, fit$is_binary)
  p1 <- .ranger_predict(fit$m1, X_df, fit$is_binary)
  list(
    tau_hat  = p1 - p0,
    ci_lower = rep(NA_real_, nrow(X_test)),
    ci_upper = rep(NA_real_, nrow(X_test))
  )
}

# --------------------------------------------------------------------------
# 4. X-Learner  (Künzel et al. 2019)
# --------------------------------------------------------------------------
fit_x_learner <- function(X, W, Y, num_trees = 500, seed = 42, ...) {
  is_binary <- .is_binary_outcome(Y)
  X <- .ensure_X_named(X)
  X_df <- as.data.frame(X)
  idx0 <- which(W == 0); idx1 <- which(W == 1)

  # Stage 1: outcome models per group (= T-Learner stage)
  t_fit <- fit_t_learner(X, W, Y, num_trees = num_trees, seed = seed)

  # Stage 2: impute residuals
  # For treated:  D1 = Y1 - mu0(X1)
  # For control:  D0 = mu1(X0) - Y0
  mu0_at_1 <- .ranger_predict(t_fit$m0, X_df[idx1, , drop = FALSE], is_binary)
  mu1_at_0 <- .ranger_predict(t_fit$m1, X_df[idx0, , drop = FALSE], is_binary)
  D1 <- as.numeric(Y[idx1]) - mu0_at_1
  D0 <- mu1_at_0 - as.numeric(Y[idx0])

  # Stage 3: regress residuals on X (always regression, even if binary outcome)
  tau1_model <- ranger(.D ~ ., data = data.frame(X_df[idx1, , drop = FALSE], .D = D1),
                       num.trees = num_trees, seed = seed,
                       num.threads = max(1L, parallel::detectCores() - 1L))
  tau0_model <- ranger(.D ~ ., data = data.frame(X_df[idx0, , drop = FALSE], .D = D0),
                       num.trees = num_trees, seed = seed,
                       num.threads = max(1L, parallel::detectCores() - 1L))

  # Stage 4: propensity model
  e_df <- data.frame(X_df, .W = factor(W, levels = c(0, 1)))
  e_model <- ranger(.W ~ ., data = e_df, num.trees = num_trees,
                    probability = TRUE, seed = seed,
                    num.threads = max(1L, parallel::detectCores() - 1L))

  list(tau0 = tau0_model, tau1 = tau1_model, e_model = e_model,
       is_binary = is_binary, type = "x_learner")
}

predict_x_learner <- function(fit, X_test) {
  X_test <- .ensure_X_named(X_test)
  X_df <- as.data.frame(X_test)
  tau0_hat <- .ranger_predict(fit$tau0, X_df, FALSE)  # regression head
  tau1_hat <- .ranger_predict(fit$tau1, X_df, FALSE)
  e_hat    <- .ranger_predict(fit$e_model, X_df, TRUE)
  # Combine: tau = e * tau0 + (1-e) * tau1   (Künzel et al. eq.)
  tau_hat <- e_hat * tau0_hat + (1 - e_hat) * tau1_hat
  list(
    tau_hat  = tau_hat,
    ci_lower = rep(NA_real_, nrow(X_test)),
    ci_upper = rep(NA_real_, nrow(X_test))
  )
}

# --------------------------------------------------------------------------
# 5. Causal Tree (small ensemble, 50 trees) — grf-based
# --------------------------------------------------------------------------
fit_causal_tree <- function(X, W, Y, num_trees = 50, seed = 42, ...) {
  cf <- causal_forest(
    X               = as.matrix(X),
    Y               = as.numeric(Y),
    W               = as.numeric(W),
    num.trees       = num_trees,
    honesty         = TRUE,
    sample.fraction = 0.5,
    min.node.size   = 5,
    seed            = seed
  )
  list(model = cf, type = "causal_tree")
}

predict_causal_tree <- function(fit, X_test) {
  p <- predict(fit$model, newdata = as.matrix(X_test), estimate.variance = TRUE)
  tau_hat <- as.numeric(p$predictions)
  se <- sqrt(pmax(as.numeric(p$variance.estimates), 0))
  list(
    tau_hat  = tau_hat,
    ci_lower = tau_hat - 1.96 * se,
    ci_upper = tau_hat + 1.96 * se
  )
}

# --------------------------------------------------------------------------
# 6. Causal Forest (default 500 trees)
# --------------------------------------------------------------------------
fit_causal_forest <- function(X, W, Y, num_trees = 500, seed = 42, ...) {
  cf <- causal_forest(
    X                = as.matrix(X),
    Y                = as.numeric(Y),
    W                = as.numeric(W),
    num.trees        = num_trees,
    honesty          = TRUE,
    honesty.fraction = 0.5,
    sample.fraction  = 0.5,
    min.node.size    = 5,
    seed             = seed
  )
  list(model = cf, type = "causal_forest")
}

predict_causal_forest <- function(fit, X_test) {
  p <- predict(fit$model, newdata = as.matrix(X_test), estimate.variance = TRUE)
  tau_hat <- as.numeric(p$predictions)
  se <- sqrt(pmax(as.numeric(p$variance.estimates), 0))
  list(
    tau_hat  = tau_hat,
    ci_lower = tau_hat - 1.96 * se,
    ci_upper = tau_hat + 1.96 * se
  )
}

# --------------------------------------------------------------------------
# Variable importance helper
#   For grf models: use causal_forest variable_importance()
#   For ranger models: use ranger's built-in importance (need importance arg)
#   For demo simplicity: always return CF's VI (most meaningful for uplift)
# --------------------------------------------------------------------------
compute_var_importance <- function(cf_fit, X_cols) {
  if (is.null(cf_fit) || is.null(cf_fit$model)) return(NULL)
  vi <- tryCatch(as.numeric(variable_importance(cf_fit$model)),
                 error = function(e) NULL)
  if (is.null(vi)) return(NULL)
  data.frame(feature = X_cols, importance = vi, stringsAsFactors = FALSE)
}

# --------------------------------------------------------------------------
# Master wrapper: train all 6 learners on (X, W, Y)
#   Returns named list, each element = fit object + predictions on X_test
#   progress_fn(step, label) is called before each learner; can be used
#   to push Shiny notifications.
# --------------------------------------------------------------------------
train_all_learners <- function(X_train, W_train, Y_train,
                                X_test,
                                num_trees = 500,
                                seed = 42,
                                progress_fn = NULL) {
  learners <- list(
    standard_clf  = list(label = "Standard Classifier",
                         fit_fn = fit_standard_clf, pred_fn = predict_standard_clf),
    s_learner     = list(label = "S-Learner",
                         fit_fn = fit_s_learner, pred_fn = predict_s_learner),
    t_learner     = list(label = "T-Learner",
                         fit_fn = fit_t_learner, pred_fn = predict_t_learner),
    x_learner     = list(label = "X-Learner",
                         fit_fn = fit_x_learner, pred_fn = predict_x_learner),
    causal_tree   = list(label = "Causal Tree (50)",
                         fit_fn = fit_causal_tree, pred_fn = predict_causal_tree),
    causal_forest = list(label = "Causal Forest",
                         fit_fn = fit_causal_forest, pred_fn = predict_causal_forest)
  )

  results <- list()
  n_total <- length(learners)
  for (i in seq_along(learners)) {
    name <- names(learners)[i]
    lr   <- learners[[i]]
    if (!is.null(progress_fn)) progress_fn(i, n_total, lr$label)

    t0 <- Sys.time()
    fit_obj <- tryCatch(
      lr$fit_fn(X_train, W_train, Y_train,
                num_trees = if (name == "causal_tree") 50 else num_trees,
                seed = seed),
      error = function(e) {
        message(sprintf("[learners] %s FAILED: %s", lr$label, conditionMessage(e)))
        NULL
      }
    )
    pred_obj <- if (!is.null(fit_obj)) {
      tryCatch(lr$pred_fn(fit_obj, X_test),
               error = function(e) {
                 message(sprintf("[learners] predict %s FAILED: %s",
                                 lr$label, conditionMessage(e)))
                 NULL
               })
    } else NULL
    train_time <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

    results[[name]] <- list(
      label      = lr$label,
      fit        = fit_obj,
      pred       = pred_obj,
      train_time = train_time,
      ok         = !is.null(fit_obj) && !is.null(pred_obj)
    )
  }
  results
}
