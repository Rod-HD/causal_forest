# Tasks — Simulation Reproduction

## Implementation Tasks

- [x] **Task 1**: Implement `dgp.R` — 3 data-generating processes
  - [x] 1.1: `beta24_pdf()` helper for Design 1 propensity
  - [x] 1.2: `gen_design1()` — Confounding design (τ=0, e(x)=Beta propensity)
  - [x] 1.3: `sigmoid20()` helper for Design 2
  - [x] 1.4: `gen_design2()` — Smooth heterogeneity (τ=σ₂₀×σ₂₀)
  - [x] 1.5: `sigmoid12()` helper for Design 3
  - [x] 1.6: `gen_design3()` — Sharp heterogeneity (τ=σ₁₂×σ₁₂)

- [x] **Task 2**: Implement `methods.R` — estimators & metrics
  - [x] 2.1: `grow_causal_forest()` — Procedure 1 (Double-Sample Trees, grf)
  - [x] 2.2: `grow_propensity_forest()` — Procedure 2 (Propensity Forest emulation)
  - [x] 2.3: `predict_cf()` — predict with IJ variance
  - [x] 2.4: `predict_knn()` — k-NN matching with Eq. 26 variance
  - [x] 2.5: `compute_metrics()` — MSE + 95% CI coverage

- [x] **Task 3**: Implement `00_setup.R` — package installation
  - [x] 3.1: Check and install `grf` from CRAN
  - [x] 3.2: Check and install `FNN` from CRAN
  - [x] 3.3: Verification output with OK/FAILED status

- [x] **Task 4**: Implement `run_experiment.R` — single cell runner
  - [x] 4.1: CLI argument parsing (--design, --method, --d)
  - [x] 4.2: Paper config lookup (CONFIGS list)
  - [x] 4.3: Seed scheme (42×10000+r for train, +10M for test)
  - [x] 4.4: Design-aware method dispatch (propensity vs double-sample)
  - [x] 4.5: Parallel execution for kNN (parLapply on Windows)
  - [x] 4.6: CSV output with progress reporting

- [x] **Task 5**: Implement `run_all.R` — orchestrator
  - [x] 5.1: Grid generation (54 cells)
  - [x] 5.2: Optional --design filter
  - [x] 5.3: Progress logging with ETA

- [x] **Task 6**: Implement `print_tables.R` — comparison output
  - [x] 6.1: Hard-coded paper values (from arXiv TeX source)
  - [x] 6.2: Load our results from CSV
  - [x] 6.3: Unicode box-drawing table format
  - [x] 6.4: Delta indicators (+, -, =) with thresholds
  - [x] 6.5: Dual output (terminal + file)

- [x] **Task 7**: Implement `plot_results.R` — figures
  - [x] 7.1: ITE distribution density plot (3 designs faceted)
  - [x] 7.2: Comparison chart (MSE + Coverage vs d, all methods)
  - [x] 7.3: PDF output

- [x] **Task 8**: Run all 54 simulation cells
  - [x] 8.1: Design 1 — 18 cells (cf + knn10 + knn100 × 6 d-values)
  - [x] 8.2: Design 2 — 18 cells (cf + knn7 + knn50 × 6 d-values)
  - [x] 8.3: Design 3 — 18 cells (cf + knn10 + knn100 × 6 d-values)

- [x] **Task 9**: Generate comparison outputs
  - [x] 9.1: `results/comparison_table.txt`
  - [x] 9.2: `results/fig_ite_distribution.pdf`
  - [x] 9.3: `results/fig_comparison.pdf`

- [x] **Task 10**: Write documentation
  - [x] 10.1: `docs/option_a_setup.md` — Option A (causalTree) setup guide
  - [x] 10.2: `docs/option_b_setup.md` — Option B (grf) setup guide
