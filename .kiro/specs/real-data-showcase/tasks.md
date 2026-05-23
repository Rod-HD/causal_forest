# Tasks — Real-Data Showcase

## Implementation Tasks

- [x] **Task 1**: Implement `prepare_real_data.R` — download & preprocess
  - [x] 1.1: `safe_download()` helper with error handling
  - [x] 1.2: `stratified_sample()` helper preserving W ratio
  - [x] 1.3: `prepare_hillstrom()` — download, encode categoricals, split men/women
  - [x] 1.4: `prepare_lenta()` — multi-mirror download, auto-detect columns, label-encode
  - [x] 1.5: `prepare_criteo()` — download gz, read 1M rows, use exposure as W
  - [x] 1.6: Idempotent checks (skip if exists)
  - [x] 1.7: Manual fallback instructions for failed downloads

- [x] **Task 2**: Implement `train_pretrained.R` — model training
  - [x] 2.1: `train_and_save()` core function (X matrix coercion, 80/20 split, CF train, predict, VI, save)
  - [x] 2.2: `train_hillstrom()` — 6 models (2 groups × 3 outcomes)
  - [x] 2.3: `train_lenta()` — 1 model (response)
  - [x] 2.4: `train_criteo()` — 2 models (visit, conversion)
  - [x] 2.5: CLI `--only` filter
  - [x] 2.6: Skip if already trained (force flag)
  - [x] 2.7: Binary outcome clamping

- [x] **Task 3**: Download real datasets
  - [x] 3.1: Hillstrom MineThatData → `hillstrom_raw.rds`
  - [x] 3.2: Lenta RetailHero → `lenta_raw.rds`
  - [x] 3.3: Criteo Uplift v2.1 → `criteo_raw.rds`

- [x] **Task 4**: Train all pre-trained models
  - [x] 4.1: hillstrom_men_visit, hillstrom_men_conversion, hillstrom_men_spend
  - [x] 4.2: hillstrom_women_visit, hillstrom_women_conversion, hillstrom_women_spend
  - [x] 4.3: lenta_response
  - [x] 4.4: criteo_visit, criteo_conversion
