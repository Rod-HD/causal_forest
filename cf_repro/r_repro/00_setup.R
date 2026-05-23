options(repos = c(CRAN = "https://cloud.r-project.org"))

# Core simulation packages
core_pkgs <- c("grf", "FNN")

# Shiny app packages (for app.R, app_real.R, app_demo.R)
shiny_pkgs <- c("shiny", "ggplot2", "plotly", "dplyr", "scales")

# Live demo packages (for app_demo.R only)
demo_pkgs <- c("ranger", "DT", "pROC", "gridExtra")

all_pkgs <- c(core_pkgs, shiny_pkgs, demo_pkgs)

install_if_missing <- function(p) {
  cat(sprintf("=== %s ===\n", p))
  if (!requireNamespace(p, quietly = TRUE)) {
    install.packages(p)
  } else {
    cat(sprintf("%s da co\n", p))
  }
}

invisible(lapply(all_pkgs, install_if_missing))

cat("\n=== Kiem tra ===\n")
ok <- sapply(all_pkgs, requireNamespace, quietly = TRUE)
for (p in names(ok)) {
  cat(sprintf("  %-12s %s\n", p, ifelse(ok[p], "OK", "FAILED")))
}

if (all(ok)) {
  cat("\nTat ca OK. Chay thu:\n")
  cat("  Rscript run_experiment.R --design 1 --method knn10 --d 10\n")
  cat("  Rscript -e \"shiny::runApp('app_demo.R', launch.browser=TRUE)\"\n")
} else {
  cat("\nCo package that bai.\n")
}
