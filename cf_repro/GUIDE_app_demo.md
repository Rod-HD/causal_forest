# Hướng dẫn sử dụng app_demo.R

## Cách khởi động

```r
Rscript -e "shiny::runApp('cf_repro/r_repro/app_demo.R', launch.browser=TRUE)"
```

Lần đầu mở app sẽ tự tải kết quả pre-trained của Hillstrom Men × Visit (nếu file `.rds` tồn tại trong `results/demo_pretrained/`). Nếu chưa có file pre-trained, chạy trước:

```r
Rscript cf_repro/r_repro/pretrain_demo.R
```

---

## Tổng quan giao diện

```
┌─────────────────────────────────────────────────────────────────┐
│  Tiêu đề + badge trạng thái model (góc phải)                   │
├───────────────┬─────────────────────────────────────────────────┤
│   SIDEBAR     │  TAB 1 | TAB 2 | TAB 3 | TAB 4 | TAB 5         │
│  (chọn data,  │  Dataset  Comparison  Curves  Decision  Upload  │
│   train,      │                                                 │
│   export)     │  Nội dung thay đổi tuỳ tab đang chọn           │
└───────────────┴─────────────────────────────────────────────────┘
```

---

## Sidebar — Thanh điều khiển bên trái

### Dataset
Dropdown chọn tập dữ liệu để chạy mô hình:

| Lựa chọn | Mô tả |
|---|---|
| **Hillstrom MineThatData** | 64K khách hàng, chiến dịch email marketing ngẫu nhiên (Men's / Women's / Control). Dữ liệu thực, feature dễ hiểu. |
| **Lenta RetailHero** | ~687K khách, chiến dịch SMS siêu thị Lenta (Nga). Lấy mẫu 100K để demo nhanh. |
| **Criteo Uplift v2.1** | 14M dòng, 12 feature ẩn danh. Lấy mẫu 100K. |
| **Simulation: Design 1/2/3** | Dữ liệu mô phỏng từ Wager & Athey (2018), có tau thật để kiểm tra độ chính xác. |
| **Upload your own CSV** | Tải lên file CSV của bạn. |

**Khi chọn Hillstrom**: xuất hiện thêm lựa chọn *Treatment group* — Men's Email hay Women's Email (so với nhóm Control).

**Khi chọn Simulation (Design 1/2/3)**: xuất hiện lựa chọn **Dimension d** — số chiều feature (từ 2 đến 8). Tăng d = thêm nhiều feature nhiễu không liên quan → mô hình khó hơn, hiệu năng thường giảm.

### Outcome
Chọn biến kết quả cần dự đoán tác động:
- **Visit** — khách có ghé trang web không? (0/1)
- **Conversion** — có mua hàng không? (0/1)
- **Spend** — chi tiêu bao nhiêu? (liên tục)

### Trees per learner (slider 200–1500)
Số cây quyết định trong mỗi mô hình rừng (Causal Forest, Causal Tree, S/T/X-Learner).

- **Ít cây (200–300)**: train nhanh hơn, kết quả kém ổn định hơn (variance cao), dùng để xem demo nhanh.
- **Nhiều cây (1000–1500)**: kết quả ổn định và chính xác hơn, nhưng mất nhiều thời gian hơn.
- **Mặc định 500**: cân bằng tốt cho demo.

Khi thay đổi số cây, cần bấm **Re-train** để áp dụng.

### Nút Re-train / ▶ Re-train with current settings
Bắt đầu huấn luyện lại toàn bộ 6 learner với cài đặt hiện tại. Trong lúc train, app hiện thông báo tiến trình. Sau khi xong, tất cả các tab cập nhật kết quả mới.

*Với dataset simulation (Design 1/2/3): không có nút này vì kết quả được pre-trained sẵn, tải ngay lập tức.*

### Learner status
Hiển thị trạng thái từng learner sau khi train:
- ✅ = train thành công
- ❌ = train thất bại (thường do dữ liệu không phù hợp)
- ⏳ = chưa train

### Export Report PNG
Xuất báo cáo tổng hợp (bảng metrics + biểu đồ AUUC + uplift curve + customer decision nếu đã chọn) ra file `.png` vào thư mục `results/demo_exports/`.

### Badge trạng thái (góc trên phải)
- 🔒 **Pre-trained** — dữ liệu đã được train trước và tải từ file `.rds`.
- ⚡ **Fresh train** — vừa train xong với cài đặt hiện tại.
- **No model loaded** — chưa có kết quả nào.

---

## Tab 1 — Dataset Overview

Tổng quan dữ liệu trước khi xem kết quả mô hình.

### Dataset Info
Thông tin cơ bản: tên dataset, kích thước (số mẫu × số feature), tỉ lệ treated/control, baseline rate của outcome, tỉ lệ train/test.

### Biểu đồ: Treatment vs Control Counts
Cột xanh (Control, W=0) và cột xanh lá (Treated, W=1). Hover để xem số lượng và phần trăm chính xác.

- **Đọc hiểu**: kiểm tra dữ liệu có cân bằng không. Nếu tỉ lệ treated quá thấp (< 5%) thì ước lượng uplift sẽ kém tin cậy.

### Biểu đồ: Outcome distribution by W
So sánh phân phối kết quả (Y) giữa nhóm Treated và Control.

- **Nếu Y nhị phân**: 2 cột bar, mỗi cột là tỉ lệ Y=1 (%). Nếu cột Treated cao hơn Control → treatment có tác động dương trung bình.
- **Nếu Y liên tục**: 2 đường density chồng lên nhau. Nếu phân phối hai nhóm khác nhau → treatment có tác động.

### Biểu đồ: True τ(x) distribution (chỉ với Simulation)
Hiện khi chọn Design 2 hoặc 3. Phân phối giá trị tau thật (τ_true) trên tập test — đây là "đáp án đúng" mà các mô hình cần ước lượng.

- Đường đứt đỏ = mean của τ_true.
- Đường đứt xám = τ = 0 (không có tác động).
- **Design 2/3**: phân phối có đuôi dài, nhiều khách có τ cao (treatment thực sự có tác dụng mạnh).
- **Design 1**: τ_true = 0 với mọi người, dùng để test xem mô hình có bị bias không.

---

## Tab 2 — Quantitative Comparison

So sánh định lượng hiệu năng của 6 learner.

### 6 Uplift Learner là gì?

| Learner | Ý tưởng cốt lõi |
|---|---|
| **Standard Classifier** | Dự đoán xác suất Y=1 trực tiếp, không phân biệt W. Baseline không phải uplift model. |
| **S-Learner** | Một mô hình duy nhất, W được đưa vào như một feature bình thường. τ̂ = f(X,W=1) − f(X,W=0). |
| **T-Learner** | Hai mô hình riêng biệt cho nhóm Treated và Control. τ̂ = μ₁(X) − μ₀(X). |
| **X-Learner** | Cải tiến của T-Learner: sử dụng counterfactual để "học chéo" giữa hai nhóm. Tốt hơn khi tỉ lệ treated/control lệch. |
| **Causal Tree (50)** | Một cây quyết định nhân quả với 50 lá. Dễ giải thích, ít ổn định hơn rừng. |
| **Causal Forest** | Ensemble nhiều Causal Tree, sử dụng honest splitting. Ước lượng không thiên lệch + có khoảng tin cậy. **Phương pháp chính của paper.** |

### Bảng kết quả (Performance comparison)

| Cột | Ý nghĩa | Đọc thế nào? |
|---|---|---|
| **AUUC ↑** | Area Under the Uplift Curve — tổng diện tích dưới đường uplift. Cao hơn = tốt hơn. | > 0 là tốt hơn random. Causal Forest thường dẫn đầu. |
| **Qini ↑** | Tương tự AUUC nhưng theo định nghĩa Qini (normalize theo số treated). | So sánh cùng scale với AUUC. |
| **AUC (Y)** | Chỉ áp dụng cho Standard Classifier — AUC dự đoán Y trực tiếp. Các uplift model không có cột này. | — nghĩa là N/A. |
| **Train** | Thời gian train (giây). | Causal Forest thường lâu nhất do cần fit nhiều cây honest. |
| **RMSE vs τ(x) ↓** | Chỉ xuất hiện với Simulation. Sai số RMSE so với tau thật. Thấp hơn = tốt hơn. | Design 1: RMSE gần 0 là tốt (vì tau thật = 0). |

Hàng Causal Forest được tô màu xanh đậm để dễ nhận ra.

### Biểu đồ: AUUC Comparison (bar chart ngang)
Mỗi thanh là một learner, sắp xếp theo AUUC tăng dần (learner tốt nhất ở trên cùng). Màu sắc cố định cho từng learner (xanh đậm = Causal Forest, vàng = S-Learner, v.v.).

- **Đọc hiểu**: learner ở trên cùng là lựa chọn tốt nhất để ưu tiên target. Nếu Causal Forest không dẫn đầu, các phương pháp đơn giản hơn vẫn cạnh tranh được trên dataset này.

---

## Tab 3 — Uplift / Qini Curves

Trực quan hoá toàn bộ chiến lược targeting theo thứ tự ưu tiên.

### Uplift Curve là gì?
Giả sử bạn có ngân sách để liên hệ N% khách hàng (theo thứ tự τ̂ giảm dần). Đường uplift cho biết nếu bạn chọn đúng N% đó, bạn "thu được" bao nhiêu uplift so với không làm gì.

- Trục X: % dân số được target (0% = không ai, 100% = tất cả).
- Trục Y: cumulative uplift gain tích luỹ.
- Đường đứt xám: baseline ngẫu nhiên (nếu chọn người ngẫu nhiên).
- **Đường tốt nằm trên đường xám càng nhiều càng tốt**, đặc biệt ở phần 10–30% đầu (vì thường ngân sách hạn chế).

### Qini Curve là gì?
Tương tự uplift curve nhưng trục Y dùng định nghĩa Qini (chia cho tổng số treated), cho phép so sánh giữa các dataset có tỉ lệ treated khác nhau. Diện tích dưới Qini curve = chỉ số Qini coefficient.

### Các điều khiển trong Tab 3

**Show methods (checkbox)**: ẩn/hiện từng learner. Bỏ tick các learner yếu để xem rõ hơn sự khác biệt giữa các learner tốt.

**Smooth lines**: làm mượt đường curve bằng LOESS (trung bình cục bộ). Hữu ích khi đường bị răng cưa nhiều (dữ liệu ít hoặc nhiều tie trong τ̂). Bật smooth giúp thấy xu hướng tổng thể rõ hơn.

**Zoom X range (% slider)**: thu hẹp vùng quan sát theo trục X.
- Ví dụ: kéo về 0–30% để xem chi tiết phần "budget nhỏ" — vùng này thực tế quan trọng nhất vì marketing thường không target 100% khách.
- Kéo toàn bộ 0–100% để xem toàn cảnh.

### Panel bên phải: Key Observations và Takeaway
Tự động tóm tắt:
- Learner có AUUC cao nhất và thấp nhất.
- **Sleeping dogs**: khách hàng có τ̂ < 0 (theo Causal Forest) — tức là treatment có thể gây hại cho họ. Đây là điểm quan trọng: model không chỉ tìm ai nên treat, mà còn tìm ai **không nên** treat.

---

## Tab 4 — Customer Decision

Ra quyết định TREAT / DO NOT TREAT cho từng khách hàng cụ thể dựa trên Causal Forest.

### Cách chọn khách hàng (panel trái)

**Tab Browse**: bảng toàn bộ khách hàng test. Bấm vào bất kỳ hàng nào để chọn. Cột `tau_hat` hiển thị τ̂ — xanh lá là dương, đỏ là âm.

**Tab Random**: bấm "Pick Random Customer" để chọn ngẫu nhiên một khách từ tập test. Dùng khi muốn demo nhanh hoặc kiểm tra các trường hợp đại diện.

**Tab Top N**: hiển thị N khách có |τ̂| lớn nhất (tức là mô hình tự tin nhất về tác động, dù dương hay âm). Slider điều chỉnh N từ 5 đến 500. Dùng khi muốn focus vào nhóm "easy wins" hoặc "sleeping dogs" rõ ràng nhất.

### Panel quyết định (bên phải)

**Decision Threshold (slider −0.2 đến 0.2)**
Ngưỡng τ̂ tối thiểu để khuyến nghị TREAT. Quy tắc: *TREAT nếu τ̂ > threshold VÀ CI_lower > 0*.

- Threshold = 0 (mặc định): treat bất kỳ ai có τ̂ dương và CI không chứa 0.
- Threshold = 0.05: chỉ treat những ai có ước lượng uplift rõ ràng > 5 điểm phần trăm.
- Tăng threshold → ít người được treat hơn nhưng chắc chắn hơn.
- Giảm threshold (âm) → treat cả người có τ̂ hơi âm (ít dùng trong thực tế).

**Ô hiển thị τ̂ và CI**
- **τ̂ = 0.0423** — ước lượng tác động nhân quả cá nhân. Đơn vị là đơn vị của Y (ví dụ: tăng 4.23 điểm phần trăm xác suất mua hàng nếu Y là conversion).
- **95% CI: [0.0011, 0.0835]** — khoảng tin cậy 95%. Nếu CI không chứa 0 (cả hai đầu cùng dấu) → kết luận có ý nghĩa thống kê.
- Màu xanh lá / đỏ của τ̂ cho biết dương / âm.

**Banner TREAT / DO NOT TREAT**
- Xanh lá **TREAT**: τ̂ > threshold VÀ CI_lower > 0. Nên gửi email/SMS cho khách này.
- Đỏ **DO NOT TREAT**: không đủ bằng chứng về tác động dương, hoặc tác động âm (sleeping dog).

**Bảng Feature values**: giá trị từng feature của khách hàng đang chọn.

**Feature contribution to τ̂ (biểu đồ bar ngang)**
Đóng góp xấp xỉ của từng feature vào τ̂ của khách này, tính theo: *(giá trị feature − trung bình dân số) × tầm quan trọng feature*.

- Thanh xanh lá: feature này đẩy τ̂ lên (khách có giá trị feature này cao hơn trung bình theo hướng tích cực).
- Thanh đỏ: feature này kéo τ̂ xuống.
- Feature nào có thanh dài nhất = ảnh hưởng nhiều nhất đến quyết định của mô hình với khách này.
- *Lưu ý: đây là xấp xỉ tuyến tính, không phải SHAP chính xác.*

**Population comparison + biểu đồ vị trí**
- Cho biết τ̂ của khách này thuộc phần trăm thứ bao nhiêu trong tổng tập test.
- Đường đỏ trên biểu đồ density = vị trí của khách đang xem. Đường đứt xám = τ = 0.
- Ví dụ: "τ̂ = 0.042 cao hơn 78.3% dân số" → khách này thuộc nhóm top 22% về tác động điều trị.

---

## Tab 5 — Upload CSV

Hướng dẫn tải lên dữ liệu của riêng bạn:

1. Chọn "Upload your own CSV" trong dropdown Dataset ở sidebar.
2. Tải file CSV (tối đa 200 MB). App đọc 2,000 dòng đầu để phát hiện cột tự động.
3. Kiểm tra / chỉnh lại các cột được detect:
   - **W (Treatment)**: cột nhị phân 0/1 chỉ nhóm treated vs control.
   - **Y (Outcome)**: cột kết quả cần đo tác động (nhị phân hoặc liên tục).
   - **X (Features)**: các cột feature dùng để dự đoán (chọn nhiều).
4. Bấm **Re-train** — 6 learner train trên dữ liệu của bạn (80/20 split, seed=42).
5. Sau khi xong, tất cả tab hoạt động bình thường với dữ liệu của bạn.

**Yêu cầu**: W phải là 0/1, Y có thể nhị phân hoặc liên tục, cần ít nhất 2 cột X.

---

## Câu hỏi thường gặp

**Q: τ̂ và τ(x) khác nhau thế nào?**
τ(x) là tác động nhân quả thật (chỉ có trong dữ liệu mô phỏng). τ̂ là ước lượng của mô hình. Trong tab Simulation, bảng kết quả có thêm cột RMSE đo độ lệch giữa hai giá trị này.

**Q: Tại sao khoảng tin cậy (CI) lại quan trọng?**
Nếu τ̂ = 0.02 nhưng CI = [−0.05, 0.09], nghĩa là tác động có thể âm — không nên treat. Causal Forest là phương pháp duy nhất trong app cung cấp CI có lý thuyết đảm bảo (honest inference).

**Q: Thay đổi số cây ảnh hưởng thế nào?**
Ít cây hơn → τ̂ dao động nhiều giữa các lần train (high variance), CI rộng hơn. Nhiều cây hơn → ổn định hơn, CI hẹp hơn, nhưng tốn nhiều RAM và thời gian hơn.

**Q: AUUC âm nghĩa là gì?**
Learner đó tệ hơn random targeting — nó đang target sai người. Trong thực tế, nếu AUUC âm thì nên dùng ngẫu nhiên còn hơn dùng model đó.

**Q: "Sleeping dogs" là gì?**
Thuật ngữ trong uplift modeling chỉ nhóm khách có τ̂ < 0 — tức là treatment thực sự làm giảm xác suất kết quả tốt với họ (ví dụ: gửi email khiến họ unsubscribe). Causal Forest phát hiện được nhóm này; các model đơn giản hơn thường bỏ sót.
