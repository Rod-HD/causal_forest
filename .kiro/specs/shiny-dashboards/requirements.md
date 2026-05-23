# Requirements — Shiny Dashboards

## Overview

Hai Shiny app tương tác: `app.R` (viewer cho simulation results) và `app_real.R` (showcase real-data với dual mode pre-trained/custom).

## User Stories

### US-1: Simulation Dashboard (app.R)
**As a** presenter  
**I want to** xem kết quả simulation qua interactive dashboard  
**So that** tôi trình bày được kết quả paper reproduction dễ hiểu  

**Acceptance Criteria:**
- Sidebar: dropdown Design (1/2/3) + checkbox Methods (CF + 2 kNN)
- Tab "Comparison Chart": Plotly MSE vs d + Coverage vs d (with 0.95 reference line)
- Tab "ITE Distribution": radio buttons chọn d → gen_designX(4000, d) → density plot + stats (Mean/SD/Min/Max)
- Tab "Results Table": bảng mean ± SE cho tất cả (method, d) combinations
- **Viewer only** — không gọi grf runtime
- Design change → auto-reset Methods checkboxes (D2 dùng k khác D1/D3)

### US-2: Real-Data Dashboard (app_real.R)
**As a** presenter  
**I want to** demo CF trên real datasets với interactive dashboard  
**So that** tôi minh hoạ được ứng dụng thực tế  

**Acceptance Criteria:**
- **Dual mode**: auto-load pre-trained `.rds` (~50ms) + optional custom re-train
- **4 datasets**: Hillstrom (men/women groups), Lenta, Criteo, Upload CSV
- **4 tabs**: CATE Overview, Targeting, Variable Importance, Results Table
- **Mode badge**: xanh lá (pre-trained) / cam (custom) / xám (no model)
- **Segment analysis**: Persuadables / Do Not Disturb / Sure Things / Lost Causes
- **Uplift/Qini curve**: model vs random baseline
- **Top-K features toggle**: retrain with only top-K features by VI
- **CSV upload**: auto-detect W/Y/X columns + Quick Stats panel
- **ETA display**: estimated training time before Run
- **3-step notification**: Load → Train (UI paused) → Predict

### US-3: Documentation
**As a** presenter  
**I want to** tài liệu đầy đủ cho presentation  
**So that** tôi chuẩn bị thuyết trình hiệu quả  

**Acceptance Criteria:**
- `README.md` — tổng quan project, cài đặt, chạy thí nghiệm, kết quả
- `PRESENTATION_THEORY.md` — lý thuyết CF, potential outcomes, CATE, simulation designs
- `PRESENTATION_DEMO.md` — chức năng từng UI control của cả 2 app
- `USER_MANUAL.md` — hướng dẫn sử dụng app.R step-by-step + troubleshooting
