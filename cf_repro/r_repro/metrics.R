# metrics.R  —  Uplift evaluation metrics
#
# AUUC  (Area Under Uplift Curve)
# Qini  coefficient
# AUC   (binary classifier)
# Curve data helpers for plotting
#
# All metrics assume:
#   tau_hat : numeric vector of CATE estimates on TEST set
#   W       : 0/1 treatment indicator on TEST set
#   Y       : numeric outcome on TEST set
#
# Notes:
#   - "Uplift curve" sorts customers by tau_hat (descending), then plots
#     cumulative incremental conversion vs % targeted.
#   - "Qini" is similar but uses (treated_conv - control_conv * n_treat/n_ctrl)
#     to handle unbalanced treatment ratios.

# --------------------------------------------------------------------------
# uplift_curve_data
#   Returns df ready for ggplot: pct_targeted, cum_gain, random_baseline
# --------------------------------------------------------------------------
uplift_curve_data <- function(tau_hat, W, Y, n_points = 200) {
  n <- length(tau_hat)
  ord <- order(tau_hat, decreasing = TRUE)
  W_o <- W[ord]; Y_o <- Y[ord]

  n_treat <- sum(W); n_ctrl <- sum(1 - W)
  if (n_treat == 0 || n_ctrl == 0) {
    return(data.frame(pct_targeted = numeric(0),
                      cum_gain     = numeric(0),
                      random       = numeric(0)))
  }

  # Cumulative uplift gain: (treated conversions / n_treat at rank k)
  #                       - (control conversions / n_ctrl at rank k)
  # Scaled by k (number of customers targeted) for "gain" interpretation
  cum_t <- cumsum(Y_o * W_o)
  cum_c <- cumsum(Y_o * (1 - W_o))
  k     <- seq_len(n)
  cum_treat_rate <- cum_t / pmax(cumsum(W_o), 1)
  cum_ctrl_rate  <- cum_c / pmax(cumsum(1 - W_o), 1)
  cum_uplift     <- (cum_treat_rate - cum_ctrl_rate) * k

  # Random baseline = linear interpolation from 0 to total uplift
  total_uplift <- cum_uplift[n]
  random <- (k / n) * total_uplift

  # Thin to n_points for plotting speed
  idx <- unique(round(seq(1, n, length.out = min(n_points, n))))
  data.frame(
    pct_targeted = k[idx] / n,
    cum_gain     = cum_uplift[idx],
    random       = random[idx]
  )
}

# --------------------------------------------------------------------------
# auuc  (Area Under Uplift Curve)
#   Trapezoidal integration of cum_gain over pct_targeted.
#   Higher = better. Bounded by total uplift achievable.
# --------------------------------------------------------------------------
auuc <- function(tau_hat, W, Y) {
  df <- uplift_curve_data(tau_hat, W, Y, n_points = length(tau_hat))
  if (nrow(df) < 2) return(NA_real_)
  # Trapezoidal integral
  x <- df$pct_targeted; y <- df$cum_gain
  sum(diff(x) * (head(y, -1) + tail(y, -1)) / 2)
}

# --------------------------------------------------------------------------
# qini_curve_data
#   Returns df for plotting Qini curve.
#   Qini gain = cum_treated_conv - cum_control_conv * (n_treat/n_ctrl)
# --------------------------------------------------------------------------
qini_curve_data <- function(tau_hat, W, Y, n_points = 200) {
  n <- length(tau_hat)
  ord <- order(tau_hat, decreasing = TRUE)
  W_o <- W[ord]; Y_o <- Y[ord]

  n_treat <- sum(W); n_ctrl <- sum(1 - W)
  if (n_treat == 0 || n_ctrl == 0) {
    return(data.frame(pct_targeted = numeric(0),
                      qini_gain    = numeric(0),
                      random       = numeric(0)))
  }

  scale <- n_treat / n_ctrl
  cum_t <- cumsum(Y_o * W_o)
  cum_c <- cumsum(Y_o * (1 - W_o)) * scale
  gain  <- cum_t - cum_c
  k     <- seq_len(n)

  total_gain <- gain[n]
  random <- (k / n) * total_gain

  idx <- unique(round(seq(1, n, length.out = min(n_points, n))))
  data.frame(
    pct_targeted = k[idx] / n,
    qini_gain    = gain[idx],
    random       = random[idx]
  )
}

# --------------------------------------------------------------------------
# qini  (Qini coefficient)
#   = 2 * Area between Qini curve and Random baseline / Total uplift
#   Range: typically 0 to ~0.5 for real datasets. Higher = better.
# --------------------------------------------------------------------------
qini <- function(tau_hat, W, Y) {
  df <- qini_curve_data(tau_hat, W, Y, n_points = length(tau_hat))
  if (nrow(df) < 2) return(NA_real_)
  x <- df$pct_targeted
  area_model  <- sum(diff(x) * (head(df$qini_gain, -1) + tail(df$qini_gain, -1)) / 2)
  area_random <- sum(diff(x) * (head(df$random,    -1) + tail(df$random,    -1)) / 2)
  # Normalize by perfect-model area approximation
  # Common convention: Qini = (area_model - area_random)
  area_model - area_random
}

# --------------------------------------------------------------------------
# auc_score
#   AUC for binary classifier. Uses pROC if available, else manual Wilcoxon.
# --------------------------------------------------------------------------
auc_score <- function(prob, y) {
  y <- as.numeric(y)
  if (length(unique(y)) < 2) return(NA_real_)
  if (requireNamespace("pROC", quietly = TRUE)) {
    suppressMessages(
      as.numeric(pROC::auc(y, prob, quiet = TRUE, direction = "<"))
    )
  } else {
    # Manual: Wilcoxon-Mann-Whitney statistic
    pos <- sum(y == 1); neg <- sum(y == 0)
    if (pos == 0 || neg == 0) return(NA_real_)
    r <- rank(prob)
    (sum(r[y == 1]) - pos * (pos + 1) / 2) / (pos * neg)
  }
}

# --------------------------------------------------------------------------
# safe_metric
#   Wrapper that returns NA on error (e.g., when tau_hat is all NA for clf)
# --------------------------------------------------------------------------
safe_metric <- function(expr) {
  tryCatch(expr, error = function(e) NA_real_,
                  warning = function(w) suppressWarnings(eval(expr)))
}
