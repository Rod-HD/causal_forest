# Hướng dẫn chi tiết 2 Shiny App Demo

> Tài liệu này giải thích từng nút bấm, từng chức năng, từng ký hiệu trong 2 app demo của dự án.
> Mọi ký hiệu toán học đều được giải thích song ngữ Việt–Anh.

---

## Mục lục

- [App 1: Simulation Dashboard (`app.R`)](#app-1-simulation-dashboard-appr)
- [App 2: Real Data Showcase (`app_real.R`)](#app-2-real-data-showcase-app_realr)
- [Giải thích ký hiệu chung](#giải-thích-ký-hiệu-chung)

---

## App 1: Simulation Dashboard (`app.R`)

**Mục đích:** Xem lại kết quả mô phỏng từ paper Wager & Athey (2018) — so sánh Causal Forest vs k-NN trên 3 thiết kế mô phỏng. App này **chỉ đọc file CSV có sẵn**, không train lại mô hình.

**Cách chạy:**
```r
Rscript -e "shiny::runApp('app.R', launch.browser=TRUE)"
```

---

### Bố cục tổng thể

```
┌─────────────────────────────────────────────────────────────┐
│  Causal Forest Simulation                                    │
│  (tiêu đề + dòng mô tả)                                     │
├─────────────┬───────────────────────────────────────────────┤
│  SIDEBAR    │  MAIN PANEL                                   │
│  (3/12)     │  (9/12)                                       │
│             │  ┌─────────────────────────────────────────┐  │
│ [Design ▼]  │  │ Tab 1: Comparison Chart                 │  │
│             │  │ Tab 2: ITE Distribution                 │  │
│ [Methods ✓] │  │ Tab 3: Results Table                    │  │
└─────────────┴──┴─────────────────────────────────────────┴──┘
```

---

### SIDEBAR — Thanh điều khiển bên trái

#### Dropdown "Design" (Chọn thiết kế mô phỏng)

| Lựa chọn | Mô tả |
|---|---|
| Design 1 — Confounding | Thiết kế nhiễu — kiểm tra khả năng loại bỏ bias khi xác suất nhận treatment bị tương quan với kết quả |
| Design 2 — Smooth Heterogeneity | Thiết kế dị biến đều — hiệu ứng treatment thay đổi mượt theo đặc trưng |
| Design 3 — Sharp Heterogeneity | Thiết kế dị biến sắc — hiệu ứng treatment thay đổi đột ngột (đỉnh nhọn) |

**Khi chọn một Design**, hộp mô tả bên dưới tự động cập nhật thông số:

```
n = 500 · R = 500 replications · B = 1000 trees · subsample fraction = 0.10
```

Giải thích từng thông số:

| Ký hiệu | Tiếng Anh | Tiếng Việt | Giá trị |
|---|---|---|---|
| `n` | training sample size | kích thước mẫu huấn luyện | 500 / 5000 / 10000 |
| `R` | replications | số lần lặp lại thực nghiệm (Monte Carlo) | 500 / 25 / 40 |
| `B` | number of trees | số cây trong forest | 1000 / 2000 / 10000 |
| `subsample fraction` | subsample fraction | tỉ lệ lấy mẫu con cho mỗi cây | 0.10 / 0.50 / 0.20 |
| `tau(x)` | treatment effect function | hàm hiệu ứng treatment thực | xem bên dưới |
| `e(x)` | propensity score | xác suất nhận treatment tại điểm x | xem bên dưới |
| `m(x)` | main effect / baseline | hiệu ứng nền (không liên quan treatment) | xem bên dưới |

**Design 1 cụ thể:**
- `tau(x) = 0` — hiệu ứng treatment thực bằng 0 ở mọi nơi (không có tác dụng)
- `e(x) = 0.25 × (1 + Beta(2,4).pdf(x₁))` — xác suất nhận treatment phụ thuộc vào biến `x₁`, có phân phối Beta(2,4) — tức là confounded (bị nhiễu)
- `m(x) = 2x₁ − 1` — hiệu ứng nền mạnh, tương quan với `e(x)`, tạo ra bias nếu không xử lý đúng

**Design 2 cụ thể:**
- `tau(x) = sigma20(x₁) × sigma20(x₂)` — tích của 2 hàm sigmoid mượt
- `sigma20(x) = 1 + 1/(1 + exp(-20(x - 1/3)))` — hàm sigmoid dốc 20, điểm uốn tại 1/3
- `e(x) = 0.5` — thực nghiệm ngẫu nhiên, không bị nhiễu
- `m(x) = 0` — không có hiệu ứng nền

**Design 3 cụ thể:**
- `tau(x) = sigma12(x₁) × sigma12(x₂)` — tích của 2 hàm sigmoid sắc hơn
- `sigma12(x) = 2/(1 + exp(-12(x - 0.5)))` — hàm sigmoid dốc 12, điểm uốn tại 0.5
- Tạo ra đỉnh nhọn ở góc `x₁, x₂ ≈ 1`, khó ước lượng hơn Design 2

---

#### Checkbox group "Methods" (Chọn phương pháp hiển thị)

Tích/bỏ tích để ẩn/hiện đường trên đồ thị. Danh sách thay đổi theo Design:

| Design | Checkbox có | Màu |
|---|---|---|
| Design 1, 3 | Causal Forest · 10-NN · 100-NN | Xanh · Cam nhạt · Đỏ |
| Design 2 | Causal Forest · 7-NN · 50-NN | Xanh · Cam nhạt · Cam |

**`k-NN`** = k-Nearest Neighbors = thuật toán k láng giềng gần nhất. Số sau NN là số láng giềng k.
Ví dụ: `10-NN` = dùng 10 láng giềng gần nhất; `100-NN` = dùng 100 láng giềng.

---

### Tab 1: Comparison Chart (Biểu đồ so sánh)

Hai đồ thị Plotly (tương tác được) cạnh nhau:

#### Đồ thị trái: MSE vs Dimension d

- **Trục X (hoành):** `Dimension d` = số chiều của không gian đặc trưng X. Càng cao = bài toán càng khó (curse of dimensionality — tai họa chiều cao).
- **Trục Y (tung):** `MSE` = Mean Squared Error = sai số bình phương trung bình.

**MSE** đo lường độ chính xác ước lượng:

> MSE = trung bình của (tau_hat(X) - tau(X))²

Trong đó:
- `tau_hat(X)` — ký hiệu "tau hat" = giá trị ước lượng của hiệu ứng treatment (estimated treatment effect)
- `tau(X)` — giá trị thực của hiệu ứng treatment (true treatment effect)
- `(tau_hat - tau)²` — sai số bình phương tại từng điểm test

**MSE càng thấp = phương pháp càng chính xác.** Kỳ vọng: Causal Forest (đường xanh) thấp hơn nhiều so với k-NN, đặc biệt khi d lớn.

#### Đồ thị phải: Coverage vs Dimension d

- **Trục Y:** `Coverage (95% CI)` = tỉ lệ bao phủ của khoảng tin cậy 95%

**Coverage** đo lường độ tin cậy của khoảng ước lượng:

> Coverage = % test points mà khoảng tin cậy [tau_hat ± 1.96 × SE] chứa tau thực

Trong đó:
- `CI` = Confidence Interval = khoảng tin cậy
- `95% CI` = khoảng tin cậy 95% — nếu mọi thứ đúng, phải bao phủ giá trị thực 95% thời gian
- `SE` = Standard Error = sai số chuẩn của ước lượng
- `1.96` = điểm phân vị z₀.₉₇₅ của phân phối chuẩn (tương ứng α=0.05 hai đuôi)
- Đường đứt đỏ ngang tại `0.95` = mức target (mục tiêu)

**Coverage = 0.95 là lý tưởng.** Coverage < 0.95 = khoảng tin cậy quá hẹp (undercoverage). Coverage > 0.95 = khoảng tin cậy quá rộng (conservative — bảo thủ).

#### Tính năng tương tác

- **Hover (di chuột vào điểm):** Hiện tooltip `Method: ... | d = ... | MSE: ...`
- **Click vào legend (chú thích):** Ẩn/hiện đường tương ứng
- **Double-click legend:** Chỉ hiện đường đó (isolate)
- **Drag để zoom:** Phóng to vùng quan tâm
- **Double-click canvas:** Zoom về mức ban đầu
- **Camera icon (góc trên phải):** Tải xuống ảnh PNG

---

### Tab 2: ITE Distribution (Phân phối ITE)

#### Radio buttons "Dimension d:" (Chọn chiều d)

Các nút tròn chọn một giá trị d cụ thể để xem phân phối ITE.
- Ví dụ Design 1: `d = 2 · d = 5 · d = 10 · d = 15 · d = 20 · d = 30`
- App sinh 4000 điểm test mới bằng `gen_designX(4000, d, seed=99)` và hiển thị phân phối `tau(X)` thực.

#### Đồ thị mật độ ITE

- **Trục X:** `tau(X) — True CATE` = giá trị hiệu ứng treatment thực tại từng điểm
  - `tau` = ký tự Hy Lạp tau
  - `CATE` = Conditional Average Treatment Effect = hiệu ứng treatment trung bình có điều kiện
  - `True` = giá trị thực (không phải ước lượng)
- **Trục Y:** `Density` = mật độ xác suất
- **Đường đứt đỏ:** đường thẳng đứng tại giá trị trung bình của tau
- **Vùng xanh:** biểu đồ mật độ kernel (KDE — Kernel Density Estimation)

**Đọc đồ thị:**
- Design 1: toàn bộ mass tập trung tại tau=0 (điểm nhọn) vì tau(x)=0 mọi nơi
- Design 2: phân phối trải rộng từ 1 đến 4 (tau luôn dương, biến thiên theo x₁, x₂)
- Design 3: tương tự Design 2 nhưng có đỉnh cao hơn ở vùng tau lớn (vì sigmoid sắc hơn)

#### Thẻ "True CATE Stats" (Thống kê CATE thực)

Bốn ô thống kê:

| Ô | Ý nghĩa |
|---|---|
| **Mean** | Giá trị trung bình của tau(X) trên 4000 điểm test |
| **SD** | Standard Deviation = độ lệch chuẩn — đo mức độ biến thiên của tau |
| **Min** | Giá trị tau nhỏ nhất |
| **Max** | Giá trị tau lớn nhất |

---

### Tab 3: Results Table (Bảng kết quả)

Bảng tổng hợp cho tất cả phương pháp và tất cả giá trị d của Design đang chọn.

| Cột | Ý nghĩa |
|---|---|
| `Method` | Tên phương pháp (Causal Forest / 10-NN / ...) |
| `d` | Số chiều không gian đặc trưng |
| `MSE (mean ± SE)` | Trung bình MSE ± sai số chuẩn Monte Carlo (trên R lần lặp) |
| `Coverage (mean ± SE)` | Tỉ lệ coverage ± sai số chuẩn |

**Đọc `0.0243 ± 0.0012`:** MSE trung bình là 0.0243, sai số chuẩn của ước lượng này là 0.0012 (tương ứng với R lần lặp).

**Note cuối bảng:** "Target coverage = 0.95" — đây là mức coverage lý tưởng cần đạt.

---

## App 2: Real Data Showcase (`app_real.R`)

**Mục đích:** Áp dụng Causal Forest lên 3 dataset marketing thực để phân tích CATE, phân khúc khách hàng (customer segmentation), và Uplift/Qini curve. Hỗ trợ 2 chế độ:
- **Pre-trained mode:** Load model đã train sẵn từ file `.rds` — hiện kết quả ngay lập tức
- **Custom run mode:** Train lại với cài đặt tùy chỉnh (chậm hơn)

**Cách chạy:**
```r
Rscript -e "shiny::runApp('app_real.R', launch.browser=TRUE)"
```

---

### Bố cục tổng thể

```
┌───────────────────────────────────────────────────────────────────┐
│  Causal Forest — Real Data Showcase          [Mode Badge]         │
├─────────────┬─────────────────────────────────────────────────────┤
│  SIDEBAR    │  MAIN PANEL                                         │
│  (3/12)     │  (9/12)                                             │
│             │  ┌───────────────────────────────────────────────┐  │
│ [Dataset ▼] │  │ Tab 1: CATE Overview                          │  │
│ [Group ○]   │  │ Tab 2: Targeting                              │  │
│ [Outcome ▼] │  │ Tab 3: Variable Importance                    │  │
│             │  │ Tab 4: Results Table                          │  │
│ [Custom Run]│  └───────────────────────────────────────────────┘  │
└─────────────┴─────────────────────────────────────────────────────┘
```

---

### Mode Badge (Huy hiệu trạng thái) — góc trên phải

Chỉ thị trạng thái hiện tại của model:

| Badge | Màu | Nghĩa |
|---|---|---|
| 🔒 **Pre-trained · N obs** | Xanh lá | Đã load model từ file `.rds` có sẵn. N = tổng số quan sát (train + test) |
| ⚡ **Custom run · N obs** | Cam | Vừa train lại theo cài đặt tùy chỉnh |
| **No model loaded** | Xám | Chưa có model (file `.rds` không tồn tại) |

Khi ở chế độ Custom, xuất hiện link **"↺ Reset to pre-trained"** để quay lại model gốc.

---

### SIDEBAR — Thanh điều khiển bên trái

#### Dropdown "Dataset" (Chọn dataset)

| Lựa chọn | Dataset | Mô tả ngắn |
|---|---|---|
| Hillstrom MineThatData (n≈43K) | Kevin Hillstrom 2008 | 64,000 khách hàng, chiến dịch email quảng cáo |
| Lenta RetailHero (n≈100K subsample) | X5 RetailHero 2019 | ~687K khách hàng, chiến dịch SMS khuyến mãi |
| Criteo Uplift v2.1 (n≈100K subsample) | Criteo 2021 | 14M hàng (dùng 100K mẫu), W = phơi nhiễm quảng cáo |
| Upload your own CSV | — | Tải lên file CSV của bạn |

**`n≈43K`** = khoảng 43,000 quan sát. **`K`** = nghìn (kilo). **`subsample`** = lấy mẫu con.

#### Radio buttons "Treatment group:" (chỉ Hillstrom)

Chỉ hiện khi chọn Hillstrom. Hillstrom có 2 nhóm treatment riêng biệt:

| Nút | Nghĩa |
|---|---|
| Men's Email vs Control | So sánh email quảng cáo đồ nam vs nhóm không nhận email |
| Women's Email vs Control | So sánh email quảng cáo đồ nữ vs nhóm không nhận email |

**W = 1** = nhận email (treated). **W = 0** = không nhận email (control).

#### Dropdown "Outcome:" (Chọn biến kết quả)

Thay đổi theo dataset:

| Dataset | Outcome | Ý nghĩa |
|---|---|---|
| Hillstrom | Visit (binary) | Có vào website sau khi nhận email không? (0/1) |
| Hillstrom | Conversion (binary) | Có mua hàng không? (0/1) |
| Hillstrom | Spend (continuous) | Tổng số tiền đã chi (liên tục, đơn vị USD) |
| Lenta | Response (binary) | Có phản hồi (mua hàng) sau SMS không? (0/1) |
| Criteo | Visit (binary) | Có vào site sau khi thấy quảng cáo không? (0/1) |
| Criteo | Conversion (binary) | Có chuyển đổi (mua/đăng ký) không? (0/1) |

**`binary`** = nhị phân (chỉ có 0 hoặc 1). **`continuous`** = liên tục (mọi giá trị thực).

Khi đổi Dataset hoặc Outcome, model pre-trained tương ứng **tự động load** — không cần bấm nút.

---

#### Card "Custom Run (optional)" — Chạy tùy chỉnh

> Pre-trained results auto-load when you change dataset/outcome — no button needed.
> Use this card only to re-train with custom settings (slower).

Tạm dịch: *"Kết quả pre-trained tự load khi bạn đổi dataset/outcome — không cần bấm nút. Chỉ dùng card này để train lại với cài đặt tùy chỉnh (chậm hơn)."*

##### Slider "Subsample n:" (chỉ Lenta và Criteo)

Không có với Hillstrom (toàn bộ ~43K đã đủ nhỏ để train nhanh).

- Phạm vi: 1,000 đến 100,000
- Mặc định: 10,000
- Nghĩa: Trước khi train, lấy ngẫu nhiên n hàng từ dataset đầy đủ. Giá trị nhỏ hơn = train nhanh hơn nhưng kết quả kém chính xác hơn.

##### Slider "Number of trees:" (Số cây)

- Phạm vi: 200 đến 2,000
- Mặc định: 500
- Bước: 100
- Nghĩa: Số cây quyết định (decision trees) trong Causal Forest. Nhiều cây hơn = ổn định hơn nhưng chậm hơn.

##### Ước tính thời gian chạy (ETA)

Dòng nhỏ màu xám hiện tự động:
```
Est. ~35s  (n_train ≈ 8,000)
```
- `n_train` = số quan sát dùng để train (= 80% × subsample_n)
- Công thức ước tính: `(n_train / 10000) × (num_trees / 500) × 35 giây`

##### Checkbox "Retrain with top-K features only"

Chỉ hiện sau khi đã có kết quả (≥5 features). Cho phép train lại chỉ với K đặc trưng quan trọng nhất (theo Variable Importance từ lần train trước). Hữu ích để giảm noise và tăng tốc độ.

Khi tick, xuất hiện thêm:

**Slider "K:"** — chọn số lượng features top-K (từ 2 đến tổng số features).

##### Nút "Run Causal Forest" (hoặc "Re-train with custom settings")

Nhãn thay đổi tùy trạng thái:
- Lần đầu: `▶ Run Causal Forest`
- Sau khi đã có pre-trained: `↺ Re-train with custom settings`
- Với upload CSV: `▶ Run Causal Forest on uploaded CSV`

**Khi bấm nút, app thực hiện 3 bước:**

| Bước | Thông báo hiện ra | Thời gian |
|---|---|---|
| Step 1/3 | "Loading and preparing data..." | ~1 giây |
| Step 2/3 | "Growing causal forest — n_train=X · trees=Y · est. ~Zs" | Lâu nhất (35s–vài phút) |
| Step 3/3 | "Computing predictions..." | ~2 giây |

Sau khi xong: `"Done! n_test = X · mean CATE = 0.0123"`

> **Lưu ý:** Trong bước 2, UI bị "đóng băng" (paused) vì R đang chạy. Đây là hành vi bình thường.

---

#### Phần Upload CSV (chỉ khi chọn "Upload your own CSV")

**Nút "Upload CSV (≤200 MB)":** Tải lên file CSV từ máy tính (tối đa 200 MB).

Sau khi upload, app tự động phát hiện và hiển thị 3 dropdown/checkbox:

| Thành phần | Nghĩa |
|---|---|
| **Treatment column (W):** | Cột chứa biến treatment (0 = control, 1 = treated). App tự đoán cột nào là binary 0/1. |
| **Outcome column (Y):** | Cột chứa biến kết quả cần đo. App ưu tiên các cột có tên như "convert", "visit", "spend", "response". |
| **Feature columns (X):** | Checkbox chọn các cột dùng làm đặc trưng (covariates). |

**Link "Show feature Quick Stats (click)":** Bảng thống kê nhanh về từng cột:

| Cột | Nghĩa |
|---|---|
| Column | Tên cột |
| Type | Kiểu: binary / numeric / ordinal/cat / categorical / id-like |
| Unique | Số giá trị duy nhất |
| % NA | Phần trăm giá trị bị thiếu (missing values) |

---

### Tab 1: CATE Overview (Tổng quan CATE)

**CATE** = Conditional Average Treatment Effect = Hiệu ứng treatment trung bình có điều kiện.

Đây là `tau_hat(x)` — ước lượng của Causal Forest cho từng cá nhân x.

#### 5 ô thống kê

| Ô | Ký hiệu | Ý nghĩa |
|---|---|---|
| **Mean CATE** | τ̄ (tau bar) | Trung bình ước lượng CATE trên toàn bộ tập test |
| **SD** | σ (sigma) | Độ lệch chuẩn của CATE — đo mức độ dị biến (heterogeneity) |
| **% Positive** | — | % cá nhân có CATE > 0 (treatment có lợi) |
| **% Negative** | — | % cá nhân có CATE < 0 (treatment có hại) |
| **Test obs** | n_test | Số quan sát trong tập test (= 20% tổng n) |

**Đọc kết quả:** Nếu Mean CATE = 0.032, có nghĩa trung bình treatment tăng outcome lên 3.2 percentage points (cho binary outcome) hoặc $3.20 (cho spend outcome).

#### Đồ thị mật độ CATE

- **Trục X:** `Estimated CATE (tau-hat)` = giá trị tau_hat ước lượng được
  - `tau-hat` (τ̂) = ký hiệu "tau mũ" = ước lượng, phân biệt với `tau` = giá trị thực
- **Trục Y:** `Density` = mật độ xác suất
- **Đường đứt xám** (tại x=0): phân ranh giới dương/âm
- **Đường đứt đỏ** (tại x=mean): giá trị CATE trung bình
- **Đường chấm cam** (2 đường): ranh giới phân khúc (±0.05 cho binary, ±1.0 cho spend)

**Caption:** "Red dashed = mean · Orange dotted = segment boundaries"
Tạm dịch: *"Đứt đỏ = trung bình · Chấm cam = ranh giới phân khúc"*

---

### Tab 2: Targeting (Phân khúc & Nhắm mục tiêu)

Tab này trả lời câu hỏi thực tế: **Ai nên nhận treatment? Ai không nên?**

#### 4 ô phân khúc khách hàng

Dựa trên ngưỡng: **±0.05** cho binary outcome, **±1.0** cho spend.

| Phân khúc | Màu | Điều kiện | Ý nghĩa | Hành động |
|---|---|---|---|---|
| **Persuadables** (Có thể thuyết phục) | Xanh lá | `tau_hat > +0.05` | Treatment có tác dụng tích cực rõ ràng | **TARGET** — nhắm vào nhóm này |
| **Do Not Disturb** (Không nên tiếp cận) | Đỏ | `tau_hat < -0.05` | Treatment có tác dụng tiêu cực (làm giảm outcome) | **EXCLUDE** — loại bỏ |
| **Sure Things** (Sẽ mua dù sao) | Xanh dương nhạt | `-0.05 ≤ tau ≤ 0.05` và đang có outcome cao | Outcome cao sẵn không cần treatment | **OPTIONAL** — lãng phí chi phí |
| **Lost Causes** (Không có khả năng) | Vàng | `-0.05 ≤ tau ≤ 0.05` và đang có outcome thấp | Không phản hồi dù có treatment | **DEPRIORITIZE** — bỏ qua |

Mỗi ô hiển thị: **tên phân khúc · số lượng · (% tổng)**.

#### Đồ thị Uplift Curve (đồ thị nâng cao)

- **Trục X:** `% Population Targeted` = % tổng khách hàng được nhắm mục tiêu (0% → 100%)
- **Trục Y:** `% Conversions Captured` = % tổng conversions thu được (0% → 100%)
- **Đường xanh "Model":** Sắp xếp khách hàng theo `tau_hat` từ cao xuống thấp. Nhắm top X% → thu được Y% conversions.
- **Đường đứt xám "Random":** Đường chéo = baseline ngẫu nhiên (nhắm ngẫu nhiên không theo model)
- **Tiêu đề:** `Uplift Curve | Qini = 0.xxx`

**Đọc Qini score:**
- `Qini` = diện tích giữa đường Model và đường Random
- Qini càng cao = model càng tốt trong việc xếp hạng khách hàng theo mức độ responsive
- Qini = 0 = model không tốt hơn random
- Qini = 1 = model hoàn hảo (lý thuyết)

#### Biểu đồ cột "Customer Segments"

Biểu đồ ngang hiển thị số lượng khách hàng trong mỗi phân khúc. Hover để xem số chính xác.

#### Bảng "Targeting Recommendations"

| Cột | Ý nghĩa |
|---|---|
| Segment | Tên phân khúc |
| Action | Khuyến nghị hành động cụ thể |
| Avg CATE | CATE trung bình của phân khúc đó |
| Size | Số lượng khách hàng trong phân khúc |

---

### Tab 3: Variable Importance (Tầm quan trọng biến)

**Variable Importance** (Tầm quan trọng biến) = mức độ ảnh hưởng của từng đặc trưng đến việc xác định **ai** được hưởng lợi nhiều/ít từ treatment.

> **Lưu ý quan trọng:** Variable Importance trong Causal Forest **khác** với regression thông thường. Nó đo đặc trưng nào giải thích sự **dị biến** (heterogeneity) của treatment effect, không phải đặc trưng nào predict outcome.

#### Hộp mô tả (desc-box)

Ví dụ:
```
Top 3 features (recency, history, channel_enc) explain 72% of treatment-effect heterogeneity.
It takes 4 feature(s) to reach 80% cumulative importance (out of 7 total).
```

Tạm dịch: *"3 đặc trưng hàng đầu (recency, history, channel_enc) giải thích 72% tính dị biến của treatment effect. Cần 4 đặc trưng để đạt 80% tầm quan trọng tích lũy (trong tổng 7 đặc trưng)."*

**Các khái niệm:**
- `cumulative importance` (tầm quan trọng tích lũy) = tổng % tầm quan trọng khi xếp từ cao xuống thấp
- `targeting drivers` = đặc trưng quyết định ai sẽ responsive với treatment

#### Biểu đồ ngang Variable Importance

- **Trục X:** `Variable Importance` = giá trị tầm quan trọng (không có đơn vị, tỉ lệ tương đối)
- **Trục Y:** tên đặc trưng, sắp xếp từ quan trọng nhất (trên) đến ít nhất (dưới)
- Hover để xem giá trị chính xác

**Subtitle:** "Higher = more influential in determining treatment effect heterogeneity"
Tạm dịch: *"Giá trị cao hơn = ảnh hưởng nhiều hơn đến sự dị biến của treatment effect"*

---

### Tab 4: Results Table (Bảng kết quả chi tiết)

Bảng hiển thị từng cá nhân trong tập test, sắp xếp theo `|tau_hat|` từ lớn đến nhỏ.

#### Slider "Show top N rows (by |tau|):"

- Hiển thị N hàng có giá trị `|tau_hat|` lớn nhất (= ảnh hưởng treatment mạnh nhất, theo hướng nào cũng được)
- Phạm vi: 10 đến 500 (hoặc n_test nếu nhỏ hơn)
- `|tau|` = ký hiệu "giá trị tuyệt đối của tau" = bỏ dấu âm/dương, chỉ xét độ lớn

#### Các cột trong bảng

| Cột | Ký hiệu | Ý nghĩa |
|---|---|---|
| Cột đặc trưng | X_cols | Giá trị đặc trưng của từng khách hàng (recency, history, ...) |
| `W` | W (treatment indicator) | 0 = nhóm control, 1 = nhóm treatment thực tế |
| `Y_actual` | Y (observed outcome) | Kết quả thực tế quan sát được (0/1 hoặc số tiền) |
| `tau_hat` | τ̂ (tau hat) | Ước lượng CATE của khách hàng này: treatment tăng/giảm outcome bao nhiêu |
| `CI_lower` | τ̂ − 1.96×SE | Cận dưới khoảng tin cậy 95%: tau_hat - 1.96 × standard error |
| `CI_upper` | τ̂ + 1.96×SE | Cận trên khoảng tin cậy 95%: tau_hat + 1.96 × standard error |

**Đọc một hàng ví dụ:**
```
recency=6 | history=150 | W=1 | Y_actual=1 | tau_hat=0.18 | CI=[0.09, 0.27]
```
Nghĩa: Khách hàng này (nhận email, có mua hàng) được ước lượng là treatment tăng xác suất mua hàng lên 18 percentage points, khoảng tin cậy 95% từ 9% đến 27%.

---

## Giải thích ký hiệu chung

| Ký hiệu | Tên đầy đủ (EN) | Nghĩa (VI) |
|---|---|---|
| `tau(x)` / `τ(x)` | treatment effect function | hàm hiệu ứng treatment tại điểm x — giá trị thực |
| `tau_hat(x)` / `τ̂(x)` | estimated treatment effect | ước lượng hiệu ứng treatment tại x (mũ "^" = ước lượng) |
| `CATE` | Conditional Average Treatment Effect | hiệu ứng treatment trung bình có điều kiện theo x |
| `ITE` | Individual Treatment Effect | hiệu ứng treatment của từng cá nhân |
| `X` | feature vector / covariates | vector đặc trưng (các biến mô tả cá nhân) |
| `W` | treatment indicator | biến chỉ thị treatment (0=control, 1=treated) |
| `Y` | outcome | biến kết quả (visit, conversion, spend,...) |
| `e(x)` | propensity score | xác suất nhận treatment tại x: P[W=1 \| X=x] |
| `m(x)` | main effect / baseline | hiệu ứng nền trung bình: E[(Y(0)+Y(1))/2 \| X=x] |
| `n` | sample size | kích thước mẫu |
| `d` | dimension | số chiều của không gian đặc trưng X |
| `R` | replications | số lần lặp lại thực nghiệm Monte Carlo |
| `B` | number of trees | số cây trong random forest |
| `s` | subsample size | kích thước mẫu con cho mỗi cây (= n × sample_fraction) |
| `k` | number of neighbors | số láng giềng trong k-NN |
| `SE` | standard error | sai số chuẩn của ước lượng |
| `CI` | confidence interval | khoảng tin cậy |
| `MSE` | mean squared error | sai số bình phương trung bình |
| `IJ` | infinitesimal jackknife | phương pháp ước lượng phương sai trong grf |
| `VI` | variable importance | tầm quan trọng biến |
| `RDS` / `.rds` | R Data Serialization | định dạng file lưu trữ object R |
| `Qini` | Qini coefficient | hệ số đo chất lượng uplift model |

---

*Tài liệu này được tạo tự động từ phân tích source code `app.R` và `app_real.R`.*
