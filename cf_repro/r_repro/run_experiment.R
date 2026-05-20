# run_experiment.R  -  Chay mot (design, method, d) cell
#
# Usage (tu thu muc r_repro/):
#   Rscript run_experiment.R --design 1 --method cf     --d 10
#   Rscript run_experiment.R --design 1 --method knn10  --d 5
#   Rscript run_experiment.R --design 2 --method knn7   --d 4
#   Rscript run_experiment.R --design 3 --method knn100 --d 8
#
# Output: ../results/design{N}/r_{method}_d{d}.csv
#   columns: replication, mse, coverage

suppressPackageStartupMessages({
  library(grf)
  library(FNN)
  library(parallel)
})

# --- Parse args ---
args    <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default) {
  i <- which(args == flag)
  if (length(i) == 0) default else args[i + 1]
}
design <- as.integer(get_arg("--design", "1"))
method <- get_arg("--method", "cf")
d      <- as.integer(get_arg("--d", "10"))

# --- Source helpers ---
sd <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) ".")
source(file.path(sd, "dgp.R"))
source(file.path(sd, "methods.R"))

# --- Paper configs ---
CONFIGS <- list(
  "1" = list(n=500,   n_test=1000, R=500, num_trees=1000,  sample_fraction=0.10),
  "2" = list(n=5000,  n_test=1000, R=25,  num_trees=2000,  sample_fraction=0.50),
  "3" = list(n=10000, n_test=1000, R=40,  num_trees=10000, sample_fraction=0.20)
)
cfg    <- CONFIGS[[as.character(design)]]
gen_fn <- list("1"=gen_design1, "2"=gen_design2, "3"=gen_design3)[[as.character(design)]]

MASTER_SEED <- 42L
cat(sprintf("design=%d  method=%s  d=%d  R=%d  n=%d\n",
            design, method, d, cfg$R, cfg$n))

# --- Single replication ---
run_one <- function(r) {
  seed_tr <- MASTER_SEED * 10000L + r
  seed_te <- MASTER_SEED * 10000L + r + 10000000L
  tr <- gen_fn(cfg$n,      d, seed = seed_tr)
  te <- gen_fn(cfg$n_test, d, seed = seed_te)

  if (method == "cf") {
    # Design 1 = Propensity Forest (Procedure 2, paper Section 6.1).
    # Design 2/3 = Double-Sample Trees (Procedure 1).
    grow_fn <- if (design == 1L) grow_propensity_forest else grow_causal_forest
    forest  <- grow_fn(tr$X, tr$W, tr$Y,
                       num_trees       = cfg$num_trees,
                       sample_fraction = cfg$sample_fraction,
                       seed            = seed_tr)
    res <- predict_cf(forest, te$X)
  } else if (startsWith(method, "knn")) {
    k   <- as.integer(substring(method, 4))
    res <- predict_knn(tr$X, tr$W, tr$Y, te$X, k = k)
  } else {
    stop(paste("Unknown method:", method))
  }

  m <- compute_metrics(res$tau_hat, res$var_hat, te$tau)
  list(replication = r, mse = unname(m["mse"]), coverage = unname(m["coverage"]))
}

# --- Run R replications ---
# CF: grf uses OpenMP internally -> run sequential (no outer parallel)
# kNN: pure R -> use parLapply for speedup
n_cores <- max(1L, detectCores() - 1L)

if (method == "cf") {
  cat(sprintf("CF: sequential (grf uses %d cores internally)\n", n_cores))
  rows <- lapply(seq_len(cfg$R), run_one)
} else if (.Platform$OS.type == "windows") {
  cat(sprintf("kNN: parLapply with %d cores\n", n_cores))
  cl <- makeCluster(n_cores)
  clusterExport(cl, c("cfg", "d", "method", "MASTER_SEED", "gen_fn",
                      "gen_design1", "gen_design2", "gen_design3",
                      "sigmoid20", "sigmoid12", "beta24_pdf",
                      "predict_knn", "compute_metrics"))
  clusterEvalQ(cl, suppressPackageStartupMessages(library(FNN)))
  rows <- parLapply(cl, seq_len(cfg$R), run_one)
  stopCluster(cl)
} else {
  rows <- mclapply(seq_len(cfg$R), run_one, mc.cores = n_cores)
}

# --- Save ---
df       <- do.call(rbind, lapply(rows, as.data.frame))
df       <- df[order(df$replication), ]
out_dir  <- file.path(sd, "..", "results", paste0("design", design))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_path <- file.path(out_dir, sprintf("r_%s_d%d.csv", method, d))
write.csv(df, out_path, row.names = FALSE)

cat(sprintf("\nSaved %d rows -> %s\n", nrow(df), out_path))
cat(sprintf("MSE      = %.4f  (MC-SE %.4f)\n", mean(df$mse),      sd(df$mse)/sqrt(nrow(df))))
cat(sprintf("Coverage = %.4f  (MC-SE %.4f)\n", mean(df$coverage), sd(df$coverage)/sqrt(nrow(df))))
