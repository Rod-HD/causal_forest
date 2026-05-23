# Hướng dẫn đọc kết quả UI Live Demo

Tài liệu này hướng dẫn cách chạy `app_demo.R` và cách đọc kết quả từng tab. Phù hợp cho người thuyết trình lẫn người xem demo lần đầu.

---

## Phần 1 — Cách chạy app

### Yêu cầu hệ thống
- R 4.4 trở lên (Windows: kèm Rtools45)
- 9 package: `grf`, `FNN`, `shiny`, `ggplot2`, `plotly`, `dplyr`, `scales`, `ranger`, `DT`, `pROC`, `gridExtra`

Cài tất cả bằng 1 lệnh:
```bash
cd cf_repro/r_repro
Rscript 00_setup.R
```

### Chạy app
```bash
cd cf_repro/r_repro
Rscript -e "shiny::runApp('app_demo.R', launch.browser=TRUE)"
```

App sẽ mở browser tự động ở địa chỉ `http://127.0.0.1:<port>`. Mặc định load sẵn pre-trained model **Hillstrom × Men's Email × Visit** trong vòng <100ms — không cần chờ training.

### Khi nào cần train lại
- Đổi sang outcome khác (`conversion`, `spend`)
- Đổi sang dataset khác (Lenta, Criteo)
- Đổi số `Trees per learner` ở sidebar
- Upload CSV mới

Click nút **▶ Re-train with current settings** ở sidebar. Mất khoảng 25–70 giây tùy dataset và số cây.

### Pre-train sẵn nhiều cấu hình (tùy chọn)
Nếu muốn mọi tổ hợp dataset × outcome đều load instant:
```bash
Rscript pretrain_demo.R --all
```
Mất khoảng 5–10 phút, lưu vào `results/demo_pretrained/*.rds`.

---

## Phần 2 — Bố cục giao diện

```
┌─────────────────────────────────────────────────────────────────┐
│  Causal Forest — Live Demo (CS114)         [Mode Badge]         │
├─────────────┬───────────────────────────────────────────────────┤
│  SIDEBAR    │  MAIN PANEL — 5 tabs                              │
│  (3/12)     │  (9/12)                                           │
│             │  ┌─────────────────────────────────────────────┐  │
│ [Dataset]   │  │ 1. Dataset Overview                         │  │
│ [Group]     │  │ 2. Quantitative Comparison                  │  │
│ [Outcome]   │  │ 3. Uplift / Qini Curves                     │  │
│             │  │ 4. Customer Decision     ← Điểm nhấn         │  │
│ [Training]  │  │ 5. Upload CSV                               │  │
│ [Export]    │  └─────────────────────────────────────────────┘  │
└─────────────┴───────────────────────────────────────────────────┘
```

### Mode Badge (góc trên phải)
- 🔒 **Pre-trained · N obs** (xanh lá): đã load model từ file `.rds` sẵn
- ⚡ **Fresh train · N obs** (cam): vừa train mới
- **No model loaded** (xám): chưa có gì

---

## Tab 1 — Dataset Overview

Tab này cho biết bạn đang làm việc với dữ liệu gì, đặc điểm ra sao, có cân bằng không.

### Khu vực bên trái: Dataset Info

5 thông tin cốt lõi:

| Mục | Ý nghĩa | Ví dụ Hillstrom × men × visit |
|---|---|---|
| **Name** | Tên dataset + nhóm treatment | Hillstrom MineThatData (men group) |
| **Size** | Số mẫu × số đặc trưng | 23,487 samples × 7 features |
| **Treatment (W)** | Biến treatment + tỷ lệ % được treat | binary, 50.3% treated |
| **Outcome (Y)** | Biến mục tiêu + baseline rate | Visit (binary) — Baseline rate: 15.14% |
| **Train/Test split** | Cách chia dữ liệu | 18,789 / 4,698 (80/20, seed=42) |

**Cách đọc baseline rate:**
- Nếu **binary outcome** (visit, conversion): baseline rate = % tổng dân số có Y=1, không phân biệt treatment.
- Nếu **continuous outcome** (spend): baseline rate = giá trị trung bình của Y.
- Hillstrom × visit có baseline 15.14% nghĩa là trung bình 15 trên 100 khách hàng vào website sau email.

### Khu vực bên phải: 2 biểu đồ

**Biểu đồ 1 — Treatment vs Control Counts**
- Cột xám = nhóm Control (W=0, không nhận email)
- Cột xanh lá = nhóm Treated (W=1, nhận email)
- 2 cột gần bằng nhau → A/B test cân bằng tốt. Đây là điều kiện cần để causal inference đúng đắn.

**Biểu đồ 2 — Outcome distribution by W**
- Với binary Y: 2 cột so sánh tỷ lệ Y=1 giữa Control và Treated. Chênh lệch chính là **Average Treatment Effect (ATE)** — hiệu ứng treatment trung bình trên toàn dân số.
- Với continuous Y: density plot của Y, phân nhóm theo W.

**Ví dụ Hillstrom × men × visit:**
- Control: ~10.5% vào web
- Treated: ~18.5% vào web
- ATE = +8 percentage points → email tăng tỷ lệ visit lên 8%.

**Tuy nhiên:** ATE chỉ là con số trung bình. Mục tiêu của uplift modeling là tìm **per-customer effect** — không phải ai cũng phản ứng như nhau với email. Đó là lý do cần các tab tiếp theo.

### Khu vực dưới: Baselines
Liệt kê 6 thuật toán sẽ được so sánh:
1. Standard Classifier
2. S-Learner
3. T-Learner
4. X-Learner
5. Causal Tree (50)
6. **Causal Forest** ← phương pháp chính

---

## Tab 2 — Quantitative Comparison

Tab này so sánh điểm số định lượng của 6 thuật toán để biết cái nào tốt nhất.

### Bảng so sánh hiệu năng

5 cột:

| Cột | Ý nghĩa | Càng cao càng tốt? |
|---|---|---|
| **Method** | Tên thuật toán | — |
| **AUUC ↑** | Area Under Uplift Curve — diện tích dưới đường uplift | ✅ Có |
| **Qini ↑** | Qini coefficient — biến thể của AUUC, robust với treatment lệch | ✅ Có |
| **AUC (Y)** | Area Under ROC Curve — chỉ cho Standard Classifier | ✅ Có |
| **Train** | Thời gian huấn luyện | ❌ Thấp tốt hơn |

**Vì sao có cột "—":**
- Standard Classifier không phải uplift model → không có AUUC/Qini.
- 5 uplift learner còn lại không predict P(Y=1) trực tiếp → không có AUC.

**Ví dụ Hillstrom × men × visit (số liệu thực tế):**

| Method | AUUC | Qini | AUC | Train |
|---|---|---|---|---|
| Standard Classifier | — | — | 0.6151 | 0.6s |
| S-Learner | 221.48 | 9.94 | — | 0.8s |
| T-Learner | 218.94 | 10.08 | — | 1.2s |
| X-Learner | 220.06 | 9.55 | — | 9.2s |
| Causal Tree (50) | 218.57 | 8.57 | — | 2.3s |
| **Causal Forest** | 212.38 | 6.49 | — | 10.0s |

**Cách đọc:**
- Top 4 method (S/T/X-Learner, Causal Tree) có AUUC gần như tương đương — chênh nhau dưới 2%.
- Causal Forest có AUUC thấp nhất trên dataset này, nhưng đây không phải là lý do để bỏ Causal Forest — vì nó là method **duy nhất có confidence interval theo Wager & Athey (2018)** — giá trị thật của nó nằm ở Tab 4.

### Biểu đồ "AUUC Comparison (Higher = Better)"
Trực quan hóa cột AUUC dưới dạng bar chart ngang, sắp xếp giảm dần. Mỗi method có màu riêng (cùng màu với các tab khác để dễ liên hệ).

**Lưu ý quan trọng:** AUUC bằng nhau **không có nghĩa là 2 method chọn cùng nhóm khách hàng**. Hai method có thể đạt cùng AUUC nhưng đề xuất danh sách target khác nhau hoàn toàn.

---

## Tab 3 — Uplift / Qini Curves

Tab này trả lời câu hỏi: **Nếu chỉ gửi email cho top X% khách hàng theo model ranking, thu được bao nhiêu % conversion?**

### Khu vực bên trái: 2 biểu đồ đường

**Biểu đồ trên — Uplift Curve**
- Trục X: `% Population targeted` (0% → 100%) = % khách hàng được nhắm mục tiêu
- Trục Y: `Cumulative uplift gain` = tổng uplift thu được khi target top X% theo `τ̂` giảm dần
- 5 đường màu = 5 method (Causal Forest, X/T/S-Learner, Causal Tree)
- Đường đứt xám = Random baseline (gửi ngẫu nhiên, không theo model)

**Cách đọc:**
- Đường nào nằm **trên** đường random càng nhiều = model càng tốt.
- Diện tích giữa đường model và đường random chính là **AUUC** (đã thấy ở Tab 2).
- Ví dụ: nếu chỉ gửi cho top 20% khách hàng theo Causal Forest ranking → trục Y cho biết thu được bao nhiêu uplift, so với gửi đại trà.

**Biểu đồ dưới — Qini Curve**
- Tương tự uplift curve nhưng có scaling khác để handle treatment lệch (n_treat ≠ n_control).
- Hữu ích cho dataset như Criteo (85% treated / 15% control).

**Toggle methods:** Tích/bỏ tích checkbox phía trên để ẩn hiện đường — dễ so sánh 2-3 method cụ thể.

### Khu vực bên phải

**Box "Key Observations"** — 3 phát hiện tự động sinh:
1. Method nào có AUUC cao nhất + giá trị
2. Method nào có AUUC thấp nhất (baseline reference)
3. **"Sleeping dogs"** — số khách hàng có `τ̂ < 0` theo Causal Forest

**Sleeping dogs là gì?**
- Là nhóm khách hàng mà email **làm giảm** xác suất họ mua hàng (treatment có hại).
- Nguyên nhân thực tế: email spam → khó chịu → unsubscribe / không quay lại.
- Causal Forest phát hiện được, Standard Classifier KHÔNG phát hiện được — vì standard classifier chỉ predict xác suất mua, không phân biệt hành vi do treatment vs do tự nhiên.
- Đây là **giá trị kinh doanh lớn nhất** của uplift modeling: loại sleeping dogs ra khỏi campaign.

**Box "Takeaway"** — 1 câu kết luận, ví dụ:
> "S-Learner wins this benchmark on AUUC — a strong baseline; Causal Forest still provides paper-grade confidence intervals."

---

## Tab 4 — Customer Decision (điểm nhấn của app)

Tab này áp dụng model lên **từng khách hàng cụ thể** và đưa ra khuyến nghị TREAT / DO NOT TREAT.

### Khu vực bên trái — Chọn khách hàng (3 sub-tab)

**Sub-tab "Browse":** Bảng toàn bộ test set (~4,700 dòng cho Hillstrom). Cột τ̂ tô màu — xanh nếu dương, đỏ nếu âm. Click vào 1 row → load vào panel bên phải.

**Sub-tab "Random":** Nút lớn **🎲 Pick Random Customer** — bấm để chọn ngẫu nhiên 1 người. Hữu ích cho demo live: bấm vài lần cho lớp xem mỗi khách hàng có quyết định khác nhau.

**Sub-tab "Top N":** Slider chọn N (mặc định 20). Hiện top N khách hàng có `|τ̂|` lớn nhất — tức là những người email tác động mạnh nhất (cả tích cực lẫn tiêu cực). Đây là danh sách "ưu tiên" cho marketing team.

### Khu vực bên phải — Decision Panel

Hiện sau khi chọn được 1 khách hàng. Có 5 card từ trên xuống:

#### Card 1: Decision Threshold
- **Slider** từ −0.2 đến +0.2, default 0.0
- **Quy tắc quyết định** (text bên dưới slider):
  > Khuyến nghị TREAT nếu `τ̂ > threshold` VÀ `CI_lower > 0`

Quy tắc này có 2 điều kiện AND:
1. **Uplift dương đủ lớn** (vượt ngưỡng)
2. **Tin tưởng thống kê** (cận dưới khoảng tin cậy 95% phải > 0)

→ Đảm bảo chỉ TREAT khi vừa có lợi ích kinh tế vừa có chứng cứ thống kê.

#### Card 2: Customer Summary
- `Customer #N` (mã ID)
- **τ̂ = 0.xxxx** (số to, xanh nếu dương, đỏ nếu âm)
- **95% CI: [lower, upper]** — khoảng tin cậy theo Causal Forest IJ variance
- **Badge to:** ✅ **TREAT** (xanh) hoặc 🚫 **DO NOT TREAT** (đỏ)

**Ví dụ thực tế (Khách hàng #3 trên Hillstrom):**
- τ̂ = 0.0206 (email tăng xác suất visit thêm ~2 percentage points)
- 95% CI: [−0.0670, 0.1082]
- Decision: 🚫 **DO NOT TREAT**

**Vì sao không TREAT dù τ̂ dương?**
- Điều kiện thứ 2 không thỏa: CI_lower = −0.0670 < 0.
- Ý nghĩa: model **không đủ tự tin** rằng email có lợi cho người này. Có khả năng tác dụng ngược (CI có thể âm).
- Chiến lược an toàn: bỏ qua, dành ngân sách cho người chắc chắn TREAT có lợi.

**Cách kéo slider trong demo:**
- Kéo threshold lên 0.05 → người có τ̂ = 0.0206 chắc chắn không TREAT (vì 0.0206 < 0.05)
- Kéo threshold xuống −0.1 → mở rộng đối tượng TREAT
- Kéo về 0 → trở về quy tắc mặc định

#### Card 3: Feature values
Bảng 2 cột (Feature, Value) hiển thị giá trị các đặc trưng của khách hàng đó.

Ví dụ Khách hàng #3:
| Feature | Value |
|---|---|
| recency | 4 |
| history | 766.47 |
| mens | 1 |
| womens | 1 |
| zip_code_enc | 2 |
| newbie | 0 |
| channel_enc | 1 |

→ Khách hàng này mới mua gần đây (4 tháng), chi tiêu cao trong năm qua ($766), đã mua cả đồ nam và nữ, không phải khách mới.

#### Card 4: Feature contribution to τ̂ (approximate)

Bar chart ngang cho biết **đặc trưng nào đẩy τ̂ lên hay xuống** so với mức trung bình dân số.

Cách tính (approximate):
```
contribution_j = (X_customer[j] - X_population_mean[j]) / X_population_sd[j]
                 × variable_importance[j]
```

Đây là phương pháp xấp xỉ — không phải SHAP — nhưng đủ trực quan cho demo.

**Đọc biểu đồ:**
- **Thanh xanh (Positive):** đặc trưng đẩy τ̂ tăng so với trung bình
- **Thanh đỏ (Negative):** đặc trưng kéo τ̂ giảm
- Thanh ngắn = đặc trưng ít ảnh hưởng

Ví dụ Khách hàng #3:
- `history` (thanh xanh dài nhất) → chi tiêu cao là yếu tố mạnh nhất khiến model nghĩ nên gửi email
- `recency` (thanh đỏ) → recency = 4 (mua gần đây) lại kéo τ̂ xuống
- Các thanh khác gần bằng 0 → không ảnh hưởng

#### Card 5: Population comparison

**Text:**
> Customer này có τ̂ (0.0206) cao hơn 6.3% của test population.
> Population mean τ̂ = 0.0763 · median = 0.0763

**Vì sao mean ≈ median?**
- Phân phối τ̂ gần như **đối xứng** (symmetric, hình chuông).
- Khi phân phối đối xứng, mean và median trùng nhau.
- Hillstrom × visit có distribution khá đẹp do dataset balanced và outcome không quá hiếm.

**Con số 6.3% từ đâu?**
- Hệ thống đếm: trong 4,698 test customers, có bao nhiêu người τ̂ thấp hơn khách hàng đang xét.
- Công thức:
  ```
  percentile = (số customer có τ̂ < τ̂_target) / total × 100%
  ```
- Khách hàng #3 có τ̂ = 0.0206 → chỉ ~296 người (6.3%) có τ̂ thấp hơn, còn lại ~4,400 người (93.7%) cao hơn → người này thuộc nhóm **ít phản ứng với email**.

**Density plot bên dưới:**
- Vùng xanh = phân phối τ̂ toàn dân số (test set)
- Đường đỏ thẳng đứng = vị trí khách hàng đang xét
- Đường đứt xám = mốc τ̂ = 0 (ranh giới có lợi vs có hại)

Đường đỏ nằm sát mốc 0 và lệch trái = khách hàng kém phản ứng → củng cố cho quyết định 🚫 DO NOT TREAT.

---

## Tab 5 — Upload CSV

Tab này hướng dẫn cách dùng CSV của bạn thay vì 3 dataset có sẵn.

### Cách dùng (5 bước)
1. Sidebar dropdown chọn "Upload your own CSV"
2. Click "Upload CSV (≤200 MB)" → chọn file
3. App tự detect cột W (binary), Y (numeric), X (còn lại). Override bằng dropdown nếu sai.
4. Click "▶ Re-train" — train 6 learner trên CSV của bạn (80/20 split, seed=42)
5. Sau khi train xong, tất cả tab 1-4 update với dữ liệu mới.

### Yêu cầu CSV
- Cột `W` phải là **binary 0/1**
- Cột `Y` có thể binary hoặc continuous
- Cần **≥2 cột X** (đặc trưng)
- Cột có tên chứa "convert", "visit", "spend", "response" sẽ được app ưu tiên detect làm Y

---

## Sidebar — 3 card chức năng

### Card 1: Dataset
- Dataset dropdown (4 lựa chọn: Hillstrom / Lenta / Criteo / Upload)
- Hillstrom có thêm radio chọn Treatment group (Men's / Women's email)
- Outcome dropdown — thay đổi theo dataset
- Description box mô tả ngắn dataset

### Card 2: Training
- Slider `Trees per learner` (200–1500, default 500)
  - 200 cây: train nhanh ~10s, kết quả noisy hơn
  - 500 cây: balance, default cho demo
  - 1500 cây: ổn định nhất, chậm ~60s
- ETA estimate
- **▶ Re-train** button — kích hoạt training pipeline
- **Learner status** — 6 badge nhỏ với icon ✅ (OK) / ❌ (failed) / ⏳ (pending)

### Card 3: Export
- **💾 Export Report PNG** — xuất PNG ghép 4 thành phần:
  1. Bảng comparison
  2. Bar chart AUUC
  3. Uplift curve
  4. Customer detail (nếu có chọn)
- Lưu vào `results/demo_exports/report_<timestamp>.png`

---

## Phần 3 — Bảng tra cứu nhanh ký hiệu

| Ký hiệu | Tên đầy đủ | Ý nghĩa |
|---|---|---|
| `W` | Treatment indicator | 0 = không treat, 1 = treat |
| `Y` | Outcome | Kết quả quan sát được (visit/conversion/spend) |
| `X` | Features / Covariates | Vector đặc trưng khách hàng |
| `τ` (tau) | Treatment effect (true) | Hiệu ứng treatment thực — không quan sát được |
| `τ̂` (tau-hat) | Treatment effect (estimated) | Ước lượng của model — mỗi customer 1 giá trị |
| `CATE` | Conditional Average Treatment Effect | Hiệu ứng treatment trung bình điều kiện theo X |
| `ATE` | Average Treatment Effect | Hiệu ứng trung bình toàn dân số |
| `CI` | Confidence Interval | Khoảng tin cậy (95%) |
| `CI_lower`, `CI_upper` | Cận dưới / trên CI | `τ̂ ± 1.96 × SE` |
| `SE` | Standard Error | Sai số chuẩn |
| `AUUC` | Area Under Uplift Curve | Diện tích dưới đường uplift — đo chất lượng ranking |
| `Qini` | Qini coefficient | Tương tự AUUC, scale cho treatment lệch |
| `AUC` | Area Under ROC Curve | Đo chất lượng binary classifier |
| `IJ` | Infinitesimal Jackknife | Phương pháp tính variance của random forest (Wager 2014) |
| `VI` | Variable Importance | Tầm quan trọng đặc trưng |

---

## Phần 4 — Các vấn đề thường gặp

### "No model loaded" và không thấy gì
→ Click ▶ Re-train trong sidebar. Hoặc kiểm tra file pre-trained có tồn tại tại `results/demo_pretrained/`.

### Đường uplift curve không hiển thị, chỉ thấy random baseline
→ Refresh browser (F5). Nếu vẫn lỗi, kéo browser to hơn hoặc giảm zoom (Ctrl + −).

### Train quá lâu (>2 phút)
→ Giảm `Trees per learner` xuống 200. Hoặc giảm subsample (chỉ áp dụng Lenta/Criteo).

### Tab 4 không hiện chi tiết khi click row
→ Đảm bảo đã train xong (xem learner status đều ✅). Causal Forest phải OK vì Tab 4 phụ thuộc vào nó.

### Upload CSV báo lỗi "W must be binary"
→ Cột W trong CSV phải chỉ chứa 0 và 1. Nếu là "yes"/"no" hay "T"/"F", convert sang 0/1 trước khi upload.

---

## Phần 5 — Lời khuyên khi demo trước lớp

1. **Trước khi vào lớp**, mở app sẵn, đảm bảo pre-trained load OK (badge xanh lá)
2. Mở browser fullscreen, zoom 100%
3. Theo flow: Tab 1 → 2 → 3 → 4. Đừng nhảy tab loạn.
4. **Tab 4 là điểm nhấn** — dành nhiều thời gian nhất ở đây. Demo:
   - Bấm 🎲 random pick vài lần → cho lớp xem mỗi người có decision khác
   - Kéo threshold slider → cho lớp xem badge đổi TREAT ↔ NOT
   - Chuyển sang Top N → giải thích "đây là 20 khách đáng treat nhất"
5. Nếu lớp hỏi "tại sao mean = median" → giải thích phân phối đối xứng (xem Tab 4 Card 5)
6. Backup: chuẩn bị sẵn PNG export trước, nếu app crash thì show ảnh thay thế.

Chi tiết script 5 phút trong [PRESENTATION_DEMO_5MIN.md](PRESENTATION_DEMO_5MIN.md).
