options(repos = c(CRAN = "https://cloud.r-project.org"))

cat("=== grf ===\n")
if (!requireNamespace("grf", quietly = TRUE)) {
  install.packages("grf")
} else {
  cat("grf da co\n")
}

cat("\n=== FNN ===\n")
if (!requireNamespace("FNN", quietly = TRUE)) {
  install.packages("FNN")
} else {
  cat("FNN da co\n")
}

cat("\n=== Kiem tra ===\n")
pkgs <- c("grf", "FNN")
ok   <- sapply(pkgs, requireNamespace, quietly = TRUE)
for (p in names(ok)) {
  cat(sprintf("  %-10s %s\n", p, ifelse(ok[p], "OK", "FAILED")))
}

if (all(ok)) {
  cat("\nTat ca OK. Chay thu:\n")
  cat("  Rscript run_experiment.R --design 1 --method knn10 --d 10\n")
} else {
  cat("\nCo package that bai.\n")
}
