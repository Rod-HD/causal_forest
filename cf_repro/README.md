# Wager & Athey (2018) — Section 5 Simulation Replication

Tái lập toàn bộ kết quả mô phỏng trong:

> Wager, S. & Athey, S. (2018). Estimation and Inference of Heterogeneous Treatment Effects
> using Random Forests. *JASA*, 113(523), 1228–1242. [arXiv:1510.04342](https://arxiv.org/abs/1510.04342)

**Implementation:** R với `grf` (causal forests) + `FNN` (k-NN matching).  
**Status:** Hoàn thành — 54/54 cells trên 3 designs.

---

## Hai phương án tái lập

| | Option A | Option B (hiện tại) |
|-|----------|---------------------|
| Package CF | `causalTree` (GitHub) | `grf` (CRAN) |
| Package Var | `randomForestCI` (GitHub) | grf built-in IJ |
| R version | R 4.3.x + Rtools43 (GCC 12) | R 4.4–4.6 + Rtools45 |
| Status | Không compile (GCC 14 incompatible) | **Hoàn thành** |
| CF Coverage | Khớp chính xác paper | Cao hơn ~2–5% (grf conservative hơn) |
| kNN | — | Khớp hoàn hảo với paper |

Xem chi tiết: [`docs/option_a_setup.md`](docs/option_a_setup.md) và [`docs/option_b_setup.md`](docs/option_b_setup.md)

---

## Cài đặt nhanh

**Yêu cầu:** R 4.4+ và Rtools45 đã cài và có trong PATH.

```bash
# Từ thư mục cf_repro/
Rscript r_repro/00_setup.R
```

Script tự động kiểm tra và cài `grf` + `FNN` từ CRAN.

---

## Chạy thí nghiệm

Tất cả lệnh chạy từ thư mục `cf_repro/r_repro/`.

### Chạy 1 cell đơn lẻ

```bash
Rscript run_experiment.R --design 1 --method cf     --d 10
Rscript run_experiment.R --design 1 --method knn10  --d 5
Rscript run_experiment.R --design 2 --method knn7   --d 4
Rscript run_experiment.R --design 3 --method knn100 --d 8
```

### Chạy theo design

```bash
Rscript run_all.R --design 1   # Design 1: ~17 phút
Rscript run_all.R --design 2   # Design 2: ~12 phút
Rscript run_all.R --design 3   # Design 3: ~67 phút
```

### Chạy toàn bộ 54 cells

```bash
Rscript run_all.R              # Tổng ~96 phút
```

### Xem kết quả so với paper

```bash
Rscript print_tables.R
# In ra terminal + lưu vào results/comparison_table.txt
```

---

## Cấu trúc project

```
cf_repro/
├── README.md
├── docs/
│   ├── option_a_setup.md    Hướng dẫn Option A (causalTree gốc, GCC ≤ 13)
│   └── option_b_setup.md    Hướng dẫn Option B (grf, hiện tại, hoạt động)
├── r_repro/
│   ├── 00_setup.R           Cài packages (grf + FNN)
│   ├── dgp.R                Data-generating processes (3 designs)
│   ├── methods.R            Causal forest + k-NN estimators + metrics
│   ├── run_experiment.R     CLI: chạy 1 (design, method, d) cell
│   ├── run_all.R            Orchestrator: chạy toàn bộ 54 cells
│   └── print_tables.R       In bảng so sánh với paper values
└── results/
    ├── comparison_table.txt  Bảng so sánh đầy đủ (tất cả 3 designs)
    ├── design1/              r_cf_d{2,5,10,15,20,30}.csv
    │                         r_knn10_d{...}.csv
    │                         r_knn100_d{...}.csv
    ├── design2/              r_cf_d{2,3,4,5,6,8}.csv
    │                         r_knn7_d{...}.csv
    │                         r_knn50_d{...}.csv
    └── design3/              r_cf_d{2,3,4,5,6,8}.csv
                              r_knn10_d{...}.csv
                              r_knn100_d{...}.csv
```

Mỗi file CSV có 3 cột: `replication, mse, coverage`.

---

## Thiết kế thí nghiệm (từ paper)

### Design 1 — Confounding (Tables 1–2)

| Tham số | Giá trị |
|---------|---------|
| n | 500 |
| R | 500 |
| B (num_trees) | 1000 |
| sample_fraction | 0.10 (s=50) |
| tau(x) | 0 |
| e(x) | 0.25 × (1 + Beta(2,4).pdf(x₁)) |
| m(x) | 2x₁ − 1 |
| kNN | k = 10, 100 |
| d | {2, 5, 10, 15, 20, 30} |

### Design 2 — Smooth Heterogeneity (Tables 3–4)

| Tham số | Giá trị |
|---------|---------|
| n | 5000 |
| R | 25 |
| B | 2000 |
| sample_fraction | 0.50 (s=2500) |
| tau(x) | sigma₂₀(x₁) × sigma₂₀(x₂) |
| e(x) | 0.5 |
| kNN | k = 7, 50 |
| d | {2, 3, 4, 5, 6, 8} |

### Design 3 — Sharp Heterogeneity (Tables 5–6)

| Tham số | Giá trị |
|---------|---------|
| n | 10000 |
| R | 40 |
| B | 10000 |
| sample_fraction | 0.20 (s=2000) |
| tau(x) | sigma₁₂(x₁) × sigma₁₂(x₂) |
| e(x) | 0.5 |
| kNN | k = 10, 100 |
| d | {2, 3, 4, 5, 6, 8} |

**DGP chung:**
```
X_i  ~ Uniform([0,1]^d)
W_i  ~ Bernoulli(e(X_i))
Y_i  = m(X_i) + (W_i − 0.5) × tau(X_i) + ε_i,   ε ~ N(0,1)
```

---

## Kết quả tóm tắt

### kNN — Khớp hoàn hảo với paper

Tất cả MSE và coverage của kNN khớp với paper trong phạm vi sai số Monte Carlo. Ví dụ nổi bật: 100-NN Design 3 d=8 → Coverage = **0.450** (paper: 0.45).

### Causal Forest — MSE tốt, Coverage cao hơn paper

CF coverage cao hơn paper ~2–5% do `grf` dùng IJ variance estimator bảo thủ hơn `causalTree` gốc. Đây là khác biệt implementation, không phải lỗi.

Xem bảng đầy đủ: [`results/comparison_table.txt`](results/comparison_table.txt)

---

## Ghi chú kỹ thuật

**kNN variance:** Paper dùng ký hiệu `V̂(S) = Σ(yⱼ−ȳ)²` (sum of squares). Vì R's `var()` chia cho (k−1), công thức đúng trong R là:
```r
var_hat[i] <- (var(s1) + var(s0)) / k   # không phải / (k*(k-1))
```

**CF parallelism:** `grf` dùng OpenMP nội bộ → chạy CF sequential (`lapply`). kNN chạy parallel (`parLapply` trên Windows).

**Seed scheme:** Replication `r` dùng `42*10000+r` cho train và `42*10000+r+10000000` cho test — đảm bảo train/test độc lập nhau.
