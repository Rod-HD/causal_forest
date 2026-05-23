# Requirements — Simulation Reproduction

## Overview

Tái lập Section 5/6 của Wager & Athey (2018) JASA — chạy 54 cells mô phỏng, đo MSE và Coverage, so sánh với bảng gốc trong paper.

## User Stories

### US-1: Package Setup
**As a** researcher  
**I want to** cài đặt tự động các R packages cần thiết (grf, FNN)  
**So that** tôi có thể chạy toàn bộ pipeline mà không cần cài tay  

**Acceptance Criteria:**
- `00_setup.R` kiểm tra và cài `grf` + `FNN` từ CRAN
- Hiển thị trạng thái OK/FAILED cho từng package
- Suggest lệnh test run sau khi cài xong

### US-2: Data Generating Processes
**As a** researcher  
**I want to** sinh dữ liệu mô phỏng theo đúng công thức trong paper  
**So that** kết quả tái lập có thể so sánh trực tiếp với paper  

**Acceptance Criteria:**
- Design 1: τ(x)=0, e(x)=0.25×(1+Beta(2,4).pdf(x₁)), m(x)=2x₁−1
- Design 2: τ(x)=σ₂₀(x₁)×σ₂₀(x₂), e(x)=0.5, m(x)=0
- Design 3: τ(x)=σ₁₂(x₁)×σ₁₂(x₂), e(x)=0.5, m(x)=0
- DGP: X~Uniform([0,1]^d), W~Bernoulli(e(X)), Y=m(X)+(W−0.5)×τ(X)+ε, ε~N(0,1)
- Seed scheme: 42×10000+r (train), 42×10000+r+10000000 (test)

### US-3: Estimator Methods
**As a** researcher  
**I want to** implement Causal Forest (2 procedures) + k-NN matching theo paper  
**So that** tôi có thể so sánh performance giữa CF và kNN baselines  

**Acceptance Criteria:**
- `grow_causal_forest()` — Procedure 1 (Double-Sample Trees) cho Design 2, 3
- `grow_propensity_forest()` — Procedure 2 (Propensity Forest) cho Design 1
- `predict_cf()` — trả về tau_hat + IJ variance
- `predict_knn()` — k-NN matching với variance theo Eq. 26
- `compute_metrics()` — MSE + 95% CI coverage

### US-4: Run Single Experiment
**As a** researcher  
**I want to** chạy 1 cell (design, method, d) với CLI  
**So that** tôi có thể debug hoặc chạy lại từng cell riêng lẻ  

**Acceptance Criteria:**
- `Rscript run_experiment.R --design N --method METHOD --d D`
- Output: `results/designN/r_METHOD_dD.csv` (columns: replication, mse, coverage)
- CF chạy sequential; kNN chạy parallel (parLapply trên Windows)
- In MSE mean ± MC-SE, Coverage mean ± MC-SE ra terminal

### US-5: Run All 54 Cells
**As a** researcher  
**I want to** chạy toàn bộ 54 cells tự động  
**So that** tôi có kết quả đầy đủ cho cả 3 designs  

**Acceptance Criteria:**
- `Rscript run_all.R` chạy 54 cells tuần tự
- `Rscript run_all.R --design N` chạy 18 cells của 1 design
- Progress log: [i/total] design=N method=M d=D + elapsed + ETA
- Tổng thời gian ~96 phút (16 cores)

### US-6: Compare with Paper
**As a** researcher  
**I want to** in bảng so sánh kết quả của tôi với paper  
**So that** tôi xác nhận được mức độ khớp  

**Acceptance Criteria:**
- `Rscript print_tables.R` in bảng Unicode box-drawing cho cả 3 designs
- Cột: Paper MSE, Ours MSE, Δ MSE, Paper Cov, Ours Cov, Δ Cov
- Indicators: + (cao hơn), - (thấp hơn), = (trong ngưỡng)
- Output cả terminal lẫn file `results/comparison_table.txt`

### US-7: Plot Results
**As a** researcher  
**I want to** vẽ figure ITE distribution và comparison chart  
**So that** tôi có hình minh hoạ cho báo cáo / thuyết trình  

**Acceptance Criteria:**
- `Rscript plot_results.R` tạo 2 PDF:
  - `fig_ite_distribution.pdf` — density τ(X) cho 3 designs
  - `fig_comparison.pdf` — MSE + Coverage vs d (all methods, faceted by design)
