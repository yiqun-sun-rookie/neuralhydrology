# 文献查新报告 A:DL洪水预报 × 数据同化 × OOD极端事件

**调研日期**: 2026-07-19
**对应候选 idea**: 铁岭三河(柴河/清河/凡河)洪水复盘 + 数据同化失效边界(拟立项 ID 08)
**调研方式**: 后台 agent 约 30 轮 WebSearch/WebFetch 对抗性检索(目标是找到撞车论文而非确认新颖)
**核心结论**: C1 部分做过(仅可作动机);**C2"同化抢救 OOD 极端洪水 + 失效边界"大概率空白(置信度 75-80%)**;C3 已饱和(降级为稳健性实验)
**投稿前必查**: 人工精读 Nearing 2022 TN 与 h-Diffusion 全文;CNKI 补查「实时校正+LSTM+入库」硕博论文

---

**检索方式说明**:通过 WebSearch + WebFetch 完成约 30 轮检索,覆盖 HESS/WRR/JoH/GMD/Nature/AGU Advances/arXiv/EGUsphere/ESSOAr,以及可检索到的中文期刊(水利学报、水科学进展、湖泊科学、气象、中国防汛抗旱等)网络索引。多数出版商全文页(Copernicus/Elsevier/Wiley/ASCE/IWA/ResearchGate/CNKI)对本环境返回 403,因此**大部分结论基于摘要与检索摘录核实,少数为推断**,下文逐条标注。**未发现直接撞车 C2 核心主张的论文**,但存在多篇高威胁近邻工作。

---

## 1. 最近邻工作表(按威胁度排序)

| # | Citation | Venue/年 | 做了什么 | 与C1/C2/C3重叠 | 关键差异 |
|---|---|---|---|---|---|
| 1 | Yang W., Ji H., Lonzarich L., Song Y., Shen C. "Diffusion-Based Probabilistic Modeling for Hourly Streamflow Prediction and Assimilation" | arXiv:2510.08488, 2025 (Shen组,已验证摘要) | 扩散模型逐小时径流预报;用 diffusion inpainting **免训练同化近期实测流量**;CAMELS-hourly 上击败 MTS-LSTM,**极端指标更优** | **C2 高**(DL+同化+极端指标+小时尺度) | 随机划分测试集、非 OOD 设计;无"同化失效边界"分析;非真实破纪录事件复盘;非水库入流 |
| 2 | Nearing G.S., Klotz D., Frame J.M., et al. "Technical note: Data assimilation and autoregression for using near-real-time streamflow observations in LSTM networks" | HESS 26:5493, 2022 (已验证摘要) | LSTM 中变分DA vs 自回归(AR)摄入实时流量;AR 更准更省算力;讨论缺测敏感性 | **C2 方法学基石** | CAMELS 常规期评估;未针对超训练分布极端洪水;无洪水量级分辨的失效分析;无入流变量 |
| 3 | Gegenleithner S., Pirker M., Dorfmann C., Kern R., Schneider J. "LSTM networks for enhancing real-time flood forecasts: a case study for an underperforming hydrologic model" | HESS 29:1939, 2025 (已验证摘要+作者) | LSTM 作后处理器校正物理模型实时预报,与 ARIMA 对比,**按预见期分辨、聚焦洪水事件**(ARIMA KGE 0.98→0.60 随预见期衰减) | **C2 中高**(实时校正+预见期分辨+洪水事件) | 被校正对象是过程模型而非 DL;非 OOD 破纪录事件;无失效边界概念;单流域(奥地利) |
| 4 | Guan X., Shan B., Nguyen V.D., Merz B. "Beyond Observed Extremes: Can Hybrid Deep Learning Models Improve Flood Prediction?" | EGUsphere preprint 2025-1509(检索时仍为预印本,已验证摘要) | 中欧 400+ 流域,3个水文模型+LSTM+3个混合模型模拟极端洪水;**对 unprecedented floods 洪峰平均低估>50%** | **C1 高**(量化 DL 对未见量级洪水的低估) | 大样本统计视角,非具体 2024-25 灾害事件复盘;无 DA/实时校正"抢救"环节;无预见期分析 |
| 5 | Baste S., Klotz D., Acuña Espinoza E., Bárdossy A., Loritz R. "Unveiling the limits of deep learning models in hydrological extrapolation tasks" | HESS 29:5871, 2025 (已验证摘要) | 瑞士 196 流域,合成设计暴雨递增强度打靶;发现 LSTM 存在**输出天花板(73 mm/d,低于训练最大值183 mm/d)** | **C1 高**(OOD 外推失效机制) | 合成事件而非真实破纪录洪水;无 DA;无预见期/入流维度 |
| 6 | Frame J.M., Kratzert F., Klotz D., et al. "Deep learning rainfall–runoff predictions of extreme events" | HESS 26:3377, 2022 (已验证摘要) | 只用<5年一遇年份训练,测极端事件;LSTM 外推优于 SAC-SMA 等 | **C1 锚点** | CAMELS 统计设计;结论偏乐观;无 DA、无事件复盘、无中国小流域 |
| 7 | (作者待核) "When are AI models ready for deployment? Reassessing Google's global AI flood forecasting system through the lens of responsible modelling" | Journal of Hydrology X, 2026 (已验证摘要;作者[unverified]) | 用观测基准重评 Google 模型:5年一遇洪水中位 F1 从~0.42 跌至<0.20,**极端事件漏报率>90%** | **C1 中高**(全球 DL 模型在极端下的失效证据) | 全球统计重评,非事件级 OOD 复盘;无 DA 抢救;无失效边界随预见期分析 |
| 8 | Jamaat A., Song Y., Rahmani F., Liu J., Lawson K., Shen C. "Update hydrological states or meteorological forcings? Comparing data assimilation methods for differentiable hydrologic models" | arXiv:2502.16444, 2025 (已验证摘要) | 可微分水文模型的变分DA(改状态 vs 改降雨 vs 都改),与 LSTM-DA 等效增益;state adjuster 对高流量更有效 | **C2 中**(DA 方案系统比较) | CAMELS 常规评估;非 OOD 极端;无失效边界;无入流 |
| 9 | (作者待核) "Enhancing physically-based flood forecasts through fusion of LSTM with unscented Kalman filter" (LSTM-UKF) | Journal of Hydrology 641, 2024 (已验证摘要;卷期号两处摘录不一致[131809/131819]) | LSTM 学习 Kalman 增益自适应更新物理模型状态;NSE 最高+9.1%,**长预见期与高流量改善显著** | **C2 中** | 更新对象是物理模型;未做超训练分布事件检验;非中国破纪录事件;非入流 |
| 10 | (作者待核) "Improving the Accuracy of Flood Forecasting Based on Deep Learning Models and Error Correction Methods: Dapoling Watershed, Huaihe" | J. Hydrologic Engineering 31(1), 2026 (已验证摘要) | 淮河大坡岭:LSTM+贝叶斯优化+4种误差校正法,多步预报,1-7h 预见期,NSE 0.87→0.91 | **C2 中**(中国流域 DL+误差校正+预见期) | 常规洪水样本;无 OOD/破纪录设定;无失效边界;短预见期;非水库入流 |
| 11 | Guo W.-D., Chen W.-B., Chang C.-H. "Prediction of hourly inflow for reservoirs at mountain catchments using residual error data and multiple-ahead correction technique" | Hydrology Research 54(9):1072, 2023 (已验证题录) | 台湾山区水库,ED-GRU/ED-LSTM/CNN-LSTM 入库流量 1-24h 预报+残差校正 | **C2+C4 中**(山区水库入流+多步校正) | 台风事件属训练分布内;无 OOD 框架;无"校正何时失效"分析 |
| 12 | Zhu Q., et al. "Deep Transfer Learning Based on LSTM Model for Reservoir Flood Forecasting" | Int. J. Data Warehousing & Mining 20(1), 2024 (已验证摘要) | 相似水库预训练+微调,随机森林特征+**自回归智能校正**预报结果 | **C2+C3+C4 组合表面重叠** | 数据挖掘期刊,水文深度浅;无极端 OOD、无失效边界、无事件复盘;这是"要素撞车、问题不撞车"的典型 |
| 13 | Tran V.N., et al. "AI Improves the Accuracy, Reliability, and Economic Value of Continental-Scale Flood Predictions" | AGU Advances, 2025, 2025AV001678 (已验证摘要) | attention-LSTM 误差模型(Errorcastnet)校正 NWM,洪水精度提升4-6倍 | **C2 中低**(大尺度误差校正) | 校正物理模型;统计评估,非 OOD 事件;美国 |
| 14 | Nearing G., et al. "Global prediction of extreme floods in ungauged watersheds" | Nature 627, 2024 (已验证) + "Google Global Flood Forecasting Model Version 2" (EGUsphere 2026-2283, ME-LSTM, 预见期+6天) | 全球 LSTM 极端洪水预报及其升级版 | **C1/C3 背景性重叠** | 全球 5-10 年一遇尺度;非破纪录单事件深钻;v2 无失效边界分析 |
| 15 | Acuña Espinoza E., Loritz R., Kratzert F., Klotz D., Gauch M., Álvarez Chaves M., Ehret U. "Analyzing the generalization capabilities of (a) hybrid hydrological model(s) for extrapolation to extreme events" | HESS 29:1277, 2025 (已验证题录) | 混合模型 vs LSTM 极端外推能力分析 | **C1 中** | 同 4/5,统计设计,无 DA/事件/入流 |
| 16 | Ougahi J.H., Rowan J.S. "Investigating Deep Learning Knowledge Transfer in Streamflow Prediction From Global to Local Catchment" | WRR 62, 2026, e2025WR041194 (已验证题录) | 全球→局地 LSTM 迁移微调改善数据稀缺区预报 | **C3 高** | 非相邻小流域间迁移;未在破纪录极端事件上检验迁移效果 |
| 17 | Zhang/CAS 团队 "Deep learning for cross-region streamflow and flood forecasting at a global scale" (ED-DLSTM) | The Innovation 5:100617, 2024 (已验证题录) | 全球 2k+ 站点跨区域/无资料区洪水预报 | **C3 中** | 大尺度跨区域,非相邻流域+极端事件设定 |
| 18 | Komiya (et al.) "Informed Neural Networks for Flood Forecasting With Limited Amount of Training Data" | WRR, 2025, 2023WR036380 (已验证摘录) | 日本大淀川,小样本+物理信息 NN,检验 unprecedented-scale 洪水 | **C1 中** | 单流域方法论文;无 DA、无失效边界 |
| 19 | (作者待核) "Towards a robust hydrologic data assimilation system for hurricane-induced river flow forecasting" | HESS 29:2407, 2025 (已验证摘要) | HEAVEN 框架同化 USGS 流量,飓风极端洪水预报 | **C2 概念近邻**(DA+极端事件) | 被同化的是概念性模型而非 DL;美国飓风场景 |
| 20 | 中文实时校正传统+近作:如 河海大学 DSI 自适应动力系统反演(2025 新闻稿);"Advancing real-time error correction of flood forecasting based on hydrologic similarity + ML" (Environmental Research, 2024);LSTM-UKF/EnKF-BiLSTM 类;欧阳文宇、张弛(?) 《人工智能驱动水文预报与水库调度研究的探索与思考》水利学报 56(9), 2025 [作者单位:大连理工,细节unverified] | 多篇 | 中国"实时校正"成熟传统 + AI 化 | **C2 在中文语境的背景** | 均未见"DL 预报 OOD 破纪录洪水 + 同化抢救 + 失效边界"的组合 |

---

## 2. 分 Claim 判定

### C1(量化 DL 模型对 2024-25 破纪录洪水的 OOD 退化)— **部分做过** | 置信度:高(≈85%)
- **已被做过的部分**:「LSTM 对超训练分布洪水系统性低估」这一命题在 2022-2026 已被反复量化(Frame 2022;Baste 2025 的输出天花板;Guan 2025 的 >50% 洪峰低估;JoH X 2026 对 Google 系统极端漏报率>90% 的重评)。**如果 C1 单独成文,审稿人会认为结论已知**。
- **仍属空白的部分**:①以**真实的、有灾害后果的 2024-25 中国破纪录事件**(而非合成暴雨或大样本统计)做事件级 forensic 复盘;②小型山区流域+水库入流变量;③辽河支流(柴河/清河/凡河)区域完全无 DL 文献(已检索中英文,铁岭地区仅有新闻和气象成因分析,无 DL 水文论文)。
- 判定:**C1 只能作为铺垫章节,不能作为卖点**。

### C2(核心:DA/AR 校正如何"抢救"OOD 极端洪水预报 + 失效边界)— **大概率空白** | 置信度:中高(≈75-80%)
- 逐项对照:**(a)** DL 模型+实时流量同化——已做(Nearing 2022;Feng 2020;h-Diffusion 2025);**(b)** 校正效果按预见期分辨——已做(Gegenleithner 2025;Dapoling 2026,但对象非 OOD);**(c)** 同化+极端指标——h-Diffusion 沾边;**(d)** **专门在超训练分布的真实破纪录洪水上检验同化的抢救能力,并给出"洪水量级×预见期"二维失效边界(DA 何时不再有效)——未检索到任何论文**。多轮不同措辞的对抗性检索("assimilation + out-of-distribution + flood"、"correction beyond training range"、"洪峰误差 预见期 失效"等)均无命中。
- **残余风险**:①Copernicus/Elsevier 全文 403,无法排除某篇论文在正文(而非标题/摘要)里做了量级分层的同化效果分析——最可疑的是 Nearing 2022 TN 和 h-Diffusion 的正文,建议投稿前人工精读这两篇;②h-Diffusion(Shen 组)与 Google v2 团队都在快速迭代,该组合随时可能被做掉;③中文"实时校正"文献体量巨大且 CNKI 无法直接检索,不排除有硕博论文做过类似事情(但期刊论文层面未见)。
- 判定:**"失效边界 + 有效预见期延长 + OOD 事件 + 入库流量"的组合是可辩护的新颖性**,其中"失效边界"(failure boundary)是最强的概念增量——现有文献只报告"同化平均改善多少",没有人回答"到什么量级/预见期它救不回来"。

### C3(相邻流域间迁移 + 极端事件检验)— **已被大量做过(作为独立卖点不成立)** | 置信度:高(≈90%)
- Transfer learning/regionalization 文献饱和(Ougahi 2026 WRR;Gao 2026 WRR;ED-DLSTM 2024;IJDWM 2024;湖泊科学 2025《区域化LSTM洪水预报模型研究》;Kratzert 2024 HESS Opinions 甚至已把"多流域训练"定为默认实践)。
- 未见"相邻小流域互迁+各自破纪录事件检验"的精确设定,但这只是既有范式的一个小切片。**C3 只能作为实验设计的一部分(证明结论稳健/回应'单流域训练'质疑),不能作为独立贡献声明**。

---

## 3. 最大威胁论文 Top 3

1. **Yang, Ji, Lonzarich, Song & Shen (2025), arXiv:2510.08488(h-Diffusion)** — 唯一同时具备"DL 预报+免训练同化+极端指标更优+小时尺度"的工作,且出自高产的 Shen 组,大概率正在投 WRR。**它没做的**:OOD 实验设计、真实破纪录事件、失效边界、入库流量。你们的论文必须引用并明确区隔;若其期刊版加入 OOD 分析,C2 将被严重削弱——建议尽快锁定投稿。
2. **Nearing et al. (2022), HESS 26:5493** — 审稿人必然拿它问"你们比 TN 多做了什么"。答案要预先写死:TN 回答"怎么同化",你们回答"同化在分布外何时失效"——问题不同,且变量(入流)、场景(破纪录事件复盘)、产出(失效边界/有效预见期)都不同。
3. **Guan et al. (2025), EGUsphere-2025-1509 + Baste et al. (2025), HESS 29:5871(并列)** — 这两篇几乎把 C1 的"OOD 低估"结论说完了(>50% 低估、输出天花板)。若你们把 C1 写成主贡献会直接撞墙;但反过来,它们为 C2 提供了完美的动机引文:"既然 DL 必然低估未见量级洪水,实时同化是否是运行期的救生索、能救到什么程度?"

*(次级威胁:Gegenleithner 2025 HESS——预见期分辨的实时校正框架与你们的分析框架最像,务必引用并强调其对象是欠佳物理模型、非 OOD 场景。)*

---

## 4. 定位建议(Repositioning)

1. **把 C2 的"失效边界"提为标题级卖点**。建议论文的核心图就是"洪水量级(相对训练期最大值的倍数/重现期)× 预见期"平面上的 DA 增益等值线+失效边界线。这是全部检索中没有任何论文给出的产出物。标题方向示例:"When does real-time discharge assimilation stop rescuing deep learning flood forecasts? Evidence from record-breaking floods…"
2. **C1 降级为动机+基线**,并显式对标 Guan/Baste/Frame:不要声称"首次量化 OOD 退化",而声称"首次在真实致灾破纪录事件的事件级复盘中,把 OOD 退化与可抢救性(recoverability)联合量化"。
3. **强化入库流量这条差异线**:反推入流噪声大、且是防洪调度的实际决策变量——检索确认"DL+DA+OOD 极端+入流"四要素组合无人做过(Guo 2023 与 IJDWM 2024 只占其中两要素)。建议增加一个"入流反推噪声对 AR 同化的影响"小节,这同时是方法贡献(AR 对噪声观测的鲁棒性——Nearing TN 只讨论了缺测)。
4. **C3 改写为稳健性实验**:framing 从"贡献3:跨流域迁移"改为"用相邻流域互迁证明失效边界的可移植性/回应单流域训练质疑(引 Kratzert 2024 HESS Opinions)"。
5. **时效风险提示**:2026年7月(本月)辽宁铁岭柴河/清河正在发生超警-超保洪水,且 h-Diffusion、Google v2 都在推进。这个题目的窗口期估计 12-18 个月,建议以 letter/短文形式尽快占位,或先挂 EGUsphere/ESSOAr 预印本。
6. **审稿人风险**:大概率会被派给 Nearing/Klotz/Frame 圈子或 Shen 圈子的人,引言里必须诚实覆盖第 1 节表格前 10 行,尤其不能漏 h-Diffusion 和 Gegenleithner。

---

## 5. 完整引文列表

**核实程度标注**:[V]=已通过摘要/官方页面核实题录;[S]=仅通过检索摘录核实(题录可信,细节未读全文);[U]=存在未核实要素。

**Thread 1 — DL 极端外推/OOD**
1. [V] Frame J.M., Kratzert F., Klotz D., Gauch M., Shalev G., Gilon O., Qualls L.M., Gupta H.V., Nearing G.S. Deep learning rainfall–runoff predictions of extreme events. *HESS* 26, 3377–3392, 2022.
2. [V] Nearing G., et al. Global prediction of extreme floods in ungauged watersheds. *Nature* 627, 559–563, 2024.
3. [V] Baste S., Klotz D., Acuña Espinoza E., Bárdossy A., Loritz R. Unveiling the limits of deep learning models in hydrological extrapolation tasks. *HESS* 29, 5871–5891, 2025.
4. [V] Acuña Espinoza E., Loritz R., Kratzert F., Klotz D., Gauch M., Álvarez Chaves M., Ehret U. Analyzing the generalization capabilities of (a) hybrid hydrological model(s) for extrapolation to extreme events. *HESS* 29, 1277–1294, 2025.
5. [V] Guan X., Shan B., Nguyen V.D., Merz B. Beyond Observed Extremes: Can Hybrid Deep Learning Models Improve Flood Prediction? *EGUsphere* preprint egusphere-2025-1509, 2025(检索时未见正式版)。
6. [S] Komiya (et al.). Informed Neural Networks for Flood Forecasting With Limited Amount of Training Data. *WRR*, 2025, doi:10.1029/2023WR036380。
7. [S/U] (作者未核) When are AI models ready for deployment? Reassessing Google's global AI flood forecasting system through the lens of responsible modelling. *Journal of Hydrology X*(推断自 PII S2589915526000027), 2026.
8. [S] Baste S., Lerch S., Klotz D., Loritz R. The need for uncertainty: why probabilistic LSTMs are key to improving flood predictions… *EGUsphere* egusphere-2026-469, 2026.
9. [S] (Google/合作团队) Extending Medium-Range Global Flood Forecasts: The Google Global Flood Forecasting Model Version 2. *EGUsphere* egusphere-2026-2283, 2026.
10. [S] From RNNs to Transformers: benchmarking deep learning architectures for hydrologic prediction. *HESS* 29, 6811, 2025.(作者未核)
11. [S] Wi S., Steinschneider S. Assessing the Physical Realism of Deep Learning Hydrologic Model Projections Under Climate Change. *WRR*, 2022, 2022WR032123.
12. [S] Coping with data scarcity in extreme flood forecasting: A deep generative modeling approach. *Advances in Water Resources*, 2025(PII S0309170825001770;作者未核)。
13. [S] Kratzert F., et al. HESS Opinions: Never train a Long Short-Term Memory (LSTM) network on a single basin. *HESS* 28, 4187, 2024.

**Thread 2 — DA/实时校正 × DL**
14. [V] Feng D., Fang K., Shen C. Enhancing Streamflow Forecast and Extracting Insights Using LSTM With Data Integration at Continental Scales. *WRR* 56, 2020, e2019WR026793.
15. [V] Nearing G.S., Klotz D., Frame J.M., Gauch M., Gilon O., Kratzert F., Sampson A.K., Shalev G., Nevo S. Technical note: Data assimilation and autoregression for using near-real-time streamflow observations in LSTM networks. *HESS* 26, 5493–5513, 2022.
16. [V] Gegenleithner S., Pirker M., Dorfmann C., Kern R., Schneider J. Long short-term memory networks for enhancing real-time flood forecasts: a case study for an underperforming hydrologic model. *HESS* 29, 1939–…, 2025.
17. [V] Yang W., Ji H., Lonzarich L., Song Y., Shen C. Diffusion-Based Probabilistic Modeling for Hourly Streamflow Prediction and Assimilation. arXiv:2510.08488, 2025.
18. [V] Jamaat A., Song Y., Rahmani F., Liu J., Lawson K., Shen C. Update hydrological states or meteorological forcings? Comparing data assimilation methods for differentiable hydrologic models. arXiv:2502.16444, 2025.
19. [S/U] Enhancing physically-based flood forecasts through fusion of LSTM with unscented Kalman filter. *Journal of Hydrology* 641, 2024(文章号 131809 或 131819,两处摘录不一致;作者未核)。
20. [S/U] Improving the Accuracy of Flood Forecasting Based on Deep Learning Models and Error Correction Methods: Dapoling Watershed, Huaihe River Basin. *J. Hydrologic Engineering* 31(1), 2026(ASCE, doi:10.1061/JHYEFF.HEENG-6686;作者未核)。
21. [V] Guo W.-D., Chen W.-B., Chang C.-H. Prediction of hourly inflow for reservoirs at mountain catchments using residual error data and multiple-ahead correction technique. *Hydrology Research* 54(9), 1072–1093, 2023.
22. [S] Tran V.N., et al. AI Improves the Accuracy, Reliability, and Economic Value of Continental-Scale Flood Predictions. *AGU Advances*, 2025, e2025AV001678.
23. [S] Towards a robust hydrologic data assimilation system for hurricane-induced river flow forecasting (HEAVEN). *HESS* 29, 2407, 2025(作者未核)。
24. [S] Advancing real-time error correction of flood forecasting based on the hydrologic similarity theory and machine learning techniques. *Environmental Research*, 2024(PII S0013935124004377)。
25. [S] A Bayesian Ensemble Learning-Based Scheme for Real-Time Error Correction of Flood Forecasting. *Water* 17(14):2048, 2025.
26. [S] Latent Three-Dimensional Variational Data Assimilation with Convolutional Autoencoder and LSTM for Flood Forecasting. Springer LNCS(ISDA/相关会议文集), 2025, doi:10.1007/978-3-031-97567-7_4。
27. [S] Data assimilation-based correction of flood forecasts in a large-scale river network: Pearl River Basin(1D水动力+EnKF,33站均值NSE 0.85). *Environmental Modelling & Software*, 2026(PII S1364815226001131)。
28. [S] Real-Time Dynamic Urban Flood Prediction: An Integrated Deep Learning Architecture with Adaptive Updating. *ACS ES&T Water*, 2025, doi:10.1021/acsestwater.5c01439。
29. [S] Boucher M.-A., et al. Data Assimilation for Streamflow Forecasting Using Extreme Learning Machines and Multilayer Perceptrons. *WRR* 56, 2020, e2019WR026226.
30. [S] Improving streamflow simulation through machine learning-powered data integration…Western U.S. *HESS* 29, 5453, 2025(作者未核)。

**Thread 3/4 — 迁移与水库入流**
31. [V] Ougahi J.H., Rowan J.S. Investigating Deep Learning Knowledge Transfer in Streamflow Prediction From Global to Local Catchment. *WRR* 62, 2026, e2025WR041194.
32. [S] Gao (et al.). Multi-Source Adaptive-Fusion Transfer Learning for Streamflow Forecasting in Data-Scarce Catchments. *WRR*, 2026, e2025WR042495.
33. [S] (CAS 成都山地所团队) Deep learning for cross-region streamflow and flood forecasting at a global scale (ED-DLSTM). *The Innovation* 5, 100617, 2024.
34. [V] Zhu Q., et al. Deep Transfer Learning Based on LSTM Model for Reservoir Flood Forecasting. *Int. J. Data Warehousing and Mining* 20(1), 2024.
35. [S] Hu P., (Ning Y. 组). HydroDCM: Hydrological Domain-Conditioned Modulation for Cross-Reservoir Inflow Prediction. arXiv:2512.03300, 2025(AAAI 2026 workshop oral)。
36. [S] Deep transfer learning based on Transformer for flood forecasting in data-sparse basins. *Journal of Hydrology*, 2023(PII S0022169423008983;作者未核)。
37. [S] Luo (et al.). Exploring the role of the LSTM model in improving multi-step ahead reservoir inflow forecasting. *J. Flood Risk Management*, 2023, doi:10.1111/jfr3.12854。
38. [S] Data-driven forecasting framework for daily reservoir inflow…multi-head attention(考虑洪峰). *Journal of Hydrology*, 2024(PII S0022169424015932)。

**Thread 5 + 中文文献**
39. [S/U] 欧阳文宇, 张弛(第二作者姓名未核全), 等. 人工智能驱动水文预报与水库调度研究的探索与思考. 水利学报 56(9), 2025.
40. [S/U] 深度学习技术在洪水预报中的应用进展及思考. 《气象》(或气象科技类期刊)2025年第4期(qxqk.nmc.cn;作者未核)。
41. [S/U] 区域化长短期记忆神经网络(LSTM)洪水预报模型研究. 湖泊科学, 2025(jlakes.org 文章号 20250226;作者未核)。
42. [S/U] 基于LSTM的山区流域洪水预报模型研究(崇阳溪, 1997-2022 30场洪水). 西南大学学报(自然科学版), 2025, doi:10.13718/j.cnki.xdzk.2025.05.015。
43. [S/U] 基于深度学习集合预报的水库闸门防洪优化调度. 水科学进展 35(6), 2024, doi:10.14042/j.cnki.32.1309.2024.06.004。
44. [S/U] 考虑径流过程矢量化的机器学习洪水预报模型. 水科学进展 35(3), 2024, doi:10.14042/j.cnki.32.1309.2024.03.006。
45. [S/U] 王宗志, 王坤, 等. 洪水高风险区雨水情监测预报预警关键技术研究框架. 水科学进展 36(6), 2025(涉及超标准洪水模拟与预见期延长)。
46. [S/U] 基于LSTM网络的实时入库洪水预报方法. 《水资源研究》(Hanspub JWRR)(年份约2021-2024;题录来自检索,细节未核)。
47. [S/U] 梁卓然, 金鑫, 等. 海河"23·7"暴雨移置辽河流域预报调度分析. 中国防汛抗旱(或东北水利水电), 2024, doi:10.16867/j.issn.1673-9264.2024143。
48. [S/U] 海河"25·7"区域性大洪水模拟复盘分析. 中国防汛抗旱, 2026(?)(zgfxkh.xml-journal.net;细节未核)。
49. [S/U] 辽宁省致灾暴雨洪水成因机理探析. 中国防汛抗旱, 2024, doi:10.16867/j.issn.1673-9264.2024006。
50. [U] LSTM-UKF/EnKF-BiLSTM 类中文期刊论文若干(检索摘录提及,具体题录需 CNKI 人工核实)。

**核查建议**:投稿前请人工精读 #15(Nearing TN)与 #17(h-Diffusion)全文,确认其正文无洪水量级分层的同化增益分析;并在 CNKI 用「实时校正+LSTM+入库」「数据同化+深度学习+超标准洪水」补一轮硕博论文检索——这是本次检索环境无法覆盖的最后盲区。
