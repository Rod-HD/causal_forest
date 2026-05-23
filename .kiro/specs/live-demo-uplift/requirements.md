# Requirements — Live Demo Uplift App (`app_demo.R`)

## Context

App Shiny mới phục vụ thuyết trình trước lớp CS114. Mục tiêu: so sánh **6 uplift learners** (Standard Classifier, S/T/X-Learner, Causal Tree, Causal Forest) trên dataset marketing thực, đồng thời cho phép user upload CSV và đưa ra quyết định **TREAT / NOT TREAT** cho từng khách hàng cụ thể.

App này **không thay thế** `app_real.R` (giữ nguyên cho mục đích cũ). App mới đặt tại `cf_repro/r_repro/app_demo.R`.

## User stories

### US-1 — Dataset Overview (Tab 1)
Là một sinh viên thuyết trình, tôi muốn hiển thị thông tin tổng quan dataset (size, treatment, outcome, train/test split, baseline rates) để lớp hiểu bài toán trước khi xem kết quả.

**Acceptance:**
- Hiển thị 5 thông tin: Name, Size (N × M), Treatment, Outcome, Train/Test split
- Cho phép chọn dataset từ 3 lựa chọn: Hillstrom (default), Lenta, Criteo
- Cho phép chọn outcome:
  - Hillstrom: `visit` (default), `conversion`, `spend`
  - Lenta: `response`
  - Criteo: `visit`, `conversion`
- Hộp mô tả dataset (mục đích, nguồn)
- Visualization: phân phối W (treatment vs control), phân phối Y theo W

### US-2 — Model Comparison Quantitative (Tab 2)
Là sinh viên, tôi muốn so sánh 6 learners qua bảng + bar chart để chọn ra model tốt nhất.

**Acceptance:**
- Bảng quantitative comparison với các cột:
  - Method
  - AUUC ↑ (Area Under Uplift Curve)
  - Qini ↑
  - AUC (chỉ Standard Classifier có giá trị, các learner khác để "—")
- 6 rows: Standard Classifier, S-Learner, T-Learner, X-Learner, Causal Tree, Causal Forest
- Causal Forest row **bôi đậm** (highlight)
- Bar chart so sánh AUUC giữa các method
- Train **on-the-fly** mỗi khi user đổi dataset/outcome (chấp nhận chờ 10–30s)
- Hiển thị progress notification trong lúc train

### US-3 — Uplift / Qini Curves (Tab 3)
Là sinh viên, tôi muốn show uplift curve và key findings để giải thích model tốt nhất hoạt động như thế nào.

**Acceptance:**
- Uplift curve của 6 learners cùng plot, cộng đường Random baseline
- Cho user chọn 1 hoặc nhiều method để zoom (checkbox group)
- Box "Key Observations" với 3 findings tự động sinh:
  1. Method nào có AUUC cao nhất
  2. Method nào tệ hơn Random (nếu có)
  3. Có "sleeping dogs" hay không (số khách hàng có τ̂ < 0)
- Box "Takeaway" — câu kết luận 1 dòng

### US-4 — Customer Decision (Tab 4) — Tính năng chính
Là sinh viên, tôi muốn chọn 1 khách hàng cụ thể và app khuyến nghị có nên TREAT hay không, kèm explanation.

**Acceptance:**
- **Sub-tab 4a — Pick a Customer:** Bảng test set, click row → mở Detail Panel
- **Sub-tab 4b — Random Pick:** Nút "🎲 Pick Random Customer" → chọn ngẫu nhiên
- **Sub-tab 4c — Top N:**
  - Slider chọn N (default 20, range 5–500)
  - Bảng hiện top N customer theo `|τ̂|` descending
  - Click row → mở Detail Panel
- **Detail Panel** (hiện trong card lớn bên phải, expandable):
  - Tất cả feature values của customer (recency=6, history=$150.20, ...)
  - **Giá trị τ̂ (uplift estimate)** — số to, màu nổi bật
  - CI 95%: `[τ̂_lower, τ̂_upper]`
  - **Decision badge:** "✅ TREAT" hoặc "🚫 DO NOT TREAT" — to, màu xanh/đỏ
  - **Threshold slider:** user kéo để chỉnh ngưỡng quyết định (default 0.0, range −0.2 to +0.2)
  - **Decision rule giải thích:** "Recommend TREAT if τ̂ > threshold AND CI_lower > 0"
  - **Feature contribution:** mini bar chart cho thấy feature nào kéo τ̂ lên/xuống (dùng grf `get_forest_weights` hoặc partial dependence approximation)
  - So sánh với population: "Customer này có τ̂ cao hơn 78% dân số"

### US-5 — Upload CSV của user (Tab 5)
Là sinh viên, tôi muốn upload CSV của riêng tôi, app train + predict + cho phép chọn từng khách hàng.

**Acceptance:**
- File input nhận CSV ≤200MB
- Tự động detect cột W, Y, X (tái dùng `detect_columns()` từ `app_real.R`)
- User có thể override qua dropdown
- Sau khi confirm columns → nút "Train all 6 learners on this CSV"
- Sau khi train xong, **kích hoạt lại các tab 2, 3, 4 với dữ liệu mới**
- Lưu kết quả vào reactiveVal để chuyển tab không mất

### US-6 — Export Report PNG
Là sinh viên, tôi muốn xuất các plot/bảng ra PNG để chèn vào slide.

**Acceptance:**
- Mỗi plot có nút "💾 Save PNG" góc trên phải (dùng plotly built-in)
- Có nút "Export full report" — xuất 1 file PNG ghép 4 thành phần:
  1. Bảng comparison
  2. Bar chart AUUC
  3. Uplift curve
  4. Detail panel của customer được chọn (nếu có)
- Lưu vào `cf_repro/results/demo_exports/report_<timestamp>.png`

## Non-functional requirements

### NF-1 — Performance (CRITICAL — 5-minute demo)
- **Hillstrom × visit (default)** phải có pre-trained `.rds` file để load instant (<1 giây) khi mở app
- Train on-the-fly (đổi outcome/dataset/upload): phải ≤30 giây trên Windows 16 cores
- UI không freeze quá 1 giây cho mọi tương tác trừ lúc train
- Detail panel update khi click row: ≤200ms

### NF-2 — Demo-ready
- App phải chạy được offline (không cần internet)
- Mọi notification phải có thông báo rõ ràng trạng thái
- Không có lỗi nào hiện ra console trong lúc demo

### NF-3 — Code quality
- Tái sử dụng tối đa code từ `methods.R`, `app_real.R`
- File mới: `learners.R` (chứa 6 learner functions), `metrics.R` (AUUC, Qini, AUC)
- File chính: `app_demo.R`
- Không phụ thuộc package mới ngoài `grf`, `FNN`, `ranger` (mới — cho Standard Classifier nhanh)

### NF-4 — Reproducibility
- Master seed = 42 cho mọi `set.seed()`
- 80/20 train/test split cố định seed=42

## Out of scope

- Không support continuous treatment (chỉ binary W)
- Không support multi-arm treatment (Hillstrom có 3 arm nhưng chỉ chọn 1 vs control như `app_real.R`)
- Không tự động download dataset từ internet (đã có raw `.rds` sẵn)
- Không thay đổi `app.R` (simulation) và `app_real.R` (cũ)
