# Product — Causal Forest Reproduction & Real-Data Showcase

## Purpose

Tái lập (reproduce) toàn bộ kết quả mô phỏng Section 5/6 trong bài báo:

> Wager, S. & Athey, S. (2018). *Estimation and Inference of Heterogeneous Treatment Effects using Random Forests.* JASA, 113(523), 1228–1242.

Đồng thời mở rộng sang 3 dataset marketing thực (Hillstrom, Lenta, Criteo) để minh hoạ ứng dụng thực tế của Causal Forest trong bài toán Heterogeneous Treatment Effect (HTE).

## Target Audience

- Sinh viên, giảng viên môn CS114 — Máy học
- Người muốn hiểu Causal Forest / grf package qua ví dụ thực hành

## Core Objectives

1. **Simulation Reproduction** — Chạy 54 cells (3 designs × 3 methods × 6 giá trị d), đo MSE và Coverage, so sánh với bảng gốc trong paper.
2. **Real-Data Application** — Train Causal Forest trên 3 dataset thực (Hillstrom, Lenta, Criteo), phân tích CATE, customer segmentation (Persuadables / Do Not Disturb / Sure Things / Lost Causes), và Uplift/Qini curve.
3. **Interactive Dashboards** — Hai Shiny app:
   - `app.R` — xem kết quả simulation (viewer, không train lại).
   - `app_real.R` — xem kết quả real-data (auto-load pre-trained + optional custom re-train).
4. **Documentation** — Tài liệu lý thuyết, hướng dẫn demo, user manual đầy đủ cho thuyết trình.

## Key Outcomes

- kNN khớp hoàn hảo với paper; CF coverage cao hơn 2–5% (do grf IJ variance bảo thủ hơn causalTree gốc — documented, not a bug).
- 54/54 simulation cells hoàn thành.
- 3 real datasets đã được download, preprocess, và pre-train xong.
