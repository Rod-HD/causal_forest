# =============================================================================
# dgp.R  —  Data-generating processes (Wager & Athey 2018, Section 5)
#
# Shared framework (paper p.19):
#   X_i  ~ Uniform([0,1]^d)
#   W_i  ~ Bernoulli(e(X_i))
#   Y_i^(w) ~ Normal( m(x) + (w - 0.5)*tau(x),  1 )
#   Y_i  = W_i * Y_i^(1) + (1 - W_i) * Y_i^(0)
# =============================================================================

# Beta(2,4) density — used for Design 1 propensity
beta24_pdf <- function(x) dbeta(x, shape1 = 2, shape2 = 4)

# --------------------------------------------------------------------------
# Design 1 — Confounding  (Eq. prop_setup, Table 1-2)
#   tau(x) = 0
#   m(x)   = 2*x1 - 1
#   e(x)   = 0.25 * (1 + Beta(2,4).pdf(x1))
# --------------------------------------------------------------------------
gen_design1 <- function(n, d, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  X     <- matrix(runif(n * d), nrow = n, ncol = d)
  e_x   <- 0.25 * (1 + beta24_pdf(X[, 1]))
  W     <- rbinom(n, 1, e_x)
  tau_x <- rep(0, n)
  m_x   <- 2 * X[, 1] - 1
  mu0   <- m_x - 0.5 * tau_x
  mu1   <- m_x + 0.5 * tau_x
  Y0    <- rnorm(n, mu0, 1)
  Y1    <- rnorm(n, mu1, 1)
  Y     <- W * Y1 + (1 - W) * Y0
  list(X = X, W = W, Y = Y, tau = tau_x)
}

# sigmoid helper for Design 2 (smooth, slope=20, inflection=1/3)
sigmoid20 <- function(x) 1 + 1 / (1 + exp(-20 * (x - 1/3)))

# --------------------------------------------------------------------------
# Design 2 — Smooth Heterogeneity  (Eq. tau0_setup, Table 3-4)
#   tau(x) = sigma20(x1) * sigma20(x2)
#   m(x)   = 0
#   e(x)   = 0.5
# --------------------------------------------------------------------------
gen_design2 <- function(n, d, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  X     <- matrix(runif(n * d), nrow = n, ncol = d)
  W     <- rbinom(n, 1, 0.5)
  tau_x <- sigmoid20(X[, 1]) * sigmoid20(X[, 2])
  m_x   <- rep(0, n)
  mu0   <- m_x - 0.5 * tau_x
  mu1   <- m_x + 0.5 * tau_x
  Y0    <- rnorm(n, mu0, 1)
  Y1    <- rnorm(n, mu1, 1)
  Y     <- W * Y1 + (1 - W) * Y0
  list(X = X, W = W, Y = Y, tau = tau_x)
}

# sigmoid helper for Design 3 (sharp, slope=12, inflection=1/2)
sigmoid12 <- function(x) 2 / (1 + exp(-12 * (x - 0.5)))

# --------------------------------------------------------------------------
# Design 3 — Sharp Heterogeneity  (Eq. tau_setup, Table 5-6)
#   tau(x) = sigma12(x1) * sigma12(x2)
#   m(x)   = 0
#   e(x)   = 0.5
# --------------------------------------------------------------------------
gen_design3 <- function(n, d, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  X     <- matrix(runif(n * d), nrow = n, ncol = d)
  W     <- rbinom(n, 1, 0.5)
  tau_x <- sigmoid12(X[, 1]) * sigmoid12(X[, 2])
  m_x   <- rep(0, n)
  mu0   <- m_x - 0.5 * tau_x
  mu1   <- m_x + 0.5 * tau_x
  Y0    <- rnorm(n, mu0, 1)
  Y1    <- rnorm(n, mu1, 1)
  Y     <- W * Y1 + (1 - W) * Y0
  list(X = X, W = W, Y = Y, tau = tau_x)
}
