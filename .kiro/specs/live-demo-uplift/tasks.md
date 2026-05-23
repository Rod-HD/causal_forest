# Tasks — Live Demo Uplift App

## Implementation Tasks

### Phase 1: Foundation (setup + utilities)

- [x] **Task 1**: Update `00_setup.R` to install new dependencies
  - [x] 1.1: Add `ranger`, `DT`, `pROC`, `gridExtra` to required pkg list
  - [x] 1.2: Add `install.packages()` with check
  - [x] 1.3: Add verification output

- [x] **Task 2**: Create `metrics.R` — implement AUUC, Qini, AUC
  - [x] 2.1: `auuc(tau_hat, W, Y)` — Area Under Uplift Curve
  - [x] 2.2: `qini(tau_hat, W, Y)` — Qini coefficient (refactor from app_real.R)
  - [x] 2.3: `auc_score(prob, y)` — AUC for Standard Classifier
  - [x] 2.4: `uplift_curve_data(tau_hat, W, Y)` — returns df for plotting
  - [x] 2.5: `qini_curve_data(tau_hat, W, Y)` — returns df for plotting
  - [x] 2.6: Unit-test each function with toy data

### Phase 2: Learners

- [x] **Task 3**: Create `learners.R` — implement 6 learners
  - [x] 3.1: `fit_standard_clf()` + `predict_standard_clf()` (ranger)
  - [x] 3.2: `fit_s_learner()` + `predict_s_learner()` (ranger with W as feature)
  - [x] 3.3: `fit_t_learner()` + `predict_t_learner()` (2 separate ranger models)
  - [x] 3.4: `fit_x_learner()` + `predict_x_learner()` (T-Learner + cross-fit + propensity)
  - [x] 3.5: `fit_causal_tree()` + `predict_causal_tree()` (grf with num.trees=50)
  - [x] 3.6: `fit_causal_forest()` + `predict_causal_forest()` (reuse methods.R)
  - [x] 3.7: Wrapper `train_all_learners(X, W, Y, num_trees)` returning named list

### Phase 3: Core App

- [x] **Task 4**: Create `app_demo.R` skeleton — UI structure
  - [x] 4.1: fluidPage with CSS theme (reuse from app_real.R)
  - [x] 4.2: Sidebar layout (dataset card + training card + status card)
  - [x] 4.3: Main panel with 5 empty tab placeholders
  - [x] 4.4: Status badge in top-right

- [x] **Task 5**: Implement reactive data layer
  - [x] 5.1: `results_rv` reactiveVal with structured list
  - [x] 5.2: `selected_customer_rv` reactiveVal
  - [x] 5.3: `load_dataset(ds, outcome)` — load raw rds, return X/W/Y/X_cols
  - [x] 5.4: `prepare_train_test(X, W, Y, seed=42)` — 80/20 split
  - [x] 5.5: `observeEvent(input$train_btn)` — trigger full training pipeline

- [x] **Task 6**: Training pipeline (8-step progress notifications)
  - [x] 6.1: Step 1 — load + prep data
  - [x] 6.2: Steps 2–7 — train each learner with progress notification
  - [x] 6.3: Step 8 — compute AUUC/Qini/AUC for all
  - [x] 6.4: Total time tracking + notification
  - [x] 6.5: tryCatch for each learner; partial failures still allow other tabs to work

### Phase 4: Tabs

- [x] **Task 7**: Tab 1 — Dataset Overview
  - [x] 7.1: 5-bullet info card (Name, Size, Treatment, Outcome, Split)
  - [x] 7.2: Bar chart: W=0 vs W=1 counts
  - [x] 7.3: Density plot: Y by W (binary) or histogram (continuous)
  - [x] 7.4: Baselines section listing 6 learner names

- [x] **Task 8**: Tab 2 — Quantitative Comparison
  - [x] 8.1: DT/renderTable with 6 rows × 4 cols (Method, AUUC, Qini, AUC)
  - [x] 8.2: Bold Causal Forest row via CSS
  - [x] 8.3: Bar chart AUUC sorted desc, CF highlighted
  - [x] 8.4: "Save PNG" button → trigger plotly download

- [x] **Task 9**: Tab 3 — Uplift / Qini Curves
  - [x] 9.1: Checkbox group for method visibility (default all)
  - [x] 9.2: Plotly uplift curve, 6 lines + Random baseline (gray dashed)
  - [x] 9.3: "Key Observations" box with 3 auto-generated findings:
    - Highest AUUC method
    - Methods worse than random (if any)
    - "Sleeping dogs" count (customers with τ̂ < 0)
  - [x] 9.4: "Takeaway" box — 1-line conclusion

- [x] **Task 10**: Tab 4 — Customer Decision (3 sub-tabs + detail panel)
  - [x] 10.1: Sub-tab 4a — DT browseable table of X_test
  - [x] 10.2: Sub-tab 4b — random pick button + last-picked display
  - [x] 10.3: Sub-tab 4c — slider N + DT top-N by |τ̂|
  - [x] 10.4: Click row event handler → set `selected_customer_rv`
  - [x] 10.5: Detail panel:
    - Big τ̂ number with color
    - CI [lower, upper]
    - Decision badge (TREAT / DO NOT TREAT)
    - Threshold slider (range −0.2 to +0.2, default 0)
    - Decision rule explanation text
    - Feature values table
    - Mini bar chart: feature contribution (approximate via local importance)
    - Population comparison sentence

- [x] **Task 11**: Tab 5 — Upload CSV
  - [x] 11.1: File input ≤200MB
  - [x] 11.2: Auto-detect W, Y, X (reuse `detect_columns()` from app_real.R)
  - [x] 11.3: Override dropdowns for W, Y, X
  - [x] 11.4: "Train on uploaded CSV" button → reuse training pipeline
  - [x] 11.5: Validation: must have ≥1 binary W column, ≥1 numeric Y, ≥2 X columns

### Phase 5: Export & Polish

- [x] **Task 12**: Create `report_export.R`
  - [x] 12.1: `export_report(results_rv, selected_customer, out_path)`
  - [x] 12.2: gridExtra layout: table + bar + curve + customer (if any)
  - [x] 12.3: Save PNG to `cf_repro/results/demo_exports/report_<timestamp>.png`
  - [x] 12.4: Add "Export full report" button in sidebar
  - [x] 12.5: Notification with output path after save

- [x] **Task 13**: CSS theme + polish
  - [x] 13.1: Match style with `app_real.R` (card layout, badges)
  - [x] 13.2: Decision badge: huge green/red boxes
  - [x] 13.3: Loading spinners during training
  - [x] 13.4: Tooltip text on technical metrics (AUUC, Qini, CI)

### Phase 6: Testing & Verification

- [x] **Task 14**: Smoke test on each dataset
  - [x] 14.1: Train all 6 learners on Hillstrom × 3 outcomes — verify ≤30s
  - [x] 14.2: Train on Lenta — verify works (may be slower due to size)
  - [x] 14.3: Train on Criteo — verify works on default subsample
  - [x] 14.4: Upload sample CSV — verify auto-detect + train

- [x] **Task 15**: Customer decision flow E2E
  - [x] 15.1: Pick customer via Browse → verify detail panel populated
  - [x] 15.2: Random pick → verify changes detail panel
  - [x] 15.3: Adjust threshold slider → verify decision badge updates
  - [x] 15.4: Switch dataset → verify state clears properly

- [x] **Task 16**: PNG export verification
  - [x] 16.1: Export with no customer selected → 3-panel layout
  - [x] 16.2: Export with customer selected → 4-panel layout
  - [x] 16.3: Verify PNG opens in image viewer correctly

### Phase 7: Documentation

- [x] **Task 17**: Update USER_MANUAL.md with new app
  - [x] 17.1: Section "Live Demo App (app_demo.R)"
  - [x] 17.2: How to launch, what each tab does
  - [x] 17.3: Demo script suggestion (15-min flow)

- [x] **Task 18**: Update README.md
  - [x] 18.1: List 3 apps now (app.R, app_real.R, app_demo.R)
  - [x] 18.2: Brief diff between them

- [x] **Task 19**: Create `PRESENTATION_DEMO.md` section
  - [x] 19.1: Suggested talking points per tab
  - [x] 19.2: Pre-demo checklist (data files present, packages installed)
  - [x] 19.3: Common questions + answers (e.g., "Why is X-Learner better here?")

## Estimated effort

| Phase | Estimate |
|---|---|
| 1 — Foundation | 1–2h |
| 2 — Learners | 3–4h |
| 3 — Core App | 2h |
| 4 — Tabs (5) | 6–8h |
| 5 — Export & polish | 2h |
| 6 — Testing | 2h |
| 7 — Docs | 1h |
| **Total** | **17–21h** |

## Implementation order (recommended)

1. Phase 1 (deps + metrics) — foundational, can't proceed without
2. Phase 2 (learners) — biggest risk, test on toy data first
3. Phase 3 (app skeleton + training pipeline) — gets something running
4. Phase 4 in order: Tab 1 → 2 → 3 (these depend on training results) → 4 (most complex) → 5
5. Phase 5 (export) — needs all tabs to extract from
6. Phase 6 — verification before demo
7. Phase 7 — last, when stable

## Critical path for live demo (5-min talk)

**MUST HAVE** (demo dùng):
- Phase 1 (Foundation)
- Phase 2 (Learners) — full 6
- Phase 3 (Core App + training pipeline)
- Tab 1 (Dataset Overview) — 30s demo time
- Tab 2 (Comparison) — 60s demo time
- Tab 3 (Uplift Curves) — 60s demo time
- Tab 4 (Customer Decision) — 60s demo time, **highlight feature**
- **Pre-trained `.rds` cho Hillstrom × visit** — quan trọng để load instant trong demo

**SHOULD HAVE** (build nhưng không show trong 5 phút):
- Tab 5 (Upload CSV) — backup plan nếu lớp hỏi
- Threshold slider interactivity

**NICE TO HAVE** (cut nếu thiếu thời gian dev):
- Phase 5 PNG export (chuẩn bị screenshot trước cũng được)
- Feature contribution mini chart trong Detail panel (cắt được, thay bằng "Top 3 features")
- Sub-tab 4a Browse (đủ 4b Random + 4c Top-N là OK)

**Demo flow 5 phút (recommended):**
- 0:00–0:30 — Tab 1: giới thiệu dataset Hillstrom
- 0:30–1:30 — Tab 2: bảng + bar chart → "Causal Forest thắng"
- 1:30–2:30 — Tab 3: uplift curve → key findings
- 2:30–4:00 — Tab 4: 🎲 random pick customer → kéo threshold slider → cho lớp xem decision đổi
- 4:00–4:30 — Tab 4: chuyển sang Top N → "10 khách hàng đáng treat nhất"
- 4:30–5:00 — Kết luận

## New task added: pre-training for demo speed

- [x] **Task 20**: Pre-train Hillstrom × visit cho instant load
  - [x] 20.1: Script `pretrain_demo.R` — train all 6 learners on Hillstrom (visit, men group)
  - [x] 20.2: Save tới `results/demo_pretrained/hillstrom_visit_men.rds`
  - [x] 20.3: `app_demo.R` check file exists → load instant, không train lại
  - [x] 20.4: Lưu cả test set (X_test, W_test, Y_test) trong rds để Tab 4 dùng ngay
  - [x] 20.5: Re-train trigger chỉ khi user đổi outcome hoặc dataset hoặc upload CSV
