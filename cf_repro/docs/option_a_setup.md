# Option A — Tái lập chính xác 100% theo paper gốc

> **Wager & Athey (2018)** — *Estimation and Inference of Heterogeneous Treatment Effects using Random Forests*, JASA 113(523), arXiv:1510.04342v4

---

## Tổng quan

Option A sử dụng **đúng các package mà paper gốc dùng** khi viết năm 2015-2017:

| Package | Nguồn | Vai trò |
|---------|-------|---------|
| `causalTree` | GitHub: swager/causalTree | Causal forest (propensity trees & double-sample trees) |
| `randomForestCI` | GitHub: swager/randomForestCI | Infinitesimal jackknife (IJ) variance |
| `FNN` | CRAN | k-NN matching |

### Tại sao có thể không chạy được

`causalTree` viết năm 2017 dùng C code không tương thích với **GCC 14** (có trong Rtools45 dành cho R 4.4+). Lỗi cụ thể:

```
error: too many arguments to function 'ct_xeval'
```

Để chạy Option A, cần **Rtools43** (GCC 12/13) hoặc patch C source của causalTree.

---

## Yêu cầu hệ thống

| Thành phần | Phiên bản | Ghi chú |
|------------|-----------|---------|
| R | 4.3.x hoặc 4.4.x | R 4.6.x + Rtools45 **không hoạt động** |
| Rtools43 | GCC 12 | Tải tại https://cran.r-project.org/bin/windows/Rtools/rtools43/ |
| RAM | ≥ 8 GB | Design 3: n=10000, B=10000 |
| CPU | ≥ 4 cores | Design 3 mất 6–10 giờ |

---

## Cài đặt

### Bước 1 — Cài R 4.3.x

Tải R 4.3.3 từ https://cran.r-project.org/bin/windows/base/old/4.3.3/  
Cài vào `D:\Programs\R\R-4.3.3\`

### Bước 2 — Cài Rtools43

Tải Rtools43 từ https://cran.r-project.org/bin/windows/Rtools/rtools43/  
Cài vào `D:\Programs\Rtools43\`

Thêm vào PATH (System Environment Variables):
```
D:\Programs\R\R-4.3.3\bin
D:\Programs\Rtools43\usr\bin
```

Kiểm tra:
```bash
gcc --version   # phải ra GCC 12.x hoặc 13.x
Rscript --version
```

### Bước 3 — Cài packages

```r
# Chạy từ R console hoặc Rscript
options(repos = c(CRAN = "https://cloud.r-project.org"))
install.packages("FNN")

# causalTree và randomForestCI từ GitHub (cần pak hoặc devtools)
install.packages("pak")
pak::pak("swager/causalTree")
pak::pak("swager/randomForestCI")
```

Kiểm tra:
```r
library(causalTree)
library(randomForestCI)
library(FNN)
cat("OK\n")
```

---

## Cấu hình thí nghiệm (từ paper)

### Design 1 — Confounding (`prop_setup`, Tables 1–2)

```
n      = 500       # training size
n_test = 1000      # test size
R      = 500       # Monte Carlo replications
B      = 1000      # số cây (num.trees)
s      = 50        # subsample size → sample.fraction = 50/500 = 0.10
tau(x) = 0         # true CATE = 0
e(x)   = 0.25 * (1 + Beta(2,4).pdf(x₁))   # confounded propensity
m(x)   = 2x₁ - 1
kNN:   k = 10, 100
d_vals = {2, 5, 10, 15, 20, 30}
```

**Forest type:** Propensity trees (`split.Bucket = TRUE` trong causalTree)

### Design 2 — Smooth Heterogeneity (`tau0_setup`, Tables 3–4)

```
n      = 5000
n_test = 1000
R      = 25
B      = 2000
s      = 2500      # sample.fraction = 2500/5000 = 0.50
tau(x) = sigma₂₀(x₁) * sigma₂₀(x₂)
         sigma₂₀(x) = 1 + 1/(1+exp(-20*(x-1/3)))
e(x)   = 0.5
m(x)   = 0
kNN:   k = 7, 50
d_vals = {2, 3, 4, 5, 6, 8}
```

**Forest type:** Double-sample trees (`honesty = TRUE` trong causalTree)

### Design 3 — Sharp Heterogeneity (`tau_setup`, Tables 5–6)

```
n      = 10000
n_test = 1000
R      = 40
B      = 10000
s      = 2000      # sample.fraction = 2000/10000 = 0.20
tau(x) = sigma₁₂(x₁) * sigma₁₂(x₂)
         sigma₁₂(x) = 2/(1+exp(-12*(x-0.5)))
e(x)   = 0.5
m(x)   = 0
kNN:   k = 10, 100
d_vals = {2, 3, 4, 5, 6, 8}
```

**Forest type:** Double-sample trees

---

## DGP — Data-Generating Process

```r
# Chung cho cả 3 designs
# X_i  ~ Uniform([0,1]^d)
# W_i  ~ Bernoulli(e(X_i))
# Y_i^(w) ~ Normal(m(x) + (w-0.5)*tau(x), 1)
# Y_i  = W_i * Y_i^(1) + (1-W_i) * Y_i^(0)
```

Seed scheme (đồng bộ với Option B):
```r
seed_train <- MASTER_SEED * 10000L + r
seed_test  <- MASTER_SEED * 10000L + r + 10000000L
```

---

## Variance Formula cho k-NN

Paper Equation trên p.19:

```
Var̂(τ̂(x)) = [V̂(S₁) + V̂(S₀)] / [k*(k-1)]
```

Trong đó `V̂(S)` là **tổng bình phương độ lệch** (sum of squared deviations):

```
V̂(S) = Σ(yⱼ - ȳ)²   (NOT sample variance)
```

Vì R's `var()` chia cho (k-1), ta có:

```r
var_hat[i] <- (var(s1) + var(s0)) / k
# Không phải / (k*(k-1))
```

---

## Kết quả kỳ vọng (từ paper Tables 1–6)

### MSE

| Design | Method | d=2 | d=5 | d=8/10 |
|--------|--------|-----|-----|--------|
| D1 | CF | 0.02 | 0.02 | 0.02 |
| D1 | 10-NN | 0.21 | 0.24 | 0.28 |
| D1 | 100-NN | 0.09 | 0.12 | 0.12 |
| D2 | CF | 0.04 | 0.03 | 0.03 |
| D2 | 7-NN | 0.29 | 0.31 | 0.38 |
| D2 | 50-NN | 0.04 | 0.11 | 0.21 |
| D3 | CF | 0.02 | 0.02 | 0.03 |
| D3 | 10-NN | 0.20 | 0.22 | 0.29 |
| D3 | 100-NN | 0.02 | 0.09 | 0.26 |

### Coverage (nominal 95%)

| Design | Method | d=2 | d=5 | d=8/10 |
|--------|--------|-----|-----|--------|
| D1 | CF | 0.95 | 0.94 | 0.91–0.85 |
| D1 | 10-NN | 0.93 | 0.92 | 0.91–0.89 |
| D1 | 100-NN | 0.62 | 0.52 | 0.51–0.48 |
| D2 | CF | 0.97 | 0.93 | 0.90 |
| D2 | 7-NN | 0.93 | 0.92 | 0.90 |
| D2 | 50-NN | 0.94 | 0.77 | 0.57 |
| D3 | CF | 0.94 | 0.81 | 0.73 |
| D3 | 10-NN | 0.93 | 0.93 | 0.90 |
| D3 | 100-NN | 0.94 | 0.67 | 0.45 |

---

## Ước tính thời gian chạy

| Design | Method | Thời gian |
|--------|--------|-----------|
| D1 | CF (R=500, B=1000) | ~10–15 phút |
| D1 | kNN (R=500) | ~2 phút |
| D2 | CF (R=25, B=2000) | ~10–20 phút |
| D2 | kNN (R=25) | ~1 phút |
| D3 | CF (R=40, B=10000) | ~4–8 giờ |
| D3 | kNN (R=40) | ~10 phút |

---

## Lý do chọn Option B thay thế

| Vấn đề | Mô tả |
|--------|-------|
| GCC 14 incompatibility | causalTree không compile được với Rtools45 (GCC 14) |
| Package không được maintain | causalTree lần cuối cập nhật năm 2017 |
| Cần cài Rtools43 riêng | Không tương thích với R 4.6.x mặc định |
| Patch C source phức tạp | Cần sửa `src/causalTree.c` thủ công |

Nếu vẫn muốn thử Option A, phải dùng R 4.3.x + Rtools43.
