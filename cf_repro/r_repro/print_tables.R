# =============================================================================
# print_tables.R  —  So sánh kết quả R với paper
#
# Usage: Rscript print_tables.R
# =============================================================================

# ── Paper values (from TeX source arXiv:1510.04342v4) ─────────────────────────

PAPER <- list(
  d1 = list(
    methods = c("cf", "knn10", "knn100"),
    labels  = c("CF", "10-NN", "100-NN"),
    d_vals  = c(2, 5, 10, 15, 20, 30),
    mse = list(
      cf     = c(0.02, 0.02, 0.02, 0.02, 0.02, 0.02),
      knn10  = c(0.21, 0.24, 0.28, 0.31, 0.32, 0.33),
      knn100 = c(0.09, 0.12, 0.12, 0.13, 0.13, 0.13)
    ),
    cov = list(
      cf     = c(0.95, 0.94, 0.94, 0.91, 0.88, 0.85),
      knn10  = c(0.93, 0.92, 0.91, 0.90, 0.89, 0.89),
      knn100 = c(0.62, 0.52, 0.51, 0.48, 0.49, 0.48)
    )
  ),
  d2 = list(
    methods = c("cf", "knn7", "knn50"),
    labels  = c("CF", "7-NN", "50-NN"),
    d_vals  = c(2, 3, 4, 5, 6, 8),
    mse = list(
      cf    = c(0.04, 0.03, 0.03, 0.03, 0.02, 0.03),
      knn7  = c(0.29, 0.29, 0.30, 0.31, 0.34, 0.38),
      knn50 = c(0.04, 0.05, 0.08, 0.11, 0.15, 0.21)
    ),
    cov = list(
      cf    = c(0.97, 0.96, 0.94, 0.93, 0.93, 0.90),
      knn7  = c(0.93, 0.93, 0.93, 0.92, 0.91, 0.90),
      knn50 = c(0.94, 0.92, 0.86, 0.77, 0.68, 0.57)
    )
  ),
  d3 = list(
    methods = c("cf", "knn10", "knn100"),
    labels  = c("CF", "10-NN", "100-NN"),
    d_vals  = c(2, 3, 4, 5, 6, 8),
    mse = list(
      cf     = c(0.02, 0.02, 0.02, 0.02, 0.02, 0.03),
      knn10  = c(0.20, 0.20, 0.21, 0.22, 0.24, 0.29),
      knn100 = c(0.02, 0.03, 0.06, 0.09, 0.15, 0.26)
    ),
    cov = list(
      cf     = c(0.94, 0.90, 0.84, 0.81, 0.79, 0.73),
      knn10  = c(0.93, 0.93, 0.93, 0.93, 0.92, 0.90),
      knn100 = c(0.94, 0.90, 0.78, 0.67, 0.58, 0.45)
    )
  )
)

# ── Load our results ──────────────────────────────────────────────────────────

load_results <- function(design, method, d) {
  fp <- file.path("..", "results", paste0("design", design),
                  sprintf("r_%s_d%d.csv", method, d))
  if (!file.exists(fp)) return(list(mse = NA, cov = NA, se_mse = NA, se_cov = NA))
  df <- read.csv(fp)
  R  <- nrow(df)
  list(
    mse    = mean(df$mse),
    cov    = mean(df$coverage),
    se_mse = sd(df$mse) / sqrt(R),
    se_cov = sd(df$coverage) / sqrt(R)
  )
}

# ── Table printer ─────────────────────────────────────────────────────────────

W <- 90

box <- function(title, sub = "") {
  cat("\n")
  cat(paste0("╔", strrep("═", W-2), "╗\n"))
  cat(paste0("║  ", formatC(title, width = W-4, flag = "-"), "║\n"))
  if (nchar(sub) > 0)
    cat(paste0("║  ", formatC(sub, width = W-4, flag = "-"), "║\n"))
  cat(paste0("╠", strrep("═", W-2), "╣\n"))
}

print_design_table <- function(design_key, design_num) {
  p   <- PAPER[[design_key]]
  hdr <- sprintf("  %-8s  %3s  %10s  %10s  %9s  %10s  %10s  %8s",
                 "Method", "d", "Paper MSE", "Ours MSE", "D MSE",
                 "Paper Cov", "Ours Cov", "D Cov")
  cat(paste0("║", hdr, "  ║\n"))
  cat(paste0("╠", strrep("═", W-2), "╣\n"))

  prev_method <- ""
  for (mi in seq_along(p$methods)) {
    m  <- p$methods[mi]
    ml <- p$labels[mi]
    for (di in seq_along(p$d_vals)) {
      dv <- p$d_vals[di]
      r  <- load_results(design_num, m, dv)

      pm  <- p$mse[[m]][di]
      pc  <- p$cov[[m]][di]
      dm  <- r$mse - pm
      dc  <- r$cov - pc
      sm  <- if (!is.na(dm) && dm >  0.005) "+" else if (!is.na(dm) && dm < -0.005) "-" else "="
      sc  <- if (!is.na(dc) && dc >  0.02)  "+" else if (!is.na(dc) && dc < -0.02)  "-" else "="

      if (prev_method != "" && prev_method != ml)
        cat(paste0("║", strrep("─", W-2), "║\n"))
      prev_method <- ml

      row <- sprintf("  %-8s  %3d  %10.4f  %10s  %+8s%s  %10.3f  %10s  %+7s%s",
        ml, dv, pm,
        if (is.na(r$mse)) "   -  " else sprintf("%.4f", r$mse),
        if (is.na(dm))    "   -  " else sprintf("%.4f", dm), sm,
        pc,
        if (is.na(r$cov)) "  -  " else sprintf("%.3f", r$cov),
        if (is.na(dc))    "  -  " else sprintf("%.3f", dc), sc
      )
      cat(paste0("║", row, "  ║\n"))
    }
  }
  cat(paste0("╚", strrep("═", W-2), "╝\n"))
  cat("  D = Ours - Paper  |  + cao hon  - thap hon  = trong nguong (<0.02 cov, <0.005 mse)\n")
}

# ── Save output to file (split=TRUE = in ra cả terminal lẫn file) ────────────
out_file <- file.path("..", "results", "comparison_table.txt")
con <- file(out_file, open = "w", encoding = "UTF-8")
sink(con, split = TRUE)

# ── Print all tables ──────────────────────────────────────────────────────────

box("COMPARISON TABLE  |  Wager & Athey (2018) JASA  —  Paper vs Ours (grf + FNN)",
    sprintf("Generated: %s", format(Sys.time(), "%Y-%m-%d %H:%M")))
box("TABLE 1+2  |  DESIGN 1 — Confounding  (prop_setup)",
    "n=500, tau=0, e(x)=Beta(2,4), PROPENSITY TREES B=1000 s=50  |  R=500  |  kNN: k=10,100")
print_design_table("d1", 1)

box("TABLE 3+4  |  DESIGN 2 — Smooth Heterogeneity  (tau0_setup)",
    "n=5000, tau=sigma20*sigma20, e=0.5, DOUBLE-SAMPLE B=2000 s=2500  |  R=25  |  kNN: k=7,50")
print_design_table("d2", 2)

box("TABLE 5+6  |  DESIGN 3 — Sharp Heterogeneity  (tau_setup)",
    "n=10000, tau=sigma12*sigma12, e=0.5, DOUBLE-SAMPLE B=10000 s=2000  |  R=40  |  kNN: k=10,100")
print_design_table("d3", 3)

sink()
close(con)
cat(sprintf("\nSaved -> %s\n", normalizePath(out_file)))
