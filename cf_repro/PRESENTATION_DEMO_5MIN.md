# 5-Minute Live Demo Script — `app_demo.R`

> Hướng dẫn chi tiết cho buổi thuyết trình CS114. Demo 5 phút trên Hillstrom dataset.

---

## Pre-demo checklist (làm 5–10 phút trước khi thuyết trình)

1. **Kiểm tra packages:** chạy `Rscript 00_setup.R` — phải báo `OK` cho cả 9 package
2. **Kiểm tra pre-trained:** file `cf_repro/results/demo_pretrained/hillstrom_men_visit.rds` phải tồn tại. Nếu thiếu:
   ```bash
   cd cf_repro/r_repro
   Rscript pretrain_demo.R --dataset hillstrom --group men --outcome visit
   ```
3. **Launch app:**
   ```bash
   Rscript -e "shiny::runApp('app_demo.R', launch.browser=TRUE)"
   ```
4. **Quick smoke test trước khi vào lớp:**
   - Open Tab 1 → có hiện đúng "Hillstrom MineThatData (men group)"
   - Open Tab 2 → bảng có đủ 6 dòng learner, AUUC > 0 cho ít nhất 4 method
   - Open Tab 4 → click "🎲 Pick Random" → có ngay decision badge
   - Kéo slider threshold → thấy badge chuyển TREAT ↔ DO NOT TREAT
5. **Backup:** chuẩn bị sẵn 1 screenshot PNG đã export từ trước (phòng app crash)

---

## Demo flow — 5 phút

### Phút 0:00 – 0:30  ·  Mở đầu (slide)

> "Bài toán uplift modeling: thay vì hỏi *ai sẽ mua hàng*, ta hỏi *ai mua hàng VÌ chúng ta gửi email* — tức là CATE (Conditional Average Treatment Effect). Hôm nay tôi so sánh 6 phương pháp trên dataset Hillstrom (64K khách hàng email marketing thực)."

Chuyển sang app, mở **Tab 1 — Dataset Overview**.

### Phút 0:30 – 1:00  ·  Tab 1 (Dataset Overview)

Chỉ vào sidebar và đọc:
- **Name:** Hillstrom MineThatData (men's email campaign)
- **Size:** ~23K samples × 7 features (recency, history, mens, womens, zip_code, newbie, channel)
- **Treatment:** binary email (50% treated, 50% control)
- **Outcome:** visit website (binary — ~15% baseline rate)
- **Train/Test split:** 80/20, seed=42

Chỉ vào 2 biểu đồ:
- "Bên phải trên: 50/50 treated/control — fully randomized A/B test"
- "Bên phải dưới: outcome rate ở nhóm treated (xanh) cao hơn control (xám) một chút — đó là **average treatment effect**. Nhưng chúng ta muốn biết **per-customer effect** chứ không phải trung bình."

### Phút 1:00 – 2:00  ·  Tab 2 (Quantitative Comparison)

Click sang Tab 2.

> "Tôi đã train sẵn 6 learner. Đây là bảng so sánh:"

Đọc nhanh bảng:
- **AUUC** (Area Under Uplift Curve) = chỉ số chính, cao hơn = tốt hơn
- **Qini** = chỉ số tương tự, robust với unbalanced treatment
- **AUC** chỉ có ở Standard Classifier — vì nó không phải uplift model, không có τ

> "Causal Forest, X-Learner, T-Learner, S-Learner đều có AUUC tương đương nhau (~220). Causal Tree (small ensemble) thấp hơn vì ít cây hơn. Standard Classifier không có AUUC vì nó không model treatment effect."

Click vào bar chart bên dưới:
> "Trực quan hơn — top 4 method gần như tie. Nhưng có một điểm Causal Forest **vượt trội**: nó là method duy nhất có confidence interval theo paper Wager & Athey (2018) — chuyển sang Tab 4 sẽ thấy."

### Phút 2:00 – 2:30  ·  Tab 3 (Uplift Curves)

Click sang Tab 3.

> "Uplift curve cho thấy: nếu ta xếp khách hàng theo τ̂ giảm dần, target top X% sẽ thu được bao nhiêu % uplift. Đường đứt xám là baseline ngẫu nhiên."

Chỉ vào panel bên phải:
- **Key Observations** (auto-generated):
  - Method nào AUUC cao nhất
  - "Sleeping dogs detected: N customers có τ̂ < 0" — đây là điểm thú vị

> "Sleeping dogs nghĩa là gửi email LÀM GIẢM xác suất họ mua. Causal Forest phát hiện được — Standard Classifier không bao giờ phát hiện được vì nó chỉ predict xác suất mua, không phân biệt cause vs correlation."

### Phút 2:30 – 4:00  ·  Tab 4 (Customer Decision) — Điểm nhấn

Click sang Tab 4 → sub-tab "Random".

> "Đây là phần thú vị nhất — quyết định cho từng khách hàng cụ thể."

Click nút **🎲 Pick Random Customer**.

Khi detail panel bên phải hiện ra, chỉ vào từng phần:
- **τ̂ = 0.xxxx** (số to) — uplift ước lượng cho khách hàng này
- **95% CI: [lower, upper]** — khoảng tin cậy theo grf IJ variance
- **TREAT / DO NOT TREAT** (badge to) — quyết định tự động
- **Decision rule:** "TREAT if τ̂ > threshold AND CI_lower > 0"

Bây giờ **kéo threshold slider** từ 0.0 lên 0.05:
> "Tôi tăng ngưỡng quyết định. Khách hàng này không còn được khuyến nghị TREAT nữa — ngưỡng đã vượt qua giá trị τ̂."

Kéo về 0.0:
> "Trở lại — TREAT."

Click nút 🎲 vài lần nữa để cho thấy mỗi khách hàng cho ra decision khác nhau.

Click sub-tab **"Top N"** → slider để N = 20:

> "Đây là 20 khách hàng đáng treat nhất — sắp xếp theo |τ̂|. Trong production, marketing team chỉ gửi email cho list này thay vì toàn bộ database."

Cuộn xuống xem **Feature values** và **Population comparison**:
> "Khách hàng này có recency = X, history = Y. τ̂ của họ cao hơn Z% dân số."

### Phút 4:00 – 5:00  ·  Kết luận

> "Tóm tắt:
> 1. 6 learners đều có thể ước lượng uplift, nhưng chỉ **Causal Forest** cho khoảng tin cậy có lý thuyết back-up (paper-grade IJ variance từ Wager & Athey 2018).
> 2. Trong demo này, top 4 method tương đương về AUUC — nhưng Causal Forest cho phép ta nói **mức độ tin tưởng** vào từng prediction.
> 3. Khi áp dụng thực tế (marketing campaign), ta:
>    - Loại bỏ **sleeping dogs** (τ̂ < 0) — không gửi email
>    - Target **persuadables** (τ̂ > threshold, CI_lower > 0)
>    - Bỏ qua **lost causes** (τ̂ ≈ 0)
> 4. Code, paper reproduction, và app này có trên GitHub repo của tôi."

Câu hỏi & trả lời.

---

## Tips trong demo

### Nếu lớp hỏi "Tại sao 50-tree gọi là Causal Tree mà không phải 1 tree?"
> "Single tree quá noisy cho real data — bias rất lớn. 50-tree là small ensemble — gọi 'Causal Tree' để minh họa khái niệm tree-based, đối chiếu với 500-tree forest. Honest về implementation, không sách vở."

### Nếu hỏi "Tại sao S/T/X-Learner không có CI?"
> "Meta-learners không có closed-form variance estimator. Có thể bootstrap nhưng đắt. Causal Forest paper đề xuất Infinitesimal Jackknife — chỉ áp dụng được cho forest, không cho ranger black-box."

### Nếu hỏi "Tại sao dùng `grf` mà không phải `causalTree` của Athey?"
> "`causalTree` package từ 2016, không còn maintain, không có trên CRAN. `grf` là package mới của cùng tác giả (Wager & Athey), implement cùng thuật toán nhưng tối ưu hơn và có variance estimator chính thức."

### Nếu hỏi "Threshold mặc định 0 có hợp lý không?"
> "Mặc định nghĩa là: gửi email nếu τ̂ > 0 (treatment có lợi) VÀ CI_lower > 0 (chắc chắn có lợi). Cost-aware threshold sẽ là `cost_email / outcome_value` — ví dụ email cost $0.10, conversion $5 → threshold = 0.02."

---

## Backup plan nếu app crash

1. Reload page (F5)
2. Nếu Tab 4 lỗi: chuyển sang Tab 2 — vẫn đủ điểm chính
3. Nếu app crash hoàn toàn: mở screenshot PNG đã export sẵn (trong `results/demo_exports/`)
4. Worst case: dùng [PRESENTATION_THEORY.md](PRESENTATION_THEORY.md) như slide tĩnh

---

## Time budget per tab

| Tab | Mục đích | Thời gian |
|---|---|---|
| Tab 1 | Đặt context dataset | 30s |
| Tab 2 | So sánh quantitative | 60s |
| Tab 3 | Uplift curve + sleeping dogs | 30s |
| Tab 4 | Per-customer decision (highlight) | 90s |
| Closing | Tóm tắt + Q&A buffer | 60s |
| **Total** | — | **5 min** |
