# Structure — Codebase Organization

## Root Layout

```
New_Project/                         ← Git root
├── .gitignore
├── .kiro/                           ← Kiro steering & specs
│   ├── steering/
│   │   ├── product.md
│   │   ├── structure.md
│   │   └── tech.md
│   └── specs/
│       ├── simulation-reproduction/
│       │   ├── requirements.md
│       │   ├── design.md
│       │   └── tasks.md
│       ├── real-data-showcase/
│       │   ├── requirements.md
│       │   ├── design.md
│       │   └── tasks.md
│       └── shiny-dashboards/
│           ├── requirements.md
│           ├── design.md
│           └── tasks.md
└── cf_repro/                        ← Main project directory
    ├── README.md                    ← Project README (Vietnamese)
    ├── PRESENTATION_THEORY.md       ← Lý thuyết cho thuyết trình
    ├── PRESENTATION_DEMO.md         ← Tham khảo demo cho thuyết trình
    ├── USER_MANUAL.md               ← Hướng dẫn sử dụng app.R
    ├── docs/
    │   ├── option_a_setup.md        ← Setup guide cho Option A (causalTree)
    │   └── option_b_setup.md        ← Setup guide cho Option B (grf, hiện tại)
    ├── r_repro/                     ← Toàn bộ R source code
    │   ├── 00_setup.R               ← Cài packages (grf + FNN)
    │   ├── dgp.R                    ← Data-generating processes (3 designs)
    │   ├── methods.R                ← Causal Forest + k-NN estimators + metrics
    │   ├── run_experiment.R         ← CLI: chạy 1 (design, method, d) cell
    │   ├── run_all.R                ← Orchestrator: chạy toàn bộ 54 cells
    │   ├── print_tables.R           ← In bảng so sánh với paper values
    │   ├── plot_results.R           ← Vẽ figure ITE distribution + comparison
    │   ├── app.R                    ← Shiny app: Simulation Dashboard
    │   ├── prepare_real_data.R      ← Download & preprocess 3 real datasets
    │   ├── train_pretrained.R       ← Train CF trên real datasets, save .rds
    │   └── app_real.R               ← Shiny app: Real Data Showcase
    └── results/
        ├── comparison_table.txt     ← Bảng so sánh đầy đủ
        ├── fig_comparison.pdf       ← MSE/Coverage chart
        ├── fig_ite_distribution.pdf ← ITE density plot
        ├── design1/                 ← 18 CSV files (cf + knn10 + knn100 × 6 d-values)
        ├── design2/                 ← 18 CSV files (cf + knn7 + knn50 × 6 d-values)
        ├── design3/                 ← 18 CSV files (cf + knn10 + knn100 × 6 d-values)
        └── real/                    ← Pre-trained .rds + _cate.csv + raw data
```

## Conventions

- **Language**: R (toàn bộ source code). Documentation bằng tiếng Việt.
- **Working directory**: Các script R chạy từ `cf_repro/r_repro/`.
- **Output**: CSV cho simulation, RDS + CSV cho real-data models.
- **Naming**: `r_{method}_d{d}.csv` cho simulation; `{dataset}_{outcome}.rds` cho real-data.
- **No Python**: Project thuần R, không có Python code.
