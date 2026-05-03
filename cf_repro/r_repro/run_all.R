# run_all.R  -  Chay toan bo 54 cells
#
# Usage:
#   Rscript run_all.R              # tat ca 3 designs
#   Rscript run_all.R --design 1   # chi design 1
#
# Uoc tinh thoi gian (16 cores):
#   Design 1 CF  ~10 min  | Design 1 kNN  ~2 min
#   Design 2 CF  ~15 min  | Design 2 kNN  ~1 min
#   Design 3 CF  ~3-4h    | Design 3 kNN  ~10 min

args        <- commandArgs(trailingOnly = TRUE)
get_arg     <- function(flag, default) { i <- which(args==flag); if (!length(i)) default else args[i+1] }
only_design <- as.integer(get_arg("--design", "0"))

rscript <- file.path(R.home("bin"), "Rscript")
sd      <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) ".")

tasks <- rbind(
  expand.grid(design=1, method=c("cf","knn10","knn100"), d=c(2,5,10,15,20,30), stringsAsFactors=FALSE),
  expand.grid(design=2, method=c("cf","knn7","knn50"),   d=c(2,3,4,5,6,8),    stringsAsFactors=FALSE),
  expand.grid(design=3, method=c("cf","knn10","knn100"), d=c(2,3,4,5,6,8),    stringsAsFactors=FALSE)
)

if (only_design > 0) tasks <- tasks[tasks$design == only_design, ]
total   <- nrow(tasks)
t_start <- proc.time()["elapsed"]
cat(sprintf("Total cells: %d\n\n", total))

for (i in seq_len(total)) {
  tsk <- tasks[i, ]
  cat(sprintf("[%d/%d] design=%d  method=%-7s  d=%d\n", i, total, tsk$design, tsk$method, tsk$d))
  t0 <- proc.time()["elapsed"]

  system2(rscript,
    args = c(file.path(sd, "run_experiment.R"),
             "--design", tsk$design, "--method", tsk$method, "--d", tsk$d),
    stdout = "", stderr = "")

  elapsed <- proc.time()["elapsed"] - t0
  total_e <- proc.time()["elapsed"] - t_start
  eta     <- (total_e / i) * (total - i)
  cat(sprintf("  done %.1fs | total %.1fm | ETA %.1fm\n\n", elapsed, total_e/60, eta/60))
}

cat(sprintf("All done in %.1f minutes.\n", (proc.time()["elapsed"] - t_start) / 60))
