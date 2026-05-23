# Tech — Technology Stack & Standards

## Language & Runtime

- **R** 4.4+ (Rtools45 trên Windows)
- Không dùng Python; toàn bộ logic bằng R.

## Core R Packages

| Package | Mục đích | Source |
|---------|----------|--------|
| `grf` | Causal Forest (grow, predict, variance, variable importance) | CRAN |
| `FNN` | k-Nearest Neighbors (fast kNN search via `get.knnx`) | CRAN |
| `shiny` | Interactive web dashboards | CRAN |
| `ggplot2` | Static plotting (base cho plotly) | CRAN |
| `plotly` | Interactive Plotly charts (wrap ggplot) | CRAN |
| `dplyr` | Data manipulation | CRAN |
| `tidyr` | Data reshaping (dùng trong `plot_results.R`) | CRAN |
| `scales` | Number formatting (comma, percent) | CRAN |
| `gridExtra` | Multi-panel PDF layout | CRAN |
| `parallel` | Parallel kNN execution (parLapply trên Windows) | base R |

## Architecture Principles

### Simulation Pipeline
```
dgp.R (sinh data) → methods.R (train/predict) → run_experiment.R (1 cell)
                                                → run_all.R (54 cells)
                                                → print_tables.R (so sánh)
                                                → plot_results.R (figures)
```

### Real-Data Pipeline
```
prepare_real_data.R (download + preprocess → *_raw.rds)
    → train_pretrained.R (train CF → *.rds + *_cate.csv)
        → app_real.R (load pre-trained hoặc custom re-train)
```

### Shiny Apps
- `app.R`: **Viewer only** — đọc CSV pre-computed, không gọi grf runtime.
- `app_real.R`: **Dual mode** — auto-load pre-trained `.rds` + optional custom Run (gọi `grf::causal_forest()` live).

## Coding Standards

- **Seed scheme**: Replication `r` dùng `42*10000+r` (train) và `42*10000+r+10000000` (test) — đảm bảo train/test độc lập.
- **CF parallelism**: grf dùng OpenMP nội bộ → CF chạy sequential; kNN chạy `parLapply` (Windows) hoặc `mclapply` (Unix).
- **kNN variance**: Paper formula `V̂(S) = (V1+V0)/(k*(k-1))` → R implementation: `(var(s1)+var(s0))/k` (vì `var()` chia cho k−1).
- **Two CF procedures**:
  - Procedure 1 (Double-Sample Trees): `grow_causal_forest()` — cho Design 2, 3.
  - Procedure 2 (Propensity Forest): `grow_propensity_forest()` — cho Design 1 (confounding).
- **Propensity Forest emulation**: grf ≥ 2.0 đã loại bỏ `propensity_forest()`. Thay bằng `regression_forest(X, W)` → lấy W.hat → truyền vào `causal_forest(W.hat = ...)`.

## Configuration

- **Design 1**: n=500, R=500, B=1000, sample_fraction=0.10, d ∈ {2,5,10,15,20,30}
- **Design 2**: n=5000, R=25, B=2000, sample_fraction=0.50, d ∈ {2,3,4,5,6,8}
- **Design 3**: n=10000, R=40, B=10000, sample_fraction=0.20, d ∈ {2,3,4,5,6,8}
- **Real-data**: num_trees=500 (default), sample_fraction=0.5, seed=42, 80/20 train-test split.
