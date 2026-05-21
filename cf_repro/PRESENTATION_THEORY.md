# Phần 1 — Lý thuyết & Kết quả thực nghiệm
## Causal Forest — Wager & Athey (2018, JASA)

> Tài liệu này dùng cho **người thuyết trình** (bạn) để hiểu rõ nền tảng học thuật, ý nghĩa từng kết quả, và sẵn sàng trả lời câu hỏi của giáo viên/khán giả. Không phải slide — đọc trước buổi thuyết trình.

---

## 0. Bài báo gốc và lý do chọn

**Bài báo:** Stefan Wager & Susan Athey (2018) — *"Estimation and Inference of Heterogeneous Treatment Effects using Random Forests"*, **Journal of the American Statistical Association (JASA)**, Vol. 113, No. 523.

**Câu hỏi cốt lõi của bài báo:**
> *"Cho mỗi cá nhân X, hiệu ứng can thiệp τ(X) là bao nhiêu — và ta có thể tin câu trả lời đó tới mức nào?"*

Đây là **bài toán suy luận nhân quả heterogeneous** (Heterogeneous Treatment Effect — HTE) — khác hẳn ML truyền thống (chỉ dự đoán Y), vì ta cần ước lượng một đại lượng **không quan sát được trực tiếp** (không ai vừa "uống thuốc" vừa "không uống thuốc" cùng lúc).

**Tại sao chọn bài này:**
- Là **một trong những phương pháp HTE phổ biến nhất hiện nay** (gói `grf` của Athey/Tibshirani có >2000 stars GitHub, được dùng trong y tế, marketing, fintech).
- Có **chứng minh lý thuyết** (consistency + asymptotic normality), không chỉ heuristic.
- Có sẵn package R chính chủ (`grf`), dễ tái lập.

---

## 1. Vấn đề: tại sao không dùng Random Forest thường?

### 1.1 Khái niệm cốt lõi — Potential Outcomes (Rubin Causal Model)

Mỗi cá nhân `i` có 2 "phiên bản" tiềm năng của outcome:
- `Y_i(1)` — nếu được điều trị (W=1)
- `Y_i(0)` — nếu không được điều trị (W=0)

Hiệu ứng **cá nhân** (Individual Treatment Effect — ITE):
```
τ_i = Y_i(1) − Y_i(0)
```

Vấn đề căn bản: **ta chỉ quan sát được 1 trong 2** (Fundamental Problem of Causal Inference). Người uống thuốc → ta chỉ thấy `Y(1)`, không bao giờ thấy `Y(0)` của chính người đó.

→ Random Forest thường ước lượng `E[Y | X]` (kỳ vọng có điều kiện). **Không phải** `E[Y(1) − Y(0) | X]`.

### 1.2 CATE — đại lượng có thể ước lượng được

Vì không thể tính ITE từng người, ta nhắm vào **Conditional Average Treatment Effect**:
```
τ(x) = E[Y(1) − Y(0) | X = x]
```

Diễn giải: *"Trung bình hiệu ứng can thiệp với những người có đặc điểm X = x là bao nhiêu?"*

**Giả định cần thiết (Unconfoundedness):**
```
(Y(0), Y(1)) ⊥ W | X
```
Nghĩa là: sau khi đã control cho X, việc gán điều trị độc lập với outcome tiềm năng. Trong RCT thì giả định này tự thoả; trong observational data thì cần X đủ giàu để "bão hoà" mọi confounder.

### 1.3 Tại sao kNN baseline cũng được, nhưng tệ hơn?

kNN: tại điểm test x*, tìm k láng giềng gần nhất trong nhóm `W=0` và nhóm `W=1`, lấy chênh lệch trung bình.
- **Ưu:** đơn giản, có công thức variance (Eq. 26 trong bài).
- **Nhược:** "curse of dimensionality" — khi d (số chiều) tăng, "láng giềng" không còn gần. CF dùng cây, chỉ split theo các chiều **liên quan đến τ**, nên không bị curse.

---

## 2. Causal Forest hoạt động thế nào? (Giải thích từng bước)

### 2.1 Cấu trúc tổng quát

Causal Forest = **B cây** (mặc định 2000+), mỗi cây cho ước lượng `τ̂_b(x)`. Final:
```
τ̂(x) = (1/B) × Σ τ̂_b(x)
```

Khác Random Forest thường: cách **chọn split** và cách **dùng dữ liệu trong lá**.

### 2.2 Hai cải tiến quan trọng so với RF truyền thống

#### **(a) Honest Splitting**

Chia dữ liệu trong mỗi cây làm 2 nửa:
- **Splitting sample (50%):** chỉ dùng để chọn split (chiều nào, ngưỡng nào).
- **Estimation sample (50%):** chỉ dùng để tính `τ̂` trong từng lá.

→ Loại bỏ *overfitting bias*: cùng dữ liệu không vừa chọn split vừa tính estimate.

**Hệ quả lý thuyết:** đảm bảo `τ̂(x)` **asymptotically normal** → có thể tính confidence interval hợp lệ.

#### **(b) Subsampling thay vì Bootstrap**

RF dùng bootstrap (sample with replacement). CF dùng subsample (without replacement, size = `s = sample.fraction × n`).
- `s/n → 0` đảm bảo tính độc lập đủ mạnh để CLT chạy được.
- Bài báo dùng `s = n^β` với `β ∈ (0.5, 1)`.

#### **(c) Splitting criterion mới: "Causal MSE"**

Cây thường split để giảm `Var(Y)` trong các lá. CF split để **tăng heterogeneity của τ giữa các lá** — kiểu greedy maximize `(τ̂_L − τ̂_R)²` weighted by size. Procedure 1 trong bài (Section 2.4).

### 2.3 Variance estimate — Infinitesimal Jackknife

`grf` cài đặt **IJ variance** (Wager, Hastie, Efron 2014): estimate sai số chuẩn cho từng `τ̂(x)` từ chính cấu trúc rừng — không cần bootstrap. Đây là điểm mạnh **không có ở Random Forest thường**.

```
τ̂(x) ± 1.96 × ŝê(τ̂(x))      ← khoảng tin cậy 95%
```

→ **Coverage** = tỷ lệ thực tế khoảng này chứa `τ` thật. Lý tưởng = 0.95.

### 2.4 Hai biến thể trong project

| Biến thể | File | Khi nào dùng |
|---|---|---|
| **Procedure 1 — Double-Sample Trees** | `methods.R::grow_causal_forest` | Designs 2 & 3 (không có confounding) |
| **Procedure 2 — Propensity Forest** | `methods.R::grow_propensity_forest` | Design 1 (có confounding) |

**Propensity Forest:** fit thêm 1 forest dự đoán `e(X) = P(W=1 | X)`, rồi inject vào causal forest → giúp khử bias do `e(x)` và `m(x)` tương quan.

---

## 3. Phần thực nghiệm 1 — Simulation (3 Designs)

Bài báo Section 6 thiết kế 3 kịch bản nhân tạo để **biết chính xác τ thật**, từ đó đo MSE và Coverage. Đây là cách duy nhất để **validate** một phương pháp HTE (vì dữ liệu thật không có τ ground truth).

### 3.1 Design 1 — Confounding (kiểm tra kháng bias)

```
n = 500   ·   R = 500 replications   ·   B = 1000 trees   ·   sample.fraction = 0.10
τ(x) = 0  (everywhere — KHÔNG có hiệu ứng thật)
e(x) = 0.25 × (1 + Beta(2,4).pdf(x₁))   ← propensity phụ thuộc x₁
m(x) = 2x₁ − 1                            ← baseline effect mạnh
```

**Câu hỏi kiểm tra:** Khi `e(x)` và `m(x)` đều phụ thuộc x₁ (cùng confounder), liệu CF có **nhầm tương quan đó thành τ ≠ 0**?

**Kỳ vọng đúng:** MSE → 0, Coverage ≈ 0.95.

**Kết quả CF (file `r_cf_d{2..20}.csv`):**
- MSE rất nhỏ, gần 0 ở mọi d.
- Coverage gần 0.95 (đôi khi hơi cao do τ=0 phẳng).
- kNN: MSE cao hơn rõ rệt khi d tăng (curse of dimensionality).

→ **Slide point:** *"CF không bị 'fooled' bởi confounding — đây là test khó nhất."*

### 3.2 Design 2 — Smooth Heterogeneity

```
n = 5000  ·  R = 25 replications   ·   B = 2000 trees   ·   sample.fraction = 0.50
τ(x) = σ20(x₁) × σ20(x₂)    where σ20(x) = 1 + 1/(1+exp(-20(x-1/3)))
e(x) = 0.5                  ← RANDOMIZED — không confounding
m(x) = 0
```

**Câu hỏi:** Khi τ thay đổi mượt theo x₁, x₂ (sigmoid-like), CF có học được hình dạng đúng không?

**Kết quả CF:**
- MSE thấp, gần như không tăng khi d (số chiều noise features) tăng.
- Coverage ≈ 0.95.
- kNN: MSE tăng nhanh theo d.

→ **Slide point:** *"CF tự động phát hiện chỉ x₁, x₂ quan trọng — bỏ qua các chiều noise."*

### 3.3 Design 3 — Sharp Heterogeneity

```
n = 10000  ·  R = 40 replications   ·   B = 10000 trees   ·   sample.fraction = 0.20
τ(x) = σ12(x₁) × σ12(x₂)    where σ12(x) = 2/(1+exp(-12(x-0.5)))   ← steeper than D2
```

**Câu hỏi:** τ có "đỉnh nhọn" (sharp peak) ở góc x₁, x₂ → 1. CF có capture được không?

**Kết quả:**
- MSE thấp hơn kNN rõ rệt.
- Coverage gần 0.95 (đôi khi slightly off ở rìa — boundary bias là known issue).

→ **Slide point:** *"Trường hợp khó nhất — CF vẫn thắng."*

### 3.4 Tổng kết simulation (Tab "Results Table" trong app.R)

| Design | Mục đích | CF MSE | kNN MSE | CF Coverage |
|---|---|---|---|---|
| 1 | Kháng confounding | ≈ 0 | tăng theo d | ≈ 0.95+ |
| 2 | Smooth HTE | thấp, ổn định | tăng theo d | ≈ 0.95 |
| 3 | Sharp HTE | thấp | tệ hơn nhiều | ≈ 0.93-0.95 |

**Take-away cho khán giả:**
1. CF **không bị fooled** bởi confounding.
2. CF **không bị curse of dimensionality** như kNN.
3. CF cho **CI hợp lệ** (coverage ≈ 95%) — không chỉ point estimate.

---

## 4. Phần thực nghiệm 2 — Real Datasets

Sau khi validate trên simulation, bài (và project) chuyển sang **3 dataset marketing thực** để thấy CF hoạt động khi không biết τ thật.

### 4.1 Hillstrom MineThatData

- **Nguồn:** Kevin Hillstrom (2008) — 64K khách hàng đăng ký nhận email quảng cáo.
- **Treatment W:** gửi email (Men's / Women's clothing) vs không gửi.
- **Outcomes:** `visit` (vào web), `conversion` (mua hàng), `spend` (tổng chi tiêu).
- **Features X (7):** recency, history, mens, womens, zip_code_enc, newbie, channel_enc.
- **Tại sao kinh điển:** dataset chuẩn cho uplift modeling — ai cũng dùng để benchmark.

**Kết quả mong đợi:** CF tìm ra **persuadables** (người chỉ mua nếu nhận email) — nhóm có ROI cao nhất.

### 4.2 Lenta RetailHero

- **Nguồn:** X5 Retail Group — competition uplift 2019, dataset Lenta (siêu thị Nga).
- **Treatment:** gửi SMS khuyến mãi vs không.
- **n:** 687K rows, subsample 100K để app load nhanh.
- **Outcome:** `response` (mua sau khi nhận SMS).
- **Features:** ~50 cột (số lượng đơn hàng, gender, age, location...).

### 4.3 Criteo Uplift v2.1

- **Nguồn:** Criteo (ad-tech) — 14M impressions.
- **Treatment:** `exposure` (banner ad có thực sự hiển thị không) — chú ý: cột `treatment` luôn = 1 trong dataset, vì RCT ở mức intent-to-treat; ta phải dùng `exposure` mới là điều kiện ngẫu nhiên thực.
- **n:** 14M, subsample 100K (read first 1M rows).
- **Features X:** 12 anonymized features `f0`..`f11`.
- **Outcomes:** `visit`, `conversion`.

### 4.4 Ý nghĩa 4 segment trong app

CF không chỉ cho ra 1 con số τ̂(x); ta có thể **phân loại khách hàng** theo τ̂ và outcome cơ sở:

| Segment | τ̂(x) | Y baseline | Hành động |
|---|---|---|---|
| **Persuadables** | > +threshold | bất kỳ | **TARGET** — outreach drives uplift |
| **Do Not Disturb** | < −threshold | bất kỳ | **EXCLUDE** — treatment phản tác dụng |
| **Sure Things** | ≈ 0 | đã cao (Y=1 nhiều) | **OPTIONAL** — mua dù sao |
| **Lost Causes** | ≈ 0 | đã thấp | **DEPRIORITIZE** — không response |

**Threshold:** ±0.05 cho binary (=5 percentage points), ±1.0 cho `spend` (=$1).

→ **Slide point:** *"Đây là output thực sự có giá trị kinh doanh — không chỉ 'mô hình chính xác', mà 'gửi email cho ai để lãi cao nhất'."*

### 4.5 Uplift / Qini Curve

- **Trục X:** % dân số được nhắm mục tiêu (sắp xếp giảm dần theo τ̂).
- **Trục Y:** % tổng conversion thu được.
- **Qini coefficient:** diện tích giữa model curve và diagonal random — càng lớn càng tốt. Qini = 0 → mô hình **không** giỏi hơn random.

### 4.6 Variable Importance

- `grf::variable_importance()` đếm tần suất mỗi feature được dùng để split (weighted theo depth).
- **Top features = "targeting drivers"**: chỉ cần biết những feature này là đủ predict ai response.
- Đây là **tính diễn giải** của CF (interpretability) — không phải SHAP nhưng đủ dùng.

---

## 5. Cấu trúc project (để trả lời khi giáo viên hỏi "files đâu")

```
cf_repro/
├── r_repro/
│   ├── dgp.R                  ← sinh dữ liệu cho 3 designs (Section 6)
│   ├── methods.R              ← grow_causal_forest, grow_propensity_forest, predict_knn
│   ├── run_experiment.R       ← chạy 54 cells simulation (3 designs × 3 methods × 6 d)
│   ├── app.R                  ← Shiny dashboard SIMULATION (paper reproduction)
│   ├── prepare_real_data.R    ← download + preprocess 3 dataset thực
│   ├── train_pretrained.R     ← train CF trên 3 dataset, save .rds + _cate.csv
│   ├── app_real.R             ← Shiny dashboard REAL DATA (production-style)
│   └── USER_MANUAL.md         ← hướng dẫn UI app.R
└── results/
    ├── design1/  design2/  design3/   ← 54 file CSV simulation
    └── real/                          ← .rds pretrained + _cate.csv
```

**Hai phần demo độc lập:**
1. **`app.R`** = phần "scientific reproduction" — chứng minh ta tái lập đúng paper.
2. **`app_real.R`** = phần "real-world value" — chứng minh CF có ứng dụng thực.

---

## 6. Bảng tra cứu nhanh khi bị hỏi khó

| Câu hỏi có thể bị hỏi | Trả lời ngắn |
|---|---|
| *"Sao không dùng XGBoost?"* | XGBoost predict E[Y\|X], không phải E[Y(1)−Y(0)\|X]. Có biến thể uplift XGBoost (causal boost) nhưng không có CI hợp lệ. CF có CI từ IJ variance — đó là điểm phân biệt. |
| *"Honest splitting có tốn dữ liệu không?"* | Có — chia đôi dữ liệu trong mỗi cây. Bù lại được CLT hợp lệ. Empirically MSE tăng nhẹ nhưng coverage chuẩn. |
| *"τ ground truth ở real data đâu?"* | Không có. Đó là lý do ta validate trên simulation trước (MSE/Coverage có meaning), rồi mới tin CF trên real data (đo uplift/Qini thay vì MSE). |
| *"Sao Coverage không phải đúng 95%?"* | Asymptotic property — n hữu hạn nên có sai số. Trong sim, n=500 (D1) → coverage có thể 0.93-0.97. Bài báo cũng báo cáo tương tự. |
| *"Causal Forest khác T-learner / S-learner / X-learner (meta-learners) thế nào?"* | T/S/X-learner cũng dùng ML để estimate τ, nhưng CF là **một mô hình đơn** với honest splitting + IJ variance. Meta-learners cần 2-3 mô hình con và **không có CI hợp lệ** (bootstrap không reliable). Project này không dùng meta-learner — chỉ pure CF. |
| *"Sao Hillstrom có 2 group (men/women) tách riêng?"* | Dataset gốc có 3 nhánh: control, men's email, women's email. Để có binary W, ta tách 2 phân tích: (control vs men's) và (control vs women's). |
| *"Tại sao subsample Lenta/Criteo còn 100K?"* | Để app load nhanh + train ~30s. Không subsample → Criteo 14M rows × 12 features có thể train hàng giờ và tốn RAM. |
| *"Qini = 0.05 có tốt không?"* | Tùy domain. >0 đã là model beat random. >0.05 là khá. >0.1 là rất tốt. Marketing thực tế thường 0.02–0.08. |
| *"Variable importance khác feature importance RF chỗ nào?"* | grf weight các split theo `depth^(-2)` — split sớm (gần root) quan trọng hơn. Đo "đóng góp vào việc phân biệt τ", không phải "phân biệt Y". |

---

## 7. Một số con số nên thuộc lòng

- **n simulation:** D1=500, D2=5000, D3=10000.
- **B (trees):** D1=1000, D2=2000, D3=10000.
- **Replications:** D1=500, D2=25, D3=40.
- **Total cells:** 3 designs × 3 methods × 6 d-values = **54 cells**.
- **Real datasets:** Hillstrom ~43K, Lenta 100K subsample (từ 687K), Criteo 100K subsample (từ 14M).
- **Hillstrom features:** 7. Criteo features: 12 (f0–f11).
- **Confidence interval:** ±1.96 × SE (95%).
- **Honest splitting fraction:** 50/50.

---

## 8. Một câu kết thúc thuyết trình mạnh mẽ

> *"Causal Forest không trả lời 'X dự đoán Y như thế nào' — nó trả lời câu hỏi sâu hơn: 'Nếu ta can thiệp lên X, Y sẽ thay đổi bao nhiêu, và ta có thể tin câu trả lời đó tới mức nào?' Đây chính là khoảng cách giữa Machine Learning và Causal Inference — và `grf` là một trong những công cụ đầu tiên đóng được khoảng cách đó với rigorous statistical guarantees."*
