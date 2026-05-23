# Design — Live Demo Uplift App

## Architecture

```
cf_repro/r_repro/
├── app_demo.R          ← New app, entry point
├── learners.R          ← New: 6 uplift learners
├── metrics.R           ← New: AUUC, Qini, AUC
├── report_export.R     ← New: PNG export helper
├── methods.R           ← (existing, reused)
├── app_real.R          ← (existing, untouched)
└── app.R               ← (existing, untouched)

cf_repro/results/
└── demo_exports/       ← New: PNG report outputs
```

## Component diagram

```
                         ┌──────────────────────────────┐
                         │       app_demo.R (UI)        │
                         └──────────┬───────────────────┘
                                    │
            ┌───────────────────────┼─────────────────────────┐
            │                       │                         │
            ▼                       ▼                         ▼
   ┌────────────────┐     ┌──────────────────┐     ┌───────────────────┐
   │  learners.R    │     │   metrics.R      │     │  report_export.R  │
   │  - fit_s()     │     │  - auuc()        │     │  - export_png()   │
   │  - fit_t()     │     │  - qini()        │     └───────────────────┘
   │  - fit_x()     │     │  - auc_score()   │
   │  - fit_ctree() │     │  - uplift_data() │
   │  - fit_cforest()│    │  - cum_uplift()  │
   │  - fit_clf()   │     └──────────────────┘
   └─────┬──────────┘                ▲
         │                           │
         ▼                           │
   ┌──────────────────┐              │
   │  methods.R       │──────────────┘
   │  (grow_cf, etc)  │
   └──────────────────┘
```

## Data flow

```
[Dataset selector] ──┐
                     ├──► [load_raw()] ──► df ──┐
[Outcome selector] ──┘                          │
                                                ▼
                                       [prepare_xyw()] ──► (X, W, Y)
                                                ▼
                                       [80/20 split, seed=42]
                                                ▼
                              ┌─────────────────┴─────────────────┐
                              ▼                                   ▼
                       [fit all 6 learners]                  [X_test, W_test, Y_test]
                              │                                   │
                              ▼                                   │
                       List of 6 models                           │
                              │                                   │
                              ▼                                   │
                       [predict each on X_test]  ◄────────────────┘
                              │
                              ▼
                       results_rv: list of 6 (tau_hat, ci_lower, ci_upper, var_imp)
                              │
              ┌───────────────┼───────────────┬─────────────────┐
              ▼               ▼               ▼                 ▼
        [Tab 2: table]  [Tab 3: curves]  [Tab 4: detail]  [Tab 5: upload retrain]
```

## Learners — implementation details

### 1. Standard Classifier (baseline, AUC only)

**Mục đích:** Predict `P(Y=1 | X)` mà không quan tâm W. Dùng để tính AUC làm baseline so sánh.

**Implementation:** `ranger::ranger()` (random forest classifier nhanh hơn `randomForest` 5×).

```r
fit_standard_clf <- function(X, W, Y, ...) {
  df <- data.frame(X, Y = factor(Y))
  ranger(Y ~ ., data = df, num.trees = 500,
         probability = TRUE, num.threads = parallel::detectCores())
}
```

**Predict:** `p_treat`, không có tau. Set `tau_hat = NA`, chỉ tính AUC.

### 2. S-Learner

**Mục đích:** Train 1 model duy nhất với W là feature.

```r
fit_s_learner <- function(X, W, Y, num.trees = 500) {
  df <- data.frame(X, W = W, Y = Y)
  is_binary <- all(Y %in% c(0, 1))
  if (is_binary) {
    model <- ranger(Y ~ ., data = df, ..., probability = TRUE,
                    classification = TRUE)
  } else {
    model <- ranger(Y ~ ., data = df, num.trees = num.trees)
  }
  list(model = model, is_binary = is_binary, feature_names = c(colnames(X), "W"))
}

predict_s_learner <- function(fit, X) {
  X1 <- data.frame(X, W = 1); X0 <- data.frame(X, W = 0)
  if (fit$is_binary) {
    p1 <- predict(fit$model, X1)$predictions[, "1"]
    p0 <- predict(fit$model, X0)$predictions[, "1"]
  } else {
    p1 <- predict(fit$model, X1)$predictions
    p0 <- predict(fit$model, X0)$predictions
  }
  tau_hat <- p1 - p0
  list(tau_hat = tau_hat, ci_lower = NA, ci_upper = NA)
}
```

**Variance:** S-Learner không có closed-form CI. **Quyết định:** Set `ci_lower = NA, ci_upper = NA` (bỏ qua CI cho meta-learners). Bootstrap 10× sẽ tăng training time 10× → không kịp demo 5 phút. UI sẽ hiển thị "—" cho CI của S/T/X-Learner và tooltip giải thích: *"CI chỉ có với Causal Forest/Tree do paper-grade IJ variance estimator. Meta-learners không có closed-form CI."*

### 3. T-Learner

**Mục đích:** Train 2 model riêng cho W=0 và W=1.

```r
fit_t_learner <- function(X, W, Y, num.trees = 500) {
  idx0 <- W == 0; idx1 <- W == 1
  m0 <- ranger(Y ~ ., data = data.frame(X[idx0,], Y = Y[idx0]), ...)
  m1 <- ranger(Y ~ ., data = data.frame(X[idx1,], Y = Y[idx1]), ...)
  list(m0 = m0, m1 = m1, is_binary = all(Y %in% c(0,1)))
}

predict_t_learner <- function(fit, X) {
  p0 <- predict(fit$m0, data.frame(X))$predictions
  p1 <- predict(fit$m1, data.frame(X))$predictions
  if (fit$is_binary) { p0 <- p0[,"1"]; p1 <- p1[,"1"] }
  list(tau_hat = p1 - p0, ci_lower = NA, ci_upper = NA)
}
```

### 4. X-Learner (Künzel et al. 2019)

**Mục đích:** T-Learner + cross-fitting + propensity weighting.

```r
fit_x_learner <- function(X, W, Y, num.trees = 500) {
  # Stage 1: T-Learner
  t_fit <- fit_t_learner(X, W, Y, num.trees)

  # Stage 2: Impute counterfactual residuals
  idx0 <- W == 0; idx1 <- W == 1
  D1 <- Y[idx1] - predict(t_fit$m0, data.frame(X[idx1,]))$predictions
  D0 <- predict(t_fit$m1, data.frame(X[idx0,]))$predictions - Y[idx0]
  if (t_fit$is_binary) {
    D1 <- Y[idx1] - predict(t_fit$m0, data.frame(X[idx1,]))$predictions[,"1"]
    D0 <- predict(t_fit$m1, data.frame(X[idx0,]))$predictions[,"1"] - Y[idx0]
  }

  # Stage 3: Train tau models on residuals
  tau1_model <- ranger(D ~ ., data = data.frame(X[idx1,], D = D1), num.trees = num.trees)
  tau0_model <- ranger(D ~ ., data = data.frame(X[idx0,], D = D0), num.trees = num.trees)

  # Stage 4: Propensity (constant for randomized data, but estimate to be safe)
  e_model <- ranger(W ~ ., data = data.frame(X, W = factor(W)),
                    probability = TRUE, num.trees = num.trees)

  list(tau0 = tau0_model, tau1 = tau1_model, e_model = e_model,
       is_binary = t_fit$is_binary)
}

predict_x_learner <- function(fit, X) {
  tau0_hat <- predict(fit$tau0, data.frame(X))$predictions
  tau1_hat <- predict(fit$tau1, data.frame(X))$predictions
  e_hat <- predict(fit$e_model, data.frame(X))$predictions[, "1"]
  tau_hat <- e_hat * tau0_hat + (1 - e_hat) * tau1_hat
  list(tau_hat = tau_hat, ci_lower = NA, ci_upper = NA)
}
```

### 5. Causal Tree (small ensemble)

**Quyết định:** Dùng `grf::causal_forest` với `num.trees = 50` — KHÔNG dùng `causalTree` package cũ.

**Lý do:**
- `causalTree` (Athey & Imbens 2016) chỉ có trên GitHub, không có trên CRAN, install qua `devtools::install_github("susanathey/causalTree")` dễ fail trên Windows do C++ compilation requirements
- Single tree (1 cây) bias quá lớn, AUUC có thể âm → lớp hiểu sai bản chất
- 50-tree small ensemble giữ tinh thần "tree-based, ít cây hơn forest" mà vẫn stable

**UI label:** "Causal Tree (small ensemble, 50)" — honest về implementation.

```r
fit_causal_tree <- function(X, W, Y, ...) {
  causal_forest(X, Y, W, num.trees = 50, honesty = TRUE,
                sample.fraction = 0.5, ...)
}

predict_causal_tree <- function(fit, X_test) {
  preds <- predict(fit, X_test, estimate.variance = TRUE)
  se <- sqrt(pmax(preds$variance.estimates, 0))
  list(tau_hat  = preds$predictions,
       ci_lower = preds$predictions - 1.96 * se,
       ci_upper = preds$predictions + 1.96 * se)
}
```

### 6. Causal Forest

**Tái dùng** `grow_causal_forest()` từ `methods.R`. Default `num.trees = 500`.

## Metrics — implementation

### AUUC (Area Under Uplift Curve)

```r
auuc <- function(tau_hat, W, Y) {
  n <- length(tau_hat)
  ord <- order(tau_hat, decreasing = TRUE)
  W_ord <- W[ord]; Y_ord <- Y[ord]
  # Cumulative uplift at each rank k
  cum_treat <- cumsum(Y_ord * W_ord) / pmax(cumsum(W_ord), 1)
  cum_ctrl  <- cumsum(Y_ord * (1 - W_ord)) / pmax(cumsum(1 - W_ord), 1)
  uplift_k <- (cum_treat - cum_ctrl) * seq_len(n)
  # Area = trapezoidal sum normalized
  sum(uplift_k) / n^2
}
```

### Qini coefficient

Đã có trong `compute_uplift()` của `app_real.R`. Refactor sang `metrics.R`:

```r
qini <- function(tau_hat, W, Y) {
  n <- length(tau_hat)
  ord <- order(tau_hat, decreasing = TRUE)
  W_o <- W[ord]; Y_o <- Y[ord]
  # Qini cum gain (treated conversions - scaled control conversions)
  n_treat <- sum(W); n_ctrl <- sum(1 - W)
  cum_t <- cumsum(Y_o * W_o)
  cum_c <- cumsum(Y_o * (1 - W_o)) * (n_treat / max(n_ctrl, 1))
  gain <- cum_t - cum_c
  random_gain <- seq_len(n) * (sum(Y * W) - sum(Y * (1 - W)) * n_treat / n_ctrl) / n
  sum(gain - random_gain) / (n * sum(Y * W))
}
```

### AUC (cho Standard Classifier)

```r
auc_score <- function(prob, y) {
  if (!requireNamespace("pROC", quietly = TRUE)) {
    # manual computation if pROC missing
    ord <- order(prob)
    y_ord <- y[ord]
    ranks <- rank(prob)
    pos <- sum(y == 1); neg <- sum(y == 0)
    (sum(ranks[y == 1]) - pos * (pos + 1) / 2) / (pos * neg)
  } else {
    as.numeric(pROC::auc(y, prob, quiet = TRUE))
  }
}
```

## UI layout

### Top bar
- Title: "Causal Forest — Live Demo for CS114"
- Subtitle: dataset · outcome · n_train/n_test · trained timestamp

### Sidebar (3/12 cols)
- **Dataset card:**
  - Dataset dropdown (Hillstrom default · Lenta · Criteo · Upload CSV)
  - Hillstrom group radio (only when Hillstrom)
  - Outcome dropdown
  - Description box
- **Training card:**
  - `num.trees` slider (default 500, range 200–2000)
  - Train all 6 learners button → trigger reactive
  - Progress indicator
- **Status card:**
  - List of 6 learners with ✅/⏳/❌ status
  - Total train time

### Main panel (9/12 cols) — 5 tabs

#### Tab 1: Dataset Overview
- Left: 5 info bullets (Name, Size, Treatment, Outcome, Train/Test split)
- Right: 2 plotly charts
  - Bar chart: W=0 vs W=1 counts
  - Density/bar: Y distribution stratified by W
- Bottom: "Baselines section" — list 6 learners that will be compared

#### Tab 2: Quantitative Comparison
- Top: Table 6 rows × 4 cols (Method · AUUC · Qini · AUC)
- Bottom: Bar chart AUUC, ordered desc, Causal Forest highlighted

#### Tab 3: Uplift / Qini Curves
- Left (60% width): Uplift curve plotly, 6 lines + Random baseline
  - Checkbox group above plot to hide/show methods
- Right (40% width):
  - Box "Key Observations" — 3 auto-generated findings
  - Box "Takeaway" — 1-line conclusion

#### Tab 4: Customer Decision
- **Layout:** 2 columns: left = picker (3 sub-tabs), right = detail panel
- **Left column — picker (3 sub-tabs):**
  - **4a — Browse all:** DT table of X_test, click row to select
  - **4b — Random pick:** Big "🎲 Pick Random Customer" button + "Last picked" indicator
  - **4c — Top N:** Slider N (default 20, 5–500) + DT table top N by |τ̂|
- **Right column — detail panel:**
  - Big number: `τ̂ = 0.1234` (color: green if >0, red if <0)
  - CI: `[lower, upper]`
  - Decision badge: huge "✅ TREAT" / "🚫 DO NOT TREAT"
  - Threshold slider: range −0.2 to +0.2, step 0.01, default 0.0
  - Decision rule text: "Recommend TREAT if τ̂ > threshold AND CI_lower > 0"
  - Feature values table
  - Mini bar chart: feature contribution (using `grf::variable_importance` weighted by feature deviation from population mean)
  - Population comparison sentence: "Customer này có τ̂ cao hơn X% dân số"

#### Tab 5: Upload CSV
- File input
- Auto-detect column dropdowns (W, Y, X)
- "Train all 6 learners on uploaded CSV" button
- After train: notification → all other tabs auto-update with new data

### Color scheme
- Causal Forest: `#2166ac` (deep blue) — primary
- Causal Tree: `#5aa1d3` (lighter blue)
- X-Learner: `#9b59b6` (purple)
- T-Learner: `#e67e22` (orange)
- S-Learner: `#f1c40f` (yellow)
- Standard Classifier: `#7f8c8d` (gray)
- TREAT badge: `#27ae60`
- DO NOT TREAT badge: `#e74c3c`

## Reactive structure

```r
results_rv <- reactiveVal(NULL)
# Structure when populated:
# list(
#   dataset_label = "Hillstrom",
#   outcome       = "visit",
#   X_train, W_train, Y_train,
#   X_test,  W_test,  Y_test,
#   X_cols    = c("recency", "history", ...),
#   trained_at = Sys.time(),
#   models = list(
#     standard_clf  = list(model = ..., probs = ..., auc = ...),
#     s_learner     = list(model = ..., tau_hat = ..., ci_lower = ..., ci_upper = ..., auuc = ..., qini = ...),
#     t_learner     = list(...),
#     x_learner     = list(...),
#     causal_tree   = list(...),
#     causal_forest = list(...)
#   )
# )

selected_customer_rv <- reactiveVal(NULL)
# integer index into X_test
```

## Train flow (when user clicks Train button)

```
1. notification("Step 1/8 — Loading data")
2. df <- load raw rds
3. X, W, Y <- prepare matrix; train/test split seed=42
4. notification("Step 2/8 — Training Standard Classifier")
5. fit_standard_clf() → store in models$standard_clf
6. notification("Step 3/8 — Training S-Learner")
7. ... (similar for each learner)
9. notification("Step 8/8 — Computing metrics")
10. for each model: compute auuc, qini
11. results_rv(<populated list>)
12. notification("Done in X seconds!")
```

## Performance plan (NF-1)

Target: ≤30s on Hillstrom n=42K, 6 learners × 500 trees each.

| Learner | Est. time | Trick |
|---|---|---|
| Standard Classifier (ranger) | ~2s | parallel threads |
| S-Learner (ranger) | ~3s | parallel threads |
| T-Learner (ranger × 2) | ~4s | parallel threads |
| X-Learner (ranger × 5) | ~8s | parallel threads |
| Causal Tree (grf 50) | ~2s | small num.trees |
| Causal Forest (grf 500) | ~10s | grf OpenMP |
| **Total** | ~29s | within budget |

If exceed budget: reduce default `num.trees` to 300 for non-grf learners.

## PNG export (US-6)

Dùng `gridExtra::grid.arrange` + `ggsave`:

```r
export_report <- function(results_rv, selected_customer, out_path) {
  p1 <- table_comparison_grob(results_rv)   # via gridExtra::tableGrob
  p2 <- plot_auuc_bar(results_rv)            # ggplot
  p3 <- plot_uplift_curves(results_rv)       # ggplot
  p4 <- if (!is.null(selected_customer)) plot_customer_detail(results_rv, selected_customer) else NULL
  layout <- if (is.null(p4)) {
    gridExtra::grid.arrange(p1, p2, p3, nrow = 2, layout_matrix = rbind(c(1,1), c(2,3)))
  } else {
    gridExtra::grid.arrange(p1, p2, p3, p4, nrow = 2)
  }
  ggsave(out_path, layout, width = 14, height = 10, dpi = 150)
}
```

## Risk & mitigations

| Risk | Mitigation |
|---|---|
| 6 learners train > 30s | Default `num.trees=300` cho ranger learners |
| Demo crash giữa chừng | Wrap mọi train trong `tryCatch`, error → notification đỏ |
| CSV upload sai format | `detect_columns()` + cho override + validation message |
| `ranger` package chưa có | Add to `00_setup.R` install check |
| AUC chỉ áp dụng Standard Classifier nhưng UI muốn show cho cả 6 | Show "—" cho 5 learner uplift; AUC = scoring of Y, không phải τ̂ |
| Feature contribution cho 1 customer là approximation | Document trong tooltip: "Approximate via local feature importance, not SHAP" |

## Dependencies

Add to `00_setup.R`:
```r
required_pkgs <- c("grf", "FNN", "shiny", "ggplot2", "plotly", "dplyr",
                   "scales", "ranger",   # NEW
                   "DT",                  # NEW for tables in Tab 4
                   "pROC",                # NEW for AUC (optional)
                   "gridExtra"            # NEW for PNG export
)
```
