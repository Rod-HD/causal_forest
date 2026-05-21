# Phần 2 — Tham khảo Demo: Chức năng UI của 2 app Shiny
## Causal Forest — Reference cho người thuyết trình

> **Mục đích:** mô tả **chức năng** mỗi control trong 2 app, **trả về gì**, **hoạt động bên dưới ra sao**. Đọc xong, bạn tự dựng kịch bản phù hợp với khán giả của mình.
>
> Không phải script thuyết trình. Là **datasheet** của UI.

---

## 0. Khởi động

```bash
# Tab terminal 1 — App SIMULATION (UI paper)
cd cf_repro/r_repro
Rscript -e "shiny::runApp('app.R', port=4001, launch.browser=TRUE)"

# Tab terminal 2 — App REAL DATA
cd cf_repro/r_repro
Rscript -e "shiny::runApp('app_real.R', port=4002, launch.browser=TRUE)"
```

- **Tab A:** `http://127.0.0.1:4001` → `app.R` (paper simulation)
- **Tab B:** `http://127.0.0.1:4002` → `app_real.R` (real datasets)

**Prerequisite files:**
| File | Tạo bởi | Cho app nào |
|---|---|---|
| 54 CSV `results/design{1,2,3}/r_*_d*.csv` | `run_experiment.R` | App A |
| `results/real/*_raw.rds` | `prepare_real_data.R` | App B (custom run) |
| `results/real/*.rds` + `*_cate.csv` | `train_pretrained.R` | App B (pre-trained) |

---

# APP A — `app.R` (UI tái lập paper)

## A.0 Bố cục

```
┌──────────────────────────────────────────────────────────────┐
│ Causal Forest Simulation — Wager & Athey (2018) JASA        │
├─────────────┬────────────────────────────────────────────────┤
│ [Sidebar]   │  [ Comparison Chart | ITE Distribution | Table]│
│             │                                                │
│ Design ▼    │  ┌─ MSE chart ──┐  ┌─ Coverage chart ──┐       │
│ [box desc]  │  │              │  │   ──── 0.95       │       │
│             │  └──────────────┘  └───────────────────┘       │
│ Methods:    │                                                │
│ ☑ CF        │                                                │
│ ☑ k-NN(s)   │                                                │
└─────────────┴────────────────────────────────────────────────┘
```

## A.1 Sidebar — Card "Design"

### `selectInput("design")` — Dropdown chọn Design
- **Choices:** Design 1 / Design 2 / Design 3 (3 kịch bản simulation từ paper Section 6).
- **Tác động:** **toàn bộ** tab (cả 3 plot + table + ITE).
- **Trả về:** `input$design ∈ {"1","2","3"}`.
- **Behavior bên dưới:**
  - Trigger reactive `data_all()` → đọc 18 file CSV của design đó (`r_{method}_d{d}.csv`, method ∈ {cf, knn_low, knn_high}, d ∈ 6 giá trị).
  - Trigger `observeEvent(input$design, ...)` → **reset checkbox Methods** vì mỗi design dùng k khác (D2 = 7-NN/50-NN, D1+D3 = 10-NN/100-NN).
  - Trigger `output$d_slider_ui` → render lại radio button d trong tab ITE.

### `textOutput("design_desc")` — Box mô tả (read-only)
- Hiển thị spec của design: `n`, `R`, `B`, `sample.fraction`, công thức `τ(x)`, `e(x)`, `m(x)`, `goal`.
- Tự cập nhật khi đổi Design.

## A.2 Sidebar — Card "Methods"

### `checkboxGroupInput("methods")` — Checkbox phương pháp
- **Choices:** thay đổi theo Design.
  - D1, D3: `Causal Forest`, `10-NN`, `100-NN`
  - D2: `Causal Forest`, `7-NN`, `50-NN`
- **Mặc định:** tick tất cả.
- **Tác động:** filter `data_filtered()` → ảnh hưởng 2 plot ở tab Comparison + bảng Results Table.
- **KHÔNG** ảnh hưởng tab ITE Distribution (vì ITE là ground truth, không phụ thuộc method).
- **Edge case:** bỏ tick hết → `req(input$methods)` chặn → plot trống.

## A.3 Main panel — Tab "Comparison Chart"

### `plotlyOutput("plot_mse")` — Plot MSE vs d
- **Trục X:** `d` (dimension covariate, từ 2 đến 20 hoặc 8).
- **Trục Y:** `mean(mse)` qua R replications.
- **Mỗi đường:** 1 method, màu theo `COLORS` (CF = `#2166ac`, kNN = đỏ/cam).
- **Hover:** Plotly tooltip hiện Method, d, MSE.
- **Nguồn data:** `data_filtered()` → đọc CSV pre-computed, không train.
- **Ý nghĩa:** đường thấp = method tốt.

### `plotlyOutput("plot_coverage")` — Plot Coverage vs d
- Tương tự MSE, nhưng Y = `mean(coverage)`.
- **Đường nét đứt đỏ tại y = 0.95** = mục tiêu lý tưởng (95% CI honesty).
- Đường gần 0.95 nhất → CI hợp lệ.
- Trên 0.95 = bảo thủ; dưới 0.95 = tự tin quá.

## A.4 Main panel — Tab "ITE Distribution"

### `uiOutput("d_slider_ui")` → `radioButtons("d_ite")` — Chọn d
- **Choices:** 6 giá trị d của design hiện tại (vd D2: 2, 3, 4, 5, 6, 8).
- **Inline = TRUE** (xếp ngang).
- **Mặc định:** giá trị thứ 2 trong list.
- **Trả về:** `input$d_ite` (string).
- **Tác động:** trigger `ite_tau()`.

### `ite_tau()` — Reactive sinh τ ground truth
- **KHÔNG đọc CSV pre-computed.** Mỗi lần thay đổi → gọi `gen_designX(n=4000, d=input$d_ite, seed=99)` từ `dgp.R`.
- **Trả về:** vector 4000 giá trị τ thật theo công thức:
  - D1: `τ ≡ 0` (vector toàn 0).
  - D2: `σ20(x₁) × σ20(x₂)` (smooth sigmoid).
  - D3: `σ12(x₁) × σ12(x₂)` (sharp sigmoid).
- **Thời gian:** <1s (chỉ là `runif` + công thức scalar).

### `plotlyOutput("plot_ite")` — Density của τ thật
- `geom_density()` + `geom_vline(xintercept = mean(tau))` (đỏ đứt).
- **Title:** "True ITE (tau) Distribution".
- **Subtitle:** label design, d, n=4000.
- Khán giả thấy hình dạng đúng của `τ(X)` mà CF cần học.

### `uiOutput("ite_stats")` — 4 card thống kê
- Mean, SD, Min, Max của `tau` vector.
- Class CSS `.stat-item` (giống app_real).

## A.5 Main panel — Tab "Results Table"

### `tableOutput("results_table")`
- 1 hàng = 1 (method, d).
- Cột:
  - `Method`: tên method (theo Methods checkbox).
  - `d`: dimension.
  - `MSE (mean ± SE)`: format `%.4f ± %.4f`. SE = `sd(mse)/√R`.
  - `Coverage (mean ± SE)`: format `%.3f ± %.3f`.
- Sort: `arrange(method, d)`.
- Mục đích: số liệu chính xác đối chiếu với Table 1-6 trong paper.

## A.6 Luồng dữ liệu App A (tóm tắt)

```
input$design ───┬──► data_all() ──► 18 CSV → mean+SE
                │
                ├──► data_filtered() (lọc theo Methods) ──► plot_mse, plot_coverage, results_table
                │
                └──► ite_tau() ──► gen_designX(4000, d) ──► plot_ite + ite_stats

input$methods ─► data_filtered()
input$d_ite   ─► ite_tau()
```

**Lưu ý:** App A **không gọi `grf::causal_forest()` runtime**. Mọi MSE/Coverage đến từ CSV. Mọi τ đến từ công thức dgp.R.

---

# APP B — `app_real.R` (UI demo dataset thực)

## B.0 Bố cục

```
┌──────────────────────────────────────────────────────────────────┐
│ Causal Forest — Real Data Showcase    [mode_badge top-right]    │
├─────────────────┬────────────────────────────────────────────────┤
│ [Sidebar]       │ [CATE Overview | Targeting | VarImp | Table]  │
│                 │                                                │
│ Dataset ▼       │  ─ Stats row ─                                 │
│ (group radio)   │  ─ Plot ─                                      │
│ Outcome ▼       │                                                │
│ (csv upload)    │                                                │
│ [Custom Run]    │                                                │
│ Subsample n     │                                                │
│ Trees: ──●──    │                                                │
│ [▶ Run]         │                                                │
└─────────────────┴────────────────────────────────────────────────┘
```

## B.1 Sidebar — Card "Dataset"

### `selectInput("dataset")` — Dropdown chọn dataset
- **Choices:** `hillstrom`, `lenta`, `criteo`, `upload`.
- **Trả về:** `input$dataset`.
- **Tác động:**
  - `conditionalPanel` hiện/ẩn group radio (chỉ Hillstrom có).
  - `output$outcome_selector` render dropdown Outcome theo dataset.
  - `conditionalPanel` hiện file picker (chỉ Upload).
  - `output$subsample_slider_ui` hiện slider subsample (ẩn cho Hillstrom).
  - `pretrained_key()` reactive cập nhật → trigger auto-load `.rds`.

### `radioButtons("hillstrom_group")` — Chỉ khi dataset = hillstrom
- **Choices:** `men` (Men's Email vs Control) / `women` (Women's Email vs Control).
- **Lý do:** Hillstrom có 3 nhánh treatment (None / Men's / Women's). Để có binary W, ta tách 2 phân tích.
- **Tác động:** đổi sang file `.rds` khác (`hillstrom_men_*` vs `hillstrom_women_*`).

### `uiOutput("outcome_selector")` → `selectInput("outcome")`
- **Choices:** thay đổi theo dataset.
  - Hillstrom: `visit` (binary) / `conversion` (binary) / `spend` (continuous).
  - Lenta: `response` (binary).
  - Criteo: `visit` / `conversion`.
- **Trả về:** `input$outcome` = key nội bộ (`"visit"`, `"conversion"`, `"spend"`...).
- **Tác động:** đổi file `.rds` load + đổi `seg_threshold` (xem B.10).

### `fileInput("csv_file")` — Chỉ khi dataset = upload
- **Accept:** `.csv`, max 200 MB (set bởi `options(shiny.maxRequestSize = 200 * 1024^2)`).
- **Trả về:** `input$csv_file$datapath` (đường dẫn temp).
- **Behavior:** `upload_preview()` reactive đọc 2000 hàng đầu để auto-detect cột.

### `uiOutput("upload_col_selectors")` — Chỉ khi upload có file
- **`selectInput("upload_W")`:** chọn cột treatment. Auto-suggest cột binary (0/1).
- **`selectInput("upload_Y")`:** chọn cột outcome. Auto-suggest theo regex `convert|visit|spend|outcome|revenue|response|target|^y$`.
- **`checkboxGroupInput("upload_X")`:** chọn feature columns. Default = tất cả trừ W, Y, id-like.
- **`tags$details("upload_quick_stats")`:** bảng Quick Stats — cho mỗi cột show Type (binary/ordinal/numeric/categorical/id-like), Unique count, % NA.

### `textOutput("dataset_desc")` — Box mô tả dataset
- Multi-line text giải thích nguồn dữ liệu, n, W, Y, goal.

## B.2 Sidebar — Card "Custom Run"

> **Quan trọng:** card này CHỈ để **retrain với tham số custom**. Pre-trained tự load không cần nhấn nút.

### `uiOutput("subsample_slider_ui")` → `sliderInput("subsample_n")`
- **Range:** 1000 → `max_n` (45K Hillstrom / 100K Lenta / 100K Criteo / 50K upload).
- **Default:** `min(10000, max_n)`.
- **Hidden:** khi dataset = hillstrom (đã dùng full).
- **Tác động:** giới hạn n trước khi train CF.

### `sliderInput("num_trees")`
- **Range:** 200 → 2000, step 100.
- **Default:** 500.
- **Tác động:** truyền vào `grow_causal_forest(num_trees = ...)`.

### `uiOutput("topk_toggle_ui")` — Hiện khi đã có `var_importance`
- `checkboxInput("use_topk")`: bật để chỉ train với top-K features.
- `sliderInput("topk_n")`: K = 2 → số features tối đa, default min(10, p).
- **Behavior:** trước khi train, filter X_cols xuống top-K theo VI từ kết quả trước đó.
- **Use case:** chứng minh chỉ cần vài feature quan trọng cũng đủ predict τ.

### `uiOutput("eta_display")` — Hiển thị thời gian ước lượng
- Tính: `est_sec = (n_train / 10000) × (n_trees / 500) × 35`.
- Format: `"Est. ~Xs (n_train ≈ Y,YYY)"`.
- Cho user biết Run sẽ tốn bao lâu trước khi nhấn.

### `actionButton("run_btn")` — Nút Run
- **Label dynamic** (qua `output$run_btn_ui`):
  - Nếu chưa có model: `"▶ Run Causal Forest"`.
  - Nếu đang có pre-trained: `"⟳ Re-train with custom settings"`.
  - Nếu dataset = upload: `"▶ Run Causal Forest on uploaded CSV"`.
- **Behavior khi nhấn:** xem mục B.5.

## B.3 Main panel — `output$mode_badge` (góc phải trên)

3 trạng thái:
- **`badge-pretrained` (xanh lá):** `"🔒 Pre-trained · N obs"` + subtitle `"Loaded from disk (.rds)"` + timestamp.
- **`badge-custom` (cam):** `"⚡ Custom run · N obs"` + `"Re-trained just now (trees=X)"` + actionLink `"Reset to pre-trained"`.
- **`badge-none` (xám):** `"No model loaded"` + hint (`"File missing: key.rds"` hoặc `"Select a dataset/outcome"`).

### `observeEvent(input$reset_to_pretrained)`
- Click link → `readRDS()` lại file pre-trained → khôi phục badge xanh.

## B.4 Reactive `pretrained_key()` + Auto-load

### `pretrained_key()` — Reactive
- Ghép key từ `input$dataset` + `input$hillstrom_group` + `input$outcome`.
- Ví dụ: `"hillstrom_men_visit"`, `"lenta_response"`, `"criteo_conversion"`.
- `req(...)` chặn nếu thiếu input.

### `observe({ ... readRDS ... })` — Auto-load pre-trained
- Mỗi lần `pretrained_key()` đổi → kiểm tra file `results/real/{key}.rds`.
- **Nếu tồn tại:**
  - `readRDS()` → set `results_rv(res)` (reactiveVal trung tâm).
  - `res$mode <- "pretrained"`.
  - Hiện notification `"Loaded pre-trained model"` + thời gian load (ms).
- **Nếu không:** `results_rv(NULL)` → badge "No model loaded".
- **Thời gian:** ~50ms cho file 5-10 MB.

## B.5 `observeEvent(input$run_btn)` — Custom Run (train live)

Khi nhấn nút Run, quy trình 3 step (mỗi step show notification):

**Step 1/3 — Load + Prep (~1s)**
- Đọc raw data: `readRDS("{dataset}_raw.rds")` (cho dataset có sẵn) hoặc `read.csv(input$csv_file$datapath)` (cho upload).
- Determine columns: `X_cols`, `W_col`, `Y_col` (theo dataset).
- Apply top-K filter nếu `input$use_topk == TRUE`.
- Subsample nếu non-Hillstrom: `df[sample(nrow(df), input$subsample_n), ]`.
- Coerce X → matrix double (label-encode factor/char).
- Train/test split 80/20 (`set.seed(42)`).

**Step 2/3 — Train CF (~10-60s tùy n × trees)**
- Gọi `grow_causal_forest(X_train, W_train, Y_train, num_trees, sample_fraction=0.5, seed=42)`.
- Bên trong (`methods.R`): `grf::causal_forest()` với honest splitting + 50/50 split.
- UI **bị block** trong lúc này (single-threaded R).
- Notification show estimated time + warning "UI is paused while R trains".

**Step 3/3 — Predict + Save (~2s)**
- `predict(cf, X_test, estimate.variance = TRUE)` → `tau_hat`, `variance.estimates`.
- Tính `tau_lower/upper = tau_hat ± 1.96 × √variance`.
- Nếu Y binary (chỉ chứa 0/1): clamp `tau_hat ∈ [-1, 1]`.
- `variable_importance(cf)` → vector tầm quan trọng.
- Set `results_rv(list(...))` với `mode = "custom"` → all tabs refresh.

## B.6 Tab "CATE Overview"

### `output$tab_cate_overview` — UI tổng
- 5 stat items (class `.stat-item`):
  - **Mean CATE:** `mean(tau_hat)`.
  - **SD:** `sd(tau_hat)`.
  - **% Positive:** `mean(tau > 0)`.
  - **% Negative:** `mean(tau < 0)`.
  - **Test obs:** `n_test`.
- `plotlyOutput("plot_cate_density")`: density plot.
- `desc-box`: outcome + unit note ("dollar" vs "probability points").

### `plotlyOutput("plot_cate_density")`
- `geom_density(fill="#2166ac")`.
- 3 vline:
  - Xám đứt tại x=0 (zero effect line).
  - Đỏ đứt tại `mean(tau)`.
  - Cam dotted tại `±threshold` (segment boundaries từ `seg_threshold()`).

## B.7 Tab "Targeting"

### `seg-bar` — 4 segment boxes
- Tính bởi `compute_segments(res, seg_high, seg_low)` (xem helper B.10):
  - **Persuadables (xanh lá):** `tau > seg_high`.
  - **Do Not Disturb (đỏ):** `tau < seg_low`.
  - **Sure Things (xanh dương):** trong neutral zone + baseline_treated > 0.5.
  - **Lost Causes (vàng):** trong neutral zone + baseline_treated ≤ 0.5.
- Mỗi box show count + % trên total n_test.

### `plotlyOutput("plot_uplift")` — Uplift / Qini curve
- Tính bởi `compute_uplift(res)`:
  1. Sort test obs giảm dần theo `tau_hat`.
  2. `cum_gain[i] = cumsum(Y_sorted) / total_Y` (% conversion thu được).
  3. `random[i] = i / n` (baseline ngẫu nhiên).
  4. `qini = mean(cum_gain - random)` (Qini coefficient).
- Thin xuống 300 điểm cho plotly mượt.
- **Title:** `"Uplift Curve | Qini = X.XXX"`.
- Diện tích trên random = uplift value của targeting bằng CF.
- Return `NULL` nếu Y không variation (toàn 0 hoặc toàn 1) → show empty plot.

### `plotlyOutput("plot_segments_bar")` — Bar chart segment count
- 4 cột ngang, màu khớp với seg-bar.
- X = count, hover tooltip show `Segment: N`.

### `tableOutput("recommendation_table")` — Bảng action
- 4 hàng × 4 cột: Segment, Action, Avg CATE, Size.
- Avg CATE = `mean(tau)` trong từng segment (NA nếu segment trống).
- Actions:
  - Persuadables → **TARGET**.
  - Do Not Disturb → **EXCLUDE**.
  - Sure Things → **OPTIONAL**.
  - Lost Causes → **DEPRIORITIZE**.

## B.8 Tab "Variable Importance"

### `desc-box` (phía trên)
- Auto-tính 3 con số:
  - Top-3 features (tên).
  - % heterogeneity giải thích bởi top-3.
  - Số K cần để đạt 80% cumulative importance.

### `plotlyOutput("plot_varimp")`
- `geom_col` horizontal, features sorted theo importance.
- Importance từ `grf::variable_importance(cf)` — weighted theo độ sâu split (split sớm = quan trọng hơn).
- Higher = feature đó ảnh hưởng nhiều đến **heterogeneity của τ**, không phải mean của Y.

## B.9 Tab "Results Table"

### `sliderInput("top_n")`
- Range: 10 → `min(500, n_test)`, default `min(100, n_test)`.
- Show top N test obs theo `|tau_hat|` giảm dần.

### `tableOutput("results_df_table")`
- Mỗi hàng: 1 test obs.
- Cột: `X_cols` (đặc trưng) + `W` + `Y_actual` + `tau_hat` + `CI_lower` + `CI_upper`.
- Sort theo `|tau_hat|` desc → top rows = extreme CATEs (Persuadables hoặc DND mạnh nhất).

## B.10 Helpers nội bộ

### `seg_threshold()` — Outcome-aware
- Nếu `input$outcome == "spend"`: `list(high=1.0, low=-1.0)` (dollar units).
- Else: `list(high=0.05, low=-0.05)` (probability points).
- Tác động: dùng cho `compute_segments` + vline plot density + `recommendation_table`.

### `compute_segments(res, seg_high, seg_low)`
- Return `list(persuadable, dnd, sure_thing, lost_cause, n, baseline)`.
- `baseline_treated = mean(Y[W==1])` — tỷ lệ conversion của nhóm treated.
- Split neutral zone thêm theo baseline > 0.5 để phân biệt Sure Things vs Lost Causes.

### `compute_uplift(res)`
- Return data.frame với cột `pct_targeted`, `cum_gain`, `random`, `qini`.
- Trả `NULL` nếu Y constant.

### `detect_columns(df)` — Cho upload
- `W_candidate`: cột nhị phân 0/1, không phải ID.
- `Y_candidate`: cột numeric matching regex outcome keywords.
- `X`: phần còn lại (loại ID-like).

### `coerce_X_matrix(df, X_cols)`
- Chuyển factor/character → `as.numeric(factor(...))`.
- `storage.mode <- "double"` để grf accept.

## B.11 Luồng dữ liệu App B (tóm tắt)

```
[Path A — Pre-trained auto-load]
input$dataset/group/outcome ─► pretrained_key() ─► readRDS({key}.rds)
                                                       │
                                                       ▼
                                              results_rv(res, mode="pretrained")

[Path B — Custom training]
input$run_btn ─► observeEvent:
                   1. Load raw data (or CSV)
                   2. Subsample + split
                   3. grow_causal_forest(...)
                   4. predict + variance
                                                       │
                                                       ▼
                                              results_rv(res, mode="custom")

results_rv ─► 4 tab outputs (CATE, Targeting, VarImp, Table) + mode_badge
```

---

# C. So sánh nhanh 2 app

| Aspect | App A (`app.R`) | App B (`app_real.R`) |
|---|---|---|
| **Data source** | 54 CSV pre-computed | 10 .rds pre-trained + raw .rds |
| **τ ground truth** | Có (sinh bởi `dgp.R`) | Không |
| **Metric chính** | MSE, Coverage | Mean CATE, Qini, Segments |
| **Train live?** | Không | Có (nút Run) |
| **Tab count** | 3 (Comparison / ITE / Table) | 4 (CATE / Targeting / VarImp / Table) |
| **Reactive load time** | <100ms | <50ms (RDS) / 10-60s (custom) |
| **Audience focus** | Academic validation | Business insight |

---

# D. Bảng tham chiếu nhanh khi gặp sự cố

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| Plot trống (App A) | Bỏ tick hết Methods | Tick lại ≥ 1 |
| "No model loaded" (App B) | File `.rds` thiếu | Đổi outcome/dataset khác |
| Error đỏ khi Run | Subsample quá nhỏ / W không binary / Y có NA | Tăng subsample, check W/Y |
| UI đứng 60s sau Run | Đang train CF | Đợi, không nhấn lại |
| Plotly trắng | Browser cache | F5 |
| `could not find function "causal_forest"` | Thiếu grf | `install.packages("grf")` |
| Port chiếm khi `runApp` | App khác đang chạy | Đổi port (4001→4003) |

---

# E. Tham chiếu nội bộ

| Cần biết gì | Đọc file |
|---|---|
| Công thức `gen_design1/2/3` | `r_repro/dgp.R` |
| Cách `grow_causal_forest` gọi grf | `r_repro/methods.R` |
| Cách tạo 54 CSV cho App A | `r_repro/run_experiment.R` |
| Cách download Hillstrom/Lenta/Criteo | `r_repro/prepare_real_data.R` |
| Cách train + save `.rds` cho App B | `r_repro/train_pretrained.R` |
| Lý thuyết Causal Forest + paper | `PRESENTATION_THEORY.md` |
