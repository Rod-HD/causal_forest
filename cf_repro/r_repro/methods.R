# methods.R  -  Estimators using grf + FNN
#
# Causal Forest: grf::causal_forest()
#   Design 1: tune.parameters="all", no honesty splitting override needed
#   Design 2/3: default honest splitting (double-sample equivalent in grf)
#
# k-NN: FNN::get.knnx()
#   variance: (var(S1) + var(S0)) / (k*(k-1))   [paper Eq, p.19]

library(grf)
library(FNN)

# --------------------------------------------------------------------------
# grow_causal_forest
#   Wraps grf::causal_forest with paper hyperparameters.
#   grf uses subsampling + honest splitting internally (IJ variance built-in).
#
#   Design 1: n=500,   B=1000, s=50   => sample.fraction = 50/500  = 0.10
#   Design 2: n=5000,  B=2000, s=2500 => sample.fraction = 2500/5000 = 0.50
#   Design 3: n=10000, B=10000, s=2000 => sample.fraction = 2000/10000 = 0.20
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
#   var_hat = (var(S1) + var(S0)) / (k*(k-1))
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
