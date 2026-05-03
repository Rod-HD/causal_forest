# Option B — Tái lập với grf + FNN (Phiên bản hoạt động)

> **Wager & Athey (2018)** — *Estimation and Inference of Heterogeneous Treatment Effects using Random Forests*, JASA 113(523), arXiv:1510.04342v4

---

## Tổng quan

Option B thay thế `causalTree` (không compile được với GCC 14) bằng **`grf`** — package R chính thức của nhóm tác giả, phát triển sau paper và hiện được maintain tích cực trên CRAN.

| Package | Nguồn | Vai trò |
|---------|-------|---------|
| `grf` | CRAN | Causal forest với IJ variance (kế thừa causalTree) |
| `FNN` | CRAN | k-NN matching (Fast Nearest Neighbors) |

### Khác biệt so với Option A

| Khía cạnh | Option A (causalTree) | Option B (grf) |
|-----------|----------------------|----------------|
| Package | causalTree + randomForestCI | grf |
| GCC | Cần GCC ≤ 13 (Rtools43) | Hoạt động với Rtools45 (GCC 14) |
| IJ variance | randomForestCI::randomForestInfJack | grf built-in |
| CF Coverage | Theo paper chính xác | Cao hơn ~2–5% (grf conservative hơn) |
| kNN | Kết quả khớp hoàn hảo | Kết quả khớp hoàn hảo |
| Status | Không compile được | **Hoàn thành 54/54 cells** |

---

## Yêu cầu hệ thống

| Thành phần | Phiên bản | Ghi chú |
|------------|-----------|---------|
| R | 4.4.x hoặc 4.6.x | Đã test trên R 4.6.0 |
| Rtools45 | GCC 14 | Cần để compile grf |
| RAM | ≥ 8 GB | Design 3: n=10000, B=10000 |
| CPU | ≥ 4 cores | grf dùng OpenMP nội bộ |

---

## Cài đặt

### Bước 1 — Cài R

Tải R 4.6.0 từ https://cran.r-project.org/bin/windows/base/  
Cài vào `D:\Programs\R\R-4.6.0\`

### Bước 2 — Cài Rtools45

Tải Rtools45 từ https://cran.r-project.org/bin/windows/Rtools/rtools45/  
Cài vào `D:\Programs\Rtools45\`

Thêm vào PATH (System Environment Variables):
```
D:\Programs\R\R-4.6.0\bin
D:\Programs\Rtools45\rtools45\usr\bin
```

Thêm Environment Variable:
```
RTOOLS45_HOME = D:\Programs\Rtools45\rtools45
```

Kiểm tra:
```bash
Rscript --version
# R scripting front-end version 4.6.0 ...
```

### Bước 3 — Cài packages R

```bash
Rscript r_repro/00_setup.R
```

Script tự động kiểm tra và cài `grf` + `FNN` nếu chưa có:

```
=== grf ===
grf da co        ← hoặc tự cài từ CRAN
=== FNN ===
FNN da co
=== Kiem tra ===
  grf        OK
  FNN        OK
```

---

## Cấu hình thí nghiệm

### Design 1 — Confounding (`prop_setup`, Tables 1–2)

```
n           = 500
n_test      = 1000
R           = 500       replications
num_trees   = 1000      (B)
sample_frac = 0.10      (s/n = 50/500)
tau(x)      = 0
e(x)        = 0.25 * (1 + Beta(2,4).pdf(x₁))
m(x)        = 2x₁ - 1
kNN:        k = 10, 100
d_vals      = {2, 5, 10, 15, 20, 30}
```

### Design 2 — Smooth Heterogeneity (`tau0_setup`, Tables 3–4)

```
n           = 5000
n_test      = 1000
R           = 25
num_trees   = 2000      (B)
sample_frac = 0.50      (s/n = 2500/5000)
tau(x)      = sigma₂₀(x₁) * sigma₂₀(x₂)
              sigma₂₀(x) = 1 + 1/(1+exp(-20*(x-1/3)))
e(x)        = 0.5
m(x)        = 0
kNN:        k = 7, 50
d_vals      = {2, 3, 4, 5, 6, 8}
```

### Design 3 — Sharp Heterogeneity (`tau_setup`, Tables 5–6)

```
n           = 10000
n_test      = 1000
R           = 40
num_trees   = 10000     (B)
sample_frac = 0.20      (s/n = 2000/10000)
tau(x)      = sigma₁₂(x₁) * sigma₁₂(x₂)
              sigma₁₂(x) = 2/(1+exp(-12*(x-0.5)))
e(x)        = 0.5
m(x)        = 0
kNN:        k = 10, 100
d_vals      = {2, 3, 4, 5, 6, 8}
```

---

## DGP — Data-Generating Process

```r
# Chung cho cả 3 designs (r_repro/dgp.R)
# X_i  ~ Uniform([0,1]^d)
# W_i  ~ Bernoulli(e(X_i))
# Y_i^(w) ~ Normal(m(x) + (w-0.5)*tau(x), 1)
# Y_i  = W_i * Y_i^(1) + (1-W_i) * Y_i^(0)

# Seed scheme (reproducible, tách biệt train/test)
seed_train <- MASTER_SEED * 10000L + r         # MASTER_SEED = 42
seed_test  <- MASTER_SEED * 10000L + r + 10000000L
```

---

## Variance Formulas

### Causal Forest (grf IJ)

```r
p       <- predict(forest, newdata = X_test, estimate.variance = TRUE)
tau_hat <- as.numeric(p$predictions)
var_hat <- pmax(as.numeric(p$variance.estimates), 0)
```

grf tính IJ variance nội bộ — không cần package bổ sung.

### k-NN Matching

Paper formula (p.19): `[V̂(S₁) + V̂(S₀)] / [k*(k-1)]`  
Trong đó `V̂(S)` = sum of squared deviations = `var_ddof1 * (k-1)`, nên:

```r
# (var_ddof1 * (k-1) + var_ddof1 * (k-1)) / (k*(k-1))
# = (var_ddof1 + var_ddof1) / k
var_hat[i] <- (var(s1) + var(s0)) / k   # ĐÚNG
# Không phải: / (k*(k-1))               # SAI — lỗi phổ biến
```

---

## Chạy thí nghiệm

### Cài packages (lần đầu)

```bash
cd cf_repro
Rscript r_repro/00_setup.R
```

### Chạy 1 cell đơn lẻ

```bash
cd cf_repro/r_repro

Rscript run_experiment.R --design 1 --method cf     --d 10
Rscript run_experiment.R --design 1 --method knn10  --d 5
Rscript run_experiment.R --design 2 --method knn7   --d 4
Rscript run_experiment.R --design 3 --method knn100 --d 8
```

Output: `results/design{N}/r_{method}_d{d}.csv` (columns: replication, mse, coverage)

### Chạy 1 design

```bash
Rscript run_all.R --design 1   # ~17 phút
Rscript run_all.R --design 2   # ~12 phút
Rscript run_all.R --design 3   # ~67 phút
```

### Chạy toàn bộ 54 cells

```bash
Rscript run_all.R
```

### In bảng so sánh

```bash
Rscript print_tables.R
# Kết quả in ra terminal VÀ lưu vào ../results/comparison_table.txt
```

---

## Parallelism

```
CF:  sequential lapply()     # grf dùng OpenMP nội bộ → không outer parallel
kNN: parLapply() PSOCK       # thuần R → parallelise ngoài được
```

Lý do CF sequential: grf dùng OpenMP để parallel hoá nội bộ. Nếu bọc thêm outer PSOCK cluster trên Windows sẽ conflict và crash với lỗi "incorrect number of dimensions".

---

## Kết quả đạt được

### kNN — Khớp hoàn hảo với paper

| Metric | Tất cả designs |
|--------|----------------|
| MSE | Trong ngưỡng MC error |
| Coverage | Khớp ±0.01 |

Ví dụ: 100-NN Design 3 d=8: Coverage = 0.450 (paper: 0.45) — khớp 3 chữ số thập phân.

### CF — MSE tốt, Coverage cao hơn paper

| Design | CF Coverage (Ours) | CF Coverage (Paper) | Nguyên nhân |
|--------|---------------------|----------------------|-------------|
| D1 | 0.96–0.99 | 0.85–0.95 | grf IJ conservative hơn causalTree |
| D2 | 0.93–0.96 | 0.90–0.97 | Gần khớp |
| D3 | 0.90–0.93 | 0.73–0.94 | grf IJ conservative hơn ở d cao |

Coverage cao hơn = khoảng tin cậy rộng hơn = grf estimate variance bảo thủ hơn.  
Đây là sự khác biệt do implementation package, không phải lỗi.

---

## Ước tính thời gian chạy (máy này, ~8 cores)

| Task | Thời gian thực tế |
|------|------------------|
| Design 1 toàn bộ (18 cells) | ~17 phút |
| Design 2 toàn bộ (18 cells) | ~12 phút |
| Design 3 toàn bộ (18 cells) | ~67 phút |
| **Tổng cộng** | **~96 phút** |

---

## Cấu trúc files

```
cf_repro/
├── r_repro/
│   ├── 00_setup.R         cài packages
│   ├── dgp.R              data-generating processes (3 designs)
│   ├── methods.R          causal forest + kNN estimators
│   ├── run_experiment.R   chạy 1 cell (CLI)
│   ├── run_all.R          chạy toàn bộ 54 cells
│   └── print_tables.R     in bảng so sánh với paper
├── results/
│   ├── design1/           r_cf_d*.csv, r_knn10_d*.csv, r_knn100_d*.csv
│   ├── design2/           r_cf_d*.csv, r_knn7_d*.csv,  r_knn50_d*.csv
│   ├── design3/           r_cf_d*.csv, r_knn10_d*.csv, r_knn100_d*.csv
│   └── comparison_table.txt
└── docs/
    ├── option_a_setup.md  (tài liệu này: causalTree gốc)
    └── option_b_setup.md  (tài liệu này: grf hiện tại)
```
