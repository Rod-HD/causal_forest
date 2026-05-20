# plot_results.R  —  2 figures:
#   1. ITE distribution (true tau density for each design)
#   2. Comparison chart (MSE & Coverage vs d, all methods)
#
# Usage: Rscript plot_results.R
# Output: ../results/fig_ite_distribution.pdf
#         ../results/fig_comparison.pdf

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
})

sd <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) ".")
source(file.path(sd, "dgp.R"))

out_dir <- file.path(sd, "..", "results")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# =============================================================================
# FIGURE 1 — ITE Distribution
#   true tau(X) density at 5000 random test points for each design (d=5)
# =============================================================================

set.seed(42)
n_pts <- 5000
d_fix <- 5

d1 <- gen_design1(n_pts, d_fix, seed = 1)
d2 <- gen_design2(n_pts, d_fix, seed = 2)
d3 <- gen_design3(n_pts, d_fix, seed = 3)

ite_df <- bind_rows(
  data.frame(tau = d1$tau, Design = "Design 1\n(tau = 0, confounding)"),
  data.frame(tau = d2$tau, Design = "Design 2\n(smooth heterogeneity)"),
  data.frame(tau = d3$tau, Design = "Design 3\n(sharp heterogeneity)")
)

p1 <- ggplot(ite_df, aes(x = tau, fill = Design)) +
  geom_density(alpha = 0.75, color = "white", linewidth = 0.4) +
  facet_wrap(~Design, scales = "free", ncol = 3) +
  scale_fill_manual(values = c("#4C72B0", "#DD8452", "#55A868")) +
  labs(
    title = "True ITE Distribution by Simulation Design",
    subtitle = paste0("True tau(X) at ", n_pts, " random test points  |  d = ", d_fix),
    x = expression(tau(X) ~ " — True Individual Treatment Effect"),
    y = "Density"
  ) +
  theme_bw(base_size = 12) +
  theme(
    legend.position = "none",
    strip.background = element_rect(fill = "#f0f0f0"),
    strip.text = element_text(face = "bold", size = 10),
    plot.title = element_text(face = "bold", size = 13),
    panel.grid.minor = element_blank()
  )

ggsave(file.path(out_dir, "fig_ite_distribution.pdf"), p1,
       width = 11, height = 4)
cat("Saved: fig_ite_distribution.pdf\n")

# =============================================================================
# FIGURE 2 — Comparison Chart
#   MSE and Coverage vs d for all methods, all 3 designs
# =============================================================================

load_cell <- function(design, method, d) {
  fp <- file.path(sd, "..", "results",
                  paste0("design", design),
                  sprintf("r_%s_d%d.csv", method, d))
  if (!file.exists(fp)) return(NULL)
  df <- read.csv(fp)
  data.frame(
    design = paste0("Design ", design),
    method = method,
    d      = d,
    mse    = mean(df$mse),
    cov    = mean(df$coverage)
  )
}

cells <- list(
  list(1, "cf",     c(2,5,10,15,20,30)),
  list(1, "knn10",  c(2,5,10,15,20,30)),
  list(1, "knn100", c(2,5,10,15,20,30)),
  list(2, "cf",     c(2,3,4,5,6,8)),
  list(2, "knn7",   c(2,3,4,5,6,8)),
  list(2, "knn50",  c(2,3,4,5,6,8)),
  list(3, "cf",     c(2,3,4,5,6,8)),
  list(3, "knn10",  c(2,3,4,5,6,8)),
  list(3, "knn100", c(2,3,4,5,6,8))
)

rows <- do.call(rbind, Filter(Negate(is.null), lapply(cells, function(x) {
  do.call(rbind, lapply(x[[3]], function(d) load_cell(x[[1]], x[[2]], d)))
})))

# Nicer method labels
rows$Method <- recode(rows$method,
  "cf"     = "Causal Forest",
  "knn7"   = "7-NN",
  "knn10"  = "10-NN",
  "knn50"  = "50-NN",
  "knn100" = "100-NN"
)

rows$Method <- factor(rows$Method,
  levels = c("Causal Forest", "7-NN", "10-NN", "50-NN", "100-NN"))

colors <- c(
  "Causal Forest" = "#2166ac",
  "7-NN"          = "#d6604d",
  "10-NN"         = "#d6604d",
  "50-NN"         = "#f4a582",
  "100-NN"        = "#b2182b"
)
shapes <- c("Causal Forest"=16, "7-NN"=17, "10-NN"=17, "50-NN"=15, "100-NN"=15)

base_theme <- theme_bw(base_size = 11) + theme(
  legend.position  = "bottom",
  legend.title     = element_blank(),
  strip.background = element_rect(fill = "#f0f0f0"),
  strip.text       = element_text(face = "bold"),
  panel.grid.minor = element_blank(),
  plot.title       = element_text(face = "bold", size = 12)
)

p_mse <- ggplot(rows, aes(x = d, y = mse, color = Method,
                           group = Method, shape = Method)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.2) +
  facet_wrap(~design, scales = "free_y", ncol = 3) +
  scale_color_manual(values = colors) +
  scale_shape_manual(values = shapes) +
  labs(title = "Mean Squared Error vs Dimension",
       x = "Dimension d", y = "MSE") +
  base_theme

p_cov <- ggplot(rows, aes(x = d, y = cov, color = Method,
                           group = Method, shape = Method)) +
  geom_hline(yintercept = 0.95, linetype = "dashed",
             color = "grey50", linewidth = 0.6) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2.2) +
  facet_wrap(~design, scales = "free_y", ncol = 3) +
  scale_color_manual(values = colors) +
  scale_shape_manual(values = shapes) +
  scale_y_continuous(limits = c(0.4, 1.0), breaks = seq(0.4, 1.0, 0.1)) +
  labs(title = "Coverage (95% CI) vs Dimension",
       subtitle = "Dashed line = nominal 0.95 target",
       x = "Dimension d", y = "Coverage") +
  base_theme

# Stack MSE + Coverage into one PDF
pdf(file.path(out_dir, "fig_comparison.pdf"), width = 12, height = 9)
gridExtra::grid.arrange(p_mse, p_cov, nrow = 2)
dev.off()
cat("Saved: fig_comparison.pdf\n")

cat("\nDone. Files in results/:\n")
cat("  fig_ite_distribution.pdf\n")
cat("  fig_comparison.pdf\n")
