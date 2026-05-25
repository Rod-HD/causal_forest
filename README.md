# Causal Forest — CS114 Group 3

Tái lập kết quả mô phỏng và demo ứng dụng thực tế từ:

> Wager, S. & Athey, S. (2018). Estimation and Inference of Heterogeneous Treatment Effects
> using Random Forests. *JASA*, 113(523), 1228–1242. [arXiv:1510.04342](https://arxiv.org/abs/1510.04342)

**Implementation:** R với `grf` (causal forests) + `FNN` (k-NN) + `ranger` (meta-learners).  
**Status:** 54/54 simulation cells hoàn thành · Live demo app với 6 uplift learners.

---

## Cấu trúc project

```
cf_repro/
├── README.md
├── GUIDE_app_demo.md        Hướng dẫn chi tiết dùng app_demo.R
├── docs/
│   ├── option_a_setup.md
│   └── option_b_setup.md
├── r_repro/
│   ├── 00_setup.R           Cài toàn bộ packages cần thiết
│   ├── dgp.R                Data-generating processes (3 designs)
│   ├── learners.R           6 uplift learners (CF, CT, S/T/X, Clf)
│   ├── metrics.R            AUUC, Qini, uplift/qini curve data
│   ├── methods.R            CF + kNN estimators cho simulation
│   ├── run_experiment.R     Chạy 1 cell (design × method × d)
│   ├── run_all.R            Chạy toàn bộ 54 cells
│   ├── print_tables.R       In bảng MSE + Coverage so với paper
│   ├── prepare_real_data.R  Tải và xử lý Hillstrom/Lenta/Criteo
│   ├── pretrain_demo.R      Pre-train 6 learners, lưu .rds
│   ├── app.R                Dashboard simulation results (3 designs)
│   └── app_demo.R           Live demo: 6 learners × nhiều dataset
└── results/
    ├── design1/             CSV kết quả simulation Design 1
    ├── design2/             CSV kết quả simulation Design 2
    ├── design3/             CSV kết quả simulation Design 3
    ├── demo_pretrained/     File .rds pre-trained (tạo bằng pretrain_demo.R)
    └── demo_exports/        PNG export từ app_demo
```

---

## Cài đặt

**Yêu cầu:** R 4.4+ và Rtools45 đã cài.

```r
# Từ cf_repro/
Rscript r_repro/00_setup.R
```

Cài tự động: `grf`, `FNN`, `ranger`, `shiny`, `ggplot2`, `plotly`, `dplyr`, `DT`, `scales`.

---

## App 1 — Simulation Dashboard (`app.R`)

Hiển thị kết quả tái lập 3 designs (MSE + Coverage vs dimension d), phân phối ITE, bảng số liệu đầy đủ. **Không cần pretrain** — đọc thẳng từ CSV trong `results/`.

```bash
# Từ cf_repro/r_repro/
Rscript -e "shiny::runApp('app.R', launch.browser=TRUE)"
```

---

## App 2 — Live Demo Uplift (`app_demo.R`)

So sánh 6 uplift learner trên nhiều dataset, quyết định TREAT/DO NOT TREAT từng khách hàng. **Cần file `.rds` pretrained** trong `results/demo_pretrained/`.

### Bước 1 — Pretrain

**Simulation designs** (không cần dữ liệu ngoài, chạy được ngay):

```bash
# Từ cf_repro/r_repro/

# Pretrain toàn bộ Design 1, 2, 3 (tất cả giá trị d) — ~20–40 phút
Rscript pretrain_demo.R --all-sim

# Hoặc pretrain từng cái riêng
Rscript pretrain_demo.R --sim --dataset design1 --d 5
Rscript pretrain_demo.R --sim --dataset design2 --d 3
Rscript pretrain_demo.R --sim --dataset design3 --d 3

# Chỉ định số cây (mặc định 500)
Rscript pretrain_demo.R --all-sim --trees 500
```

**Hillstrom** (cần tải dữ liệu trước):

```bash
# Bước 1: tải và xử lý raw data (~vài phút, cần internet)
Rscript prepare_real_data.R

# Bước 2: pretrain
Rscript pretrain_demo.R --dataset hillstrom --group men   --outcome visit
Rscript pretrain_demo.R --dataset hillstrom --group men   --outcome spend
Rscript pretrain_demo.R --dataset hillstrom --group women --outcome visit

# Hoặc pretrain toàn bộ tất cả dataset thực
Rscript pretrain_demo.R --all
```

File `.rds` được lưu tự động vào `cf_repro/results/demo_pretrained/`.

### Bước 2 — Chạy app

```bash
# Từ cf_repro/r_repro/
Rscript -e "shiny::runApp('app_demo.R', launch.browser=TRUE)"
```

App tự động tải file pretrained khi khởi động. Xem [GUIDE_app_demo.md](GUIDE_app_demo.md) để biết cách dùng từng tab và đọc kết quả.

---

## Tái lập simulation (54 cells)

```bash
# Từ cf_repro/r_repro/

# Chạy 1 cell đơn lẻ
Rscript run_experiment.R --design 1 --method cf    --d 10
Rscript run_experiment.R --design 1 --method knn10 --d 5

# Chạy theo design
Rscript run_all.R --design 1   # ~17 phút
Rscript run_all.R --design 2   # ~12 phút
Rscript run_all.R --design 3   # ~67 phút

# Chạy toàn bộ 54 cells
Rscript run_all.R              # ~96 phút

# In bảng kết quả so với paper
Rscript print_tables.R
```

---

## Thiết kế thí nghiệm

**DGP chung:**
```
X_i  ~ Uniform([0,1]^d)         — d feature, chỉ X₁ và X₂ ảnh hưởng đến tau
W_i  ~ Bernoulli(e(X_i))
Y_i  = m(X_i) + (W_i − 0.5) × tau(X_i) + ε_i,   ε ~ N(0,1)
```

| Design | n | R | B | tau(x) | e(x) | kNN | d |
|---|---|---|---|---|---|---|---|
| 1 — Confounding | 500 | 500 | 1000 | 0 | 0.25×(1+Beta(2,4)(x₁)) | 10, 100 | 2–30 |
| 2 — Smooth Het. | 5000 | 25 | 2000 | σ₂₀(x₁)×σ₂₀(x₂) | 0.5 | 7, 50 | 2–8 |
| 3 — Sharp Het. | 10000 | 40 | 10000 | σ₁₂(x₁)×σ₁₂(x₂) | 0.5 | 10, 100 | 2–8 |

---

## Kết quả tóm tắt

kNN khớp hoàn hảo với paper. Causal Forest cho MSE thấp nhất ở mọi design, coverage cao hơn paper ~2–5% do `grf` dùng IJ variance estimator bảo thủ hơn implementation gốc.

Xem bảng đầy đủ: [`results/comparison_table.txt`](results/comparison_table.txt)
