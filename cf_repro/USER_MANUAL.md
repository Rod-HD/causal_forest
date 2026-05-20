# Hướng dẫn sử dụng — Causal Forest Simulation Dashboard

Tài liệu này mô tả app Shiny tại `r_repro/app.R` — dashboard xem kết quả tái lập bài báo *Wager & Athey (2018) JASA*.

---

## PHẦN 1 — Giải mã logic chức năng UI

### 1.1 Các thành phần tương tác

| Vị trí | Tên component | Loại control | Tác động đến |
|---|---|---|---|
| Sidebar — Card "Design" | **Design selector** | Dropdown (`selectInput`) | Toàn bộ các tab |
| Sidebar — Description box | (chỉ đọc) | Text | Hiển thị spec của design đang chọn |
| Sidebar — Card "Methods" | **Methods checkboxes** | `checkboxGroupInput` | 2 plot trong tab "Comparison Chart" và bảng Results Table |
| Tab "ITE Distribution" — đầu tab | **Dimension d** | Radio buttons (`radioButtons` inline) | Chỉ ảnh hưởng plot ITE trong tab này |
| Header tab | **Tab switcher** | `tabsetPanel` | Chuyển giữa 3 view: Comparison Chart / ITE Distribution / Results Table |

### 1.2 Phân loại dữ liệu — 2 nguồn khác nhau

App này **không gọi mô hình thời gian thực**. Nó là **viewer** cho 2 loại data:

1. **Dữ liệu thực nghiệm pre-computed (CSV trên đĩa):**
   - 54 file CSV tại `results/design{1,2,3}/r_{method}_d{d}.csv`
   - Mỗi file: cột `replication`, `mse`, `coverage` qua R lần lặp lại
   - Được sinh trước bởi `run_experiment.R` (đã chạy xong)
   - **Dùng cho:** tab Comparison Chart và Results Table

2. **Dữ liệu mô phỏng sinh trực tiếp (on-the-fly):**
   - Hàm `gen_design1/2/3()` trong `dgp.R` sinh **4000 điểm test** ngay khi user thao tác
   - Lấy giá trị `τ(X)` thật (ground truth) — không liên quan đến model dự đoán
   - **Dùng cho:** tab ITE Distribution

### 1.3 Luồng dữ liệu (Data Flow)

```
[USER ACTION]              [REACTIVE]                  [OUTPUT]
─────────────────────────────────────────────────────────────────
Chọn Design (D1/D2/D3)
        │
        ├─► data_all()  ──► đọc 18 file CSV của design đó
        │        │                    │
        │        ▼                    ▼
        │   tính mean(mse), mean(coverage), SE
        │        │
        ├─► data_filtered() ──► lọc theo methods đã check
        │        │                    │
        │        ▼                    ▼
        │   ┌─ plot_mse ──── Plotly chart MSE vs d
        │   ├─ plot_coverage ─ Plotly chart Coverage vs d
        │   └─ results_table ─ Bảng mean ± SE
        │
        └─► (sidebar) updateCheckboxGroupInput
                       (reset danh sách methods theo design)

Chọn d (radio buttons)
        │
        └─► ite_tau() ──► gen_designX(4000, d) ──► τ values
                 │                                     │
                 ▼                                     ▼
            ┌─ plot_ite ────── Plotly density của τ
            └─ ite_stats ───── Cards Mean/SD/Min/Max
```

**Lưu ý quan trọng:** Khi đổi Design ở sidebar, `observeEvent(input$design, ...)` **tự reset** danh sách Methods checkboxes theo design mới (vì D2 dùng 7-NN/50-NN, D1+D3 dùng 10-NN/100-NN).

---

## PHẦN 2 — Hướng dẫn sử dụng từng bước

### 2.1 Khởi động app

Mở terminal trong thư mục dự án và chạy:

```bash
cd cf_repro/r_repro"
Rscript -e "shiny::runApp('app.R', launch.browser=TRUE)"
```

Browser sẽ tự mở. Nếu không, copy URL ở console (`http://127.0.0.1:xxxx`) dán vào trình duyệt.

### 2.2 Quy trình thao tác cơ bản

**Bước 1 — Chọn kịch bản thực nghiệm (Design):**
- Ở sidebar trái, mở dropdown **Design** và chọn 1 trong 3:
  - **Design 1 — Confounding:** kiểm tra khả năng chống bias khi có yếu tố gây nhiễu
  - **Design 2 — Smooth Heterogeneity:** hiệu ứng can thiệp biến đổi mượt
  - **Design 3 — Sharp Heterogeneity:** hiệu ứng can thiệp thay đổi đột ngột
- Hộp xám phía dưới hiển thị thông số (n, R, tau, e(x), m(x), goal).

**Bước 2 — Chọn các phương pháp muốn so sánh (Methods):**
- Tích/bỏ tích các checkbox dưới card **Methods**.
- Ví dụ: muốn xem riêng Causal Forest → bỏ tích 2 baseline kNN.
- Plot và bảng tự cập nhật ngay (reactive).

**Bước 3 — Chọn tab muốn xem:**
- **Comparison Chart:** xem MSE và Coverage theo dimension d
- **ITE Distribution:** xem phân phối hiệu ứng thật τ(X)
- **Results Table:** xem số liệu chi tiết dạng bảng

**Bước 4 — (Chỉ tab ITE Distribution) Chọn dimension d:**
- Phía trên plot có dãy radio buttons **Dimension d**.
- Click số d muốn xem. Plot và stats (Mean/SD/Min/Max) cập nhật ngay.

### 2.3 Cách đọc kết quả — Giải thích đơn giản

#### Biểu đồ "MSE vs Dimension d"

> **MSE là gì?** Tưởng tượng bạn đoán điểm thi của bạn bè. **MSE = "trung bình bình phương khoảng cách giữa đoán và thật"**. Số càng **nhỏ** → đoán càng chính xác.

- Trục ngang **d**: số chiều dữ liệu (càng cao càng "khó đoán" vì có nhiều feature gây nhiễu).
- Trục đứng **MSE**: sai số dự đoán.
- Mỗi đường màu = 1 phương pháp. Đường nào **thấp hơn** → phương pháp đó tốt hơn ở dimension đó.
- **Quan sát điển hình:** Causal Forest (xanh) thường thấp nhất, kNN cao hơn → CF mạnh hơn khi nhiều chiều.

#### Biểu đồ "Coverage vs Dimension d"

> **Coverage là gì?** Mô hình không chỉ đoán 1 con số, nó còn nói "tôi tin câu trả lời nằm trong khoảng A → B với xác suất 95%". **Coverage = tỷ lệ thực tế khoảng đó chứa câu trả lời đúng**. Lý tưởng là **đúng 95%**.

- Đường nét đứt **đỏ ở 0.95** = mục tiêu lý tưởng.
- Đường gần 0.95 nhất → mô hình "trung thực" về độ tự tin.
- **Cao hơn 0.95** = mô hình bảo thủ quá (CI quá rộng).
- **Thấp hơn 0.95** = mô hình tự tin quá (CI quá hẹp) → nguy hiểm.

#### Biểu đồ "ITE Distribution"

> **ITE (Individual Treatment Effect)** = nếu cho 1 người uống thuốc A so với không uống, người đó sẽ cải thiện bao nhiêu? Mỗi người có thể có hiệu ứng khác nhau.

- Trục ngang **τ(X)**: mức cải thiện thật của 1 cá thể.
- Trục đứng **Density**: bao nhiêu người có mức cải thiện đó.
- Đường đứng đỏ = giá trị trung bình.
- **Design 1:** đỉnh nhọn tại 0 (mọi người đều không có cải thiện thật).
- **Design 2/3:** đường có dạng đồi, một số người cải thiện ít, một số nhiều.

#### Bảng "Results Table"

- Mỗi hàng: 1 phương pháp ở 1 dimension d.
- `MSE (mean ± SE)`: sai số trung bình ± sai số Monte-Carlo.
- `Coverage (mean ± SE)`: độ phủ thực tế ± sai số.
- Phần `± SE` cho biết kết quả **ổn định** đến mức nào (số nhỏ = ổn định).

### 2.4 Troubleshooting (Lỗi thường gặp)

**Lỗi 1: Plot trống/không hiện gì khi chọn xong**
- *Nguyên nhân:* Bạn đã bỏ tích **tất cả** Methods checkboxes.
- *Xử lý:* Tích lại ít nhất 1 method trong card **Methods**.

**Lỗi 2: Đổi Design xong, methods cũ bị mất chọn**
- *Nguyên nhân:* Mỗi design dùng k khác nhau (D2 = 7-NN/50-NN, D1+D3 = 10-NN/100-NN). App tự reset checkbox về **tất cả** khi đổi design.
- *Xử lý:* Đây là behavior cố ý — chỉ cần bỏ tích lại nếu muốn lọc.

**Lỗi 3: Tab ITE Distribution không có radio button d**
- *Nguyên nhân:* App đang load lần đầu, `uiOutput("d_slider_ui")` chưa render xong.
- *Xử lý:* Đợi 1-2 giây hoặc refresh trang (F5).

**Lỗi 4: App báo "could not find function" khi khởi động**
- *Nguyên nhân:* Thiếu package R (`shiny`, `plotly`, `ggplot2`, `dplyr`).
- *Xử lý:* Mở R console và chạy:
  ```r
  install.packages(c("shiny","plotly","ggplot2","dplyr"))
  ```

**Lỗi 5: Số liệu trong bảng/plot bị trống (NA)**
- *Nguyên nhân:* Thiếu file CSV kết quả ở `results/design{N}/`.
- *Xử lý:* Chạy lại cell bị thiếu:
  ```bash
  Rscript run_experiment.R --design <N> --method <method> --d <d>
  ```
