# Tasks — Shiny Dashboards

## Implementation Tasks

### App A — `app.R` (Simulation Viewer)

- [x] **Task 1**: Build simulation dashboard UI
  - [x] 1.1: Sidebar — Design dropdown + description box
  - [x] 1.2: Sidebar — Methods checkbox group (auto-reset on design change)
  - [x] 1.3: Tab "Comparison Chart" — Plotly MSE + Coverage vs d
  - [x] 1.4: Tab "ITE Distribution" — d radio buttons + density plot + stat cards
  - [x] 1.5: Tab "Results Table" — mean ± SE table
  - [x] 1.6: CSS styling (card layout, stat items, description boxes)

- [x] **Task 2**: Implement simulation dashboard server
  - [x] 2.1: `data_all()` reactive — load 18 CSVs per design
  - [x] 2.2: `data_filtered()` reactive — filter by selected methods
  - [x] 2.3: `ite_tau()` reactive — gen_designX(4000, d) on-the-fly
  - [x] 2.4: `make_plot()` helper — ggplot → plotly with tooltips
  - [x] 2.5: Design change observer — reset checkboxes + d slider

### App B — `app_real.R` (Real Data Showcase)

- [x] **Task 3**: Build real-data dashboard UI
  - [x] 3.1: Dataset dropdown (hillstrom, lenta, criteo, upload)
  - [x] 3.2: Hillstrom group radio (conditional)
  - [x] 3.3: Outcome selector (dynamic per dataset)
  - [x] 3.4: CSV file upload + auto-detect column selectors
  - [x] 3.5: Custom Run card (subsample slider, trees slider, top-K toggle, ETA, Run button)
  - [x] 3.6: Mode badge (pretrained/custom/none) + reset link
  - [x] 3.7: 4 tabs: CATE Overview, Targeting, Variable Importance, Results Table
  - [x] 3.8: CSS styling (badges, segment colors, stat items)

- [x] **Task 4**: Implement real-data dashboard server
  - [x] 4.1: `pretrained_key()` reactive — construct .rds key from inputs
  - [x] 4.2: Auto-load observer — readRDS on key change + notification
  - [x] 4.3: `observeEvent(run_btn)` — 3-step custom training pipeline
  - [x] 4.4: Top-K feature filter (using VI from prior result)
  - [x] 4.5: `upload_preview()` reactive + `detect_columns()` helper
  - [x] 4.6: Tab 1 — CATE density + stats + segment boundaries
  - [x] 4.7: Tab 2 — Segment bars + uplift/Qini curve + segment bar chart + recommendation table
  - [x] 4.8: Tab 3 — Variable importance desc-box + horizontal bar chart
  - [x] 4.9: Tab 4 — Top-N by |τ̂| results table with slider
  - [x] 4.10: Outcome-aware segment thresholds (±0.05 binary, ±1.0 spend)
  - [x] 4.11: Reset-to-pretrained observer

### Documentation

- [x] **Task 5**: Write presentation & manual documents
  - [x] 5.1: `README.md` — project overview, setup, running, results
  - [x] 5.2: `PRESENTATION_THEORY.md` — CF theory, potential outcomes, 3 designs, real-data analysis
  - [x] 5.3: `PRESENTATION_DEMO.md` — UI control reference for both apps
  - [x] 5.4: `USER_MANUAL.md` — step-by-step usage guide + troubleshooting
