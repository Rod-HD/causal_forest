# Requirements — Real-Data Showcase

## Overview

Áp dụng Causal Forest lên 3 dataset marketing thực tế (Hillstrom, Lenta, Criteo) để minh hoạ khả năng ước lượng heterogeneous treatment effects trong bài toán thực.

## User Stories

### US-1: Download & Preprocess Real Datasets
**As a** researcher  
**I want to** tải và tiền xử lý 3 datasets thực từ nguồn công khai  
**So that** tôi có data sẵn sàng để train Causal Forest  

**Acceptance Criteria:**
- **Hillstrom**: Download CSV từ minethatdata.com → encode categorical → tách men/women groups → save `hillstrom_raw.rds`
- **Lenta**: Download từ sklift S3 / HuggingFace / CatBoost fallback → auto-detect W/Y columns → label-encode char columns → subsample 100K stratified → save `lenta_raw.rds`
- **Criteo**: Download v2.1 (~2.7 GB gz) → read first 1M rows → use `exposure` as W → subsample 100K → save `criteo_raw.rds`
- Fallback: nếu download fail, hướng dẫn manual download
- Idempotent: skip nếu file đã tồn tại

### US-2: Train Pre-trained Models
**As a** researcher  
**I want to** train CF trên tất cả dataset/outcome combinations và save artifacts  
**So that** Shiny app có thể load kết quả ngay lập tức  

**Acceptance Criteria:**
- `Rscript train_pretrained.R` train tất cả available datasets
- `--only hillstrom|lenta|criteo` filter theo dataset
- Output cho mỗi (dataset, outcome): `{key}.rds` (model results) + `{key}_cate.csv` (predictions)
- `.rds` chứa: tau_hat, tau_lower, tau_upper, X_test, W_test, Y_test, X_cols, var_importance, metadata
- 80/20 train-test split, seed=42
- Binary outcome: clamp tau_hat ∈ [-1, 1]
- Skip nếu đã train (force=TRUE để retrain)

### US-3: Hillstrom Analysis
**As a** researcher  
**I want to** phân tích hiệu ứng email marketing trên dataset Hillstrom  
**So that** tôi minh hoạ được customer segmentation (Persuadables/DND/Sure Things/Lost Causes)  

**Acceptance Criteria:**
- 2 treatment groups: Men's Email vs Control, Women's Email vs Control
- 3 outcomes: visit (binary), conversion (binary), spend (continuous)
- 6 model combinations total (2 groups × 3 outcomes)
- 7 features: recency, history, mens, womens, zip_code_enc, newbie, channel_enc

### US-4: Lenta Analysis
**As a** researcher  
**I want to** phân tích hiệu ứng SMS campaign trên dataset Lenta  
**So that** tôi thấy CF hoạt động trên dataset lớn (100K obs)  

**Acceptance Criteria:**
- 1 outcome: response (binary)
- Auto-detect W/Y columns, handle string encoding ("test"/"control" → 1/0)
- ~50 features (auto-selected: numeric, ≤10% NA, not ID-like)

### US-5: Criteo Analysis
**As a** researcher  
**I want to** phân tích ad exposure effect trên dataset Criteo  
**So that** tôi minh hoạ CF trên ad-tech scale data  

**Acceptance Criteria:**
- W = `exposure` (not `treatment` — CriteoV2.1 specificity)
- 2 outcomes: visit, conversion
- 12 anonymous features (f0–f11)
