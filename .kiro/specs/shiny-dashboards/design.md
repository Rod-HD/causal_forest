# Design — Shiny Dashboards

## Architecture

### App A — `app.R` (Simulation Viewer)

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

**Data Flow:**
```
input$design ───┬──► data_all() ──► 18 CSV → mean+SE
                │
                ├──► data_filtered() (lọc theo Methods) ──► plot_mse, plot_coverage, results_table
                │
                └──► ite_tau() ──► gen_designX(4000, d) ──► plot_ite + ite_stats

input$methods ─► data_filtered()
input$d_ite   ─► ite_tau()
```

**Key rule:** App A KHÔNG gọi `grf::causal_forest()` runtime. Mọi MSE/Coverage đến từ CSV. Mọi τ đến từ công thức dgp.R.

### App B — `app_real.R` (Real Data Showcase)

```
┌──────────────────────────────────────────────────────────────────┐
│ Causal Forest — Real Data Showcase    [mode_badge top-right]    │
├─────────────────┬────────────────────────────────────────────────┤
│ [Sidebar]       │ [CATE Overview | Targeting | VarImp | Table]  │
│ Dataset ▼       │                                                │
│ (group radio)   │                                                │
│ Outcome ▼       │                                                │
│ [Custom Run]    │                                                │
└─────────────────┴────────────────────────────────────────────────┘
```

**Dual-mode data flow:**
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

### CSS Design System

Both apps share a consistent visual style:
- Background: `#f5f6fa`
- Card: white, 8px radius, subtle shadow
- Primary accent: `#2166ac` (blue)
- Secondary: `#2c3e50` (dark)
- Stat cards: `.stat-item` with flex layout
- Description boxes: left-bordered `#2166ac`
- Segment colors: green (persuadable), red (DND), teal (sure thing), yellow (lost cause)

### Color Palette for Plots

| Method | Color | Shape |
|--------|-------|-------|
| Causal Forest | `#2166ac` | circle (16) |
| 7-NN / 10-NN | `#d6604d` | triangle (17) |
| 50-NN | `#f4a582` | square (15) |
| 100-NN | `#b2182b` | square (15) |
