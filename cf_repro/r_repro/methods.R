# methods.R  -  Estimators using grf + FNN
#
# Causal Forest (paper Section 6):
#   Design 1: PROPENSITY FOREST (Procedure 2) — paper Section 6.1 requires this
#             for the confounding setup. Emulated in grf 2.x by fitting
#             regression_forest(X, W) for W.hat and passing it explicitly
#             into causal_forest() (grf-labs recommended replacement for the
#             deprecated propensity_forest()).
#   Design 2/3: DOUBLE-SAMPLE TREES (Procedure 1) — default honest splitting
#               in grf::causal_forest().
#
# k-NN: FNN::get.knnx()
#   Paper Eq. 26 (p.19):  V_hat = (V1 + V0) / (k*(k-1))   where V_w = sum of
#   squared deviations. Since R's var() = V_w / (k-1), the formula simplifies
#   to  (var(s1) + var(s0)) / k  — that is what we implement below.

library(grf)
library(FNN)

# --------------------------------------------------------------------------
# grow_causal_forest  (Procedure 1 — Double-Sample Trees)
#   Used for Design 2 and Design 3.
#
#   Design 2: n=5000,  B=2000,  s=2500 => sample.fraction = 0.50
#   Design 3: n=10000, B=10000, s=2000 => sample.fraction = 0.20
# --------------------------------------------------------------------------
grow_causal_forest <- function(X_train, W_train, Y_train,
                                num_trees, sample_fraction,
                                min_node_size = 1,
                                seed = NULL) {
  cf <- causal_forest(
    X                = X_train,
    Y                = Y_train,
    W                = W_train,
    num.trees        = num_trees,
    sample.fraction  = sample_fraction,
    min.node.size    = min_node_size,
    honesty          = TRUE,
    honesty.fraction = 0.5,
    seed             = seed
  )
  cf
}

# --------------------------------------------------------------------------
# grow_propensity_forest  (Procedure 2 — Propensity Forest)
#   Used for Design 1 (confounding setup, paper Section 6.1).
#
#   grf >= 2.0 removed propensity_forest(). The grf-labs recommended
#   replacement is to fit a regression_forest on (X, W) to obtain W.hat,
#   then pass it explicitly to causal_forest(). This forces the causal
#   forest to use the propensity estimate that the paper's Procedure 2
#   embeds in its splitting target, instead of grf's internal OOB
#   orthogonalization.
#
#   Y.hat is left at grf default (OOB residual-on-mean), which mirrors the
#   paper's setup where m(x) is unknown and must be learned.
#
#   Design 1: n=500, B=1000, s=50 => sample.fraction = 0.10
# --------------------------------------------------------------------------
grow_propensity_forest <- function(X_train, W_train, Y_train,
                                    num_trees, sample_fraction,
                                    min_node_size = 1,
                                    seed = NULL) {
  forest_W <- regression_forest(
    X               = X_train,
    Y               = W_train,
    num.trees       = num_trees,
    sample.fraction = sample_fraction,
    honesty         = TRUE,
    seed            = seed
  )
  W_hat <- predict(forest_W)$predictions

  cf <- causal_forest(
    X                = X_train,
    Y                = Y_train,
    W                = W_train,
    W.hat            = W_hat,
    num.trees        = num_trees,
    sample.fraction  = sample_fraction,
    min.node.size    = min_node_size,
    honesty          = TRUE,
    honesty.fraction = 0.5,
    seed             = seed
  )
  cf
}

# --------------------------------------------------------------------------
# predict_cf
#   Returns tau_hat and var_hat at X_test using grf's built-in IJ variance.
# --------------------------------------------------------------------------
predict_cf <- function(forest, X_test) {
  p       <- predict(forest, newdata = X_test, estimate.variance = TRUE)
  tau_hat <- as.numeric(p$predictions)
  var_hat <- pmax(as.numeric(p$variance.estimates), 0)
  list(tau_hat = tau_hat, var_hat = var_hat)
}

# --------------------------------------------------------------------------
# predict_knn
#   k-NN matching (paper Eq. 26).
#   Paper formula  V_hat = (V1+V0)/(k*(k-1))  with V_w = sum of squared
#   deviations. Since R's var() = V_w/(k-1), the implementation collapses to
#   (var(s1)+var(s0))/k.
# --------------------------------------------------------------------------
predict_knn <- function(X_train, W_train, Y_train, X_test, k) {
  idx0 <- which(W_train == 0)
  idx1 <- which(W_train == 1)
  X0   <- X_train[idx0, , drop = FALSE]
  X1   <- X_train[idx1, , drop = FALSE]
  Y0   <- Y_train[idx0]
  Y1   <- Y_train[idx1]

  nn0 <- FNN::get.knnx(data = X0, query = X_test, k = k)$nn.index
  nn1 <- FNN::get.knnx(data = X1, query = X_test, k = k)$nn.index

  n_test  <- nrow(X_test)
  tau_hat <- numeric(n_test)
  var_hat <- numeric(n_test)

  for (i in seq_len(n_test)) {
    s0 <- Y0[nn0[i, ]]
    s1 <- Y1[nn1[i, ]]
    tau_hat[i] <- mean(s1) - mean(s0)
    # Paper: (V(S1)+V(S0))/(k*(k-1)) where V = sum of squared deviations
    # = (var_ddof1*(k-1)) / (k*(k-1)) = var_ddof1 / k
    var_hat[i] <- (var(s1) + var(s0)) / k
  }
  list(tau_hat = tau_hat, var_hat = var_hat)
}

# --------------------------------------------------------------------------
# compute_metrics
# --------------------------------------------------------------------------
compute_metrics <- function(tau_hat, var_hat, tau_true) {
  mse      <- mean((tau_hat - tau_true)^2)
  se_hat   <- sqrt(pmax(var_hat, 0))
  covered  <- tau_true >= (tau_hat - 1.96 * se_hat) &
              tau_true <= (tau_hat + 1.96 * se_hat)
  coverage <- mean(covered)
  c(mse = mse, coverage = coverage)
}
