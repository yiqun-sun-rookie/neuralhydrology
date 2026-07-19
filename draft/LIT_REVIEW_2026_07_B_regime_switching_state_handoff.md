# 文献查新报告 B:按工况切换的多专用DL水文模型 + 隐状态跨切换传递

**调研日期**: 2026-07-19
**对应候选 idea**: 多个专用 DL 水文模型按工况自动切换 + 隐状态跨切换传递(拟立项 ID 09)
**调研方式**: 后台 agent 约 25 组 WebSearch 对抗性检索 + 本机 neuralhydrology 源码核验
**核心结论**: **该精确组合空白(置信度 75-80%)**——水文侧的切换全部无状态;ML 侧的状态连续切换全部是联合训练单模型;已有状态移交(MTS-LSTM、Google Nature 2024)全部发生在固定而非工况触发的交接点
**投稿前必查**: HydMoE(WRM 2026)与 Sun et al.(JoH 2025)全文;中文核心期刊补检;2026 预印本增量

---

检索时间:2026年7月。方法:WebSearch 约25组查询(HESS/WRR/JoH/Nature/NeurIPS/ICML/arXiv/EGUsphere/中文文献),对可达来源核验摘要;Copernicus/Elsevier/Springer/arXiv 全文被网络策略拦截,故部分条目标注核验层级(**[摘要核验]** = 通过检索摘录确认关键机制;**[推断]** = 基于检索摘要合理推断;**[unverified]** = 细节未能确认)。另:MTS-LSTM 的状态传递机制在本机 neuralhydrology 源码(`neuralhydrology/modelzoo/mtslstm.py`)中直接核验。

---

## 1. 最近邻工作表

| # | Citation | Venue/年 | 切换机制 | 状态是否传递 | 与本 idea 的差异 |
|---|---|---|---|---|---|
| 1 | Zhang & Govindaraju, "Prediction of watershed runoff using Bayesian concepts and modular neural networks" | WRR 2000 | 硬(低/中/高流量级分模块,Bayesian 组合) | 否(前馈网络,无递归状态) | 概念鼻祖:按流量级分专家,但全程无状态 **[摘要核验]** |
| 2 | See & Openshaw, "A hybrid multi-model approach to river level forecasting" | Hydrol. Sci. J. 2000 | 数据预分组(SOM/模糊聚类)+模糊规则集成,软/硬混合 | 否 | 无状态、无DL、按样本分组 **[摘要核验]** |
| 3 | Corzo & Solomatine, "Baseflow separation techniques for modular artificial neural network modelling in flow forecasting" | Hydrol. Sci. J. 2007 | 硬(基流/超渗流分离,K-means/滤波分割水文过程线) | 否 | 时域上确实"分段切模型",但 ANN 无状态,切换零成本,无移交问题 **[摘要核验]** |
| 4 | Corzo & Solomatine, "Knowledge-based modularization and global optimization of ANN models in hydrological forecasting" | Neural Networks 2007 | 硬(知识驱动模块化,局部模型+委员会) | 否 | 同上 **[摘要核验]** |
| 5 | Toth, "Classification of hydro-meteorological conditions and multiple artificial neural networks for streamflow forecasting" | HESS 2009 | 硬(SOM 对水文气象条件在线分类,逐时段选 ANN) | 否 | 与本 idea 的"检测工况→切模型"流程几乎相同,但模型无状态——最直接的无状态前身 **[摘要核验]** |
| 6 | Hashemi, Brigode, Garambois & Javelle, "How can we benefit from regime information to make more effective use of LSTM runoff models?" | HESS 2022 | 无时域切换(按 regime 对**流域**分组,分组训练区域 LSTM) | 否 | regime 用于空间分组训练,不在模拟过程中切换;结论仅"同 regime 分组训练略优" **[摘要核验]** |
| 7 | Sun, Rong, Xie, Huang & Chen, "Mixture of experts leveraging Informer and LSTM variants for enhanced daily streamflow forecasting" | J. Hydrol. 2025 | 硬路由(RF/LSTM/Transformer 作 router,4类/2类专家选择) | 否(每专家独立处理自己的输入窗口,仅输出层集成) | 专家按**架构**分(LSTM/GRU/Informer),不按水文工况分;无状态交接 **[摘要核验]** |
| 8 | "Enhancing Multi-Step Ahead Daily Runoff Prediction via HydMoE Model with Local-Global Hybrid Attention" | Water Resour. Manage. 2026 | 软(自适应 MoE 路由 + Time2Vec + 混合注意力) | 无证据(注意力/窗口式,非跨切换递归状态) [unverified 细节] | 水文 MoE 但软门控、联合训练、无独立专家状态移交 **[摘要核验]** |
| 9 | Gauch, Kratzert, Klotz, Nearing, Lin & Hochreiter, "Rainfall–runoff prediction at multiple timescales with a single LSTM network" (MTS-LSTM) | HESS 2021 | 无 regime 切换(按**时间尺度**分支) | **是**:h、c 经 linear/identity 传递层交给高分辨率 LSTM(源码核验:`transfer_fcs`) | 状态移交机制的最强先例,但切换维度是时间尺度而非工况,分支联合训练 **[全文+源码核验]** |
| 10 | Nearing et al., "Global prediction of extreme floods in ungauged watersheds" | Nature 2024 | 无(encoder→decoder 固定交接,非条件切换) | **是**:线性 cell-state 传递网络 + tanh 全连接 hidden-state 传递网络 | 两个不同 LSTM 间的状态移交已是业界操作,但按预报阶段划分、联合训练、单一"专家" **[摘要核验]** |
| 11 | Ilhan, Karaahmetoglu, Balaban & Kozat, "Markovian RNN: An Adaptive Time Series Prediction Network with HMM-Based Switching for Nonstationary Environments" | IEEE TNNLS 2021 | 软(HMM belief 加权),每个 regime 有独立递归转移权重 | **是**(单一内部状态连续演化,由各 regime 候选状态按 belief 加权合成) | 机制上最接近:regime 专属递归动力学 + 状态连续;但单网络端到端联合训练、非独立专家、非水文 **[摘要核验]** |
| 12 | Linderman et al., "Recurrent switching linear dynamical systems" (rSLDS) | AISTATS 2017 | 硬(离散模式切换,连续状态反馈驱动切换) | **是**(共享连续潜状态跨切换持续) | 线性动力学、联合推断、共享状态空间;未见水文径流应用 **[摘要核验]** |
| 13 | Dong et al., "Collapsed amortized variational inference for switching nonlinear dynamical systems" (SNLDS) | ICML 2020 [venue unverified] | 硬(离散开关) | 是(连续潜状态共享) | 同上家族;非水文 **[摘要核验]** |
| 14 | Ansari et al., "Deep Explicit Duration Switching Models for Time Series" (RED-SDS) | NeurIPS 2021 | 硬(state-to-switch 递归 + 显式持续时间变量) | 是(连续潜状态共享) | 同上家族;非水文 **[摘要核验]** |
| 15 | Xu & Chen(作者待核),"Deep switching state space model (DS3M) for nonlinear time series forecasting with regime switching" | arXiv 2021 / Int. J. Forecasting 2025 | 硬(Markov 链离散 regime) | 是(离散+连续潜变量并行) | 通用时序(金融/电力等);非水文、非独立专家 **[摘要核验,作者名 unverified]** |
| 16 | Namikawa & Tani, "A model for learning to segment temporal sequences, utilizing a mixture of RNN experts together with adaptive variance" | Neural Networks 2008 [年份/卷 unverified] | 硬(gate 赢者通吃) | **各专家自带独立递归状态,并行常开**——用"全体专家持续热运行"回避了移交问题 | 机器人序列分割;专家联合训练;无"状态从A交给B" **[摘要核验]** |
| 17 | Wolpert & Kawato, "Multiple paired forward and inverse models for motor control" (MOSAIC) | Neural Networks 1998 | 软(responsibility 信号) | 各前向模型并行维护自身状态 | 运动控制;同为"并行常开"范式 **[摘要核验]** |
| 18 | Pawelzik, Kohlmorgen & Müller, "Annealed competition of experts for a segmentation and classification of switching dynamics" | Neural Computation 1996 [卷期 unverified] | 硬(退火竞争) | 否 | 切换动力学分割的 ML 经典;预测器无递归状态传递 **[摘要核验]** |
| 19 | Kratzert, Gauch, Klotz & Nearing, "HESS Opinions: Never train a Long Short-Term Memory (LSTM) network on a single basin" | HESS 2024 | —(反面证据) | — | 实证:把 CAMELS 按水文相似性分组分别训练,**性能反而低于**单一全量模型 **[摘要核验]** |
| 20 | Fang, Kifer, Lawson, Feng & Shen, "The Data Synergy Effects of Time-Series Deep Learning Models in Hydrology" | WRR 2022 | —(反面证据) | — | "数据协同":异质数据合并训练优于同质分区专训 **[摘要核验]** |

补充近邻(未入表):Frame et al., "Deep learning rainfall–runoff predictions of extreme events", HESS 2022(单体 LSTM 对极端事件外推已不差,削弱"极端需专家"论点,[摘要核验]);Bakke et al., "The ability of LSTM to model snowmelt versus rainfall generated floods", EGUsphere preprint 2026(只做分洪水类型**评估**,不做分模型,[摘要核验]);"Progressive Mixture-of-Experts with autoencoder routing for continual RANS turbulence modelling", arXiv 2026(湍流领域"每专家=一种流态、router=流态分类器"的硬路由 MoE,[摘要核验]);Du et al., "AdaRNN: Adaptive Learning and Forecasting of Time Series", CIKM 2021;"Dynamic TMoE: Drift-Aware Dynamic Mixture of Experts for Non-Stationary Time Series Forecasting", arXiv 2026 [仅标题核验]。

---

## 2. 判定

**结论:空白(该精确组合未见发表)。置信度:中高(约 75–80%)。**

拆解成三个组件看:
- 组件A"按水文工况硬切换多个专用模型":水文界已做 20+ 年(Zhang & Govindaraju 2000;Corzo & Solomatine 2007;Toth 2009),但全部是**无状态前馈网络**,切换无代价,因此"状态移交"问题在该文献线中从未出现——已确认无人传状态。
- 组件B"不同 DL 水文模型间隐状态移交":已存在且已是主流工程实践,但只在**固定、非条件性**的交接点(MTS-LSTM 跨时间尺度,linear/identity 传递层,源码核验;Google Nature 2024 encoder→decoder,线性 c + 非线性 h 传递网络)。没有任何工作把它用于**由检测到的 regime 触发的运行时切换**。
- 组件C"regime 切换 + 状态连续":在 ML 方法文献中成熟(rSLDS/SNLDS/RED-SDS/DS3M/Markovian RNN),但全部是**单一模型联合训练、共享状态空间**,并且未检索到任何径流/水文应用。

A+B+C 的交集——**独立训练的多个专用递归水文模型 + 推理时按工况硬切换 + 隐状态跨切换移交(免冷启动)**——在水文期刊(HESS/WRR/JoH/GMD/JAMES/WRM)、ML会议与 arXiv(截至 2026-07)均未检索到。特别是"**独立训练**的专家之间做状态移交"这一点,连通用时序文献里也没有直接先例(最接近的是 model stitching,但那是分类网络逐层拼接,不是时序推理中的动态交接)。

置信度扣分项:(i) HydMoE(WRM 2026)与 Sun et al.(JoH 2025)只核验到摘要级机制,全文被拦;(ii) 中文核心期刊(《水利学报》《水科学进展》等)覆盖不足;(iii) 2026 年预印本增量大,EGU/AGU 会议摘要未穷尽。建议投稿前对这三处再做一次人工复查。

---

## 3. 最大威胁工作 Top 3

1. **Markovian RNN(Ilhan et al., IEEE TNNLS 2021)** — 机制层面的最近邻:每个 regime 拥有独立的递归转移权重,HMM belief 控制切换,内部状态跨 regime 连续演化。审稿人可以说"你的方法 = Markovian RNN 的硬切换版 + 水文应用"。防御点:它是单网络端到端联合训练(专家不可独立训练/替换/复用),软加权而非硬切换,且从未用于水文;你的贡献要落在"独立训练的可插拔专家 + 显式移交算子 + 水文域验证"。
2. **switching SSM 家族(rSLDS AISTATS 2017;SNLDS ICML 2020;RED-SDS NeurIPS 2021;DS3M IJF 2025)** — 方法学威胁:"离散模式切换 + 连续潜状态"是它们的定义性特征,你的 idea 会被定性为"该框架的一个水文应用变体"。防御点:它们共享单一潜空间、联合推断、通常线性/浅非线性动力学,无法容纳各自独立训练的大型 LSTM/Mamba 专家;且水文应用为零(这同时是你的机会)。
3. **水文 MoE 双连击:Sun et al.(J. Hydrol. 2025)+ HydMoE(WRM 2026)** — 期刊层面的最近邻:审稿人首先想到"MoE 已进入 JoH/WRM"。防御点:两者的专家按**模型架构**或抽象 pattern 划分而非水文工况;路由是逐窗口的输出选择/加权,不存在递归状态跨切换问题;必须以它们为 baseline 并显式对比。

另一类"动机威胁"(不撞创新点但打击立论):Kratzert et al. 2024(HESS Opinions)+ Fang et al. 2022(WRR 数据协同)+ Frame et al. 2022(单体 LSTM 极端事件表现不差)。论文必须正面回答:**为什么时间维度的工况专精能赢,而空间维度的流域分组专训已被证明会输**。这是 introduction 里绕不开的一段。

---

## 4. 状态传递技术方案盘点 + 必备 baseline 清单

### 可行的状态移交/连续性方案(带出处)

| 方案 | 机制 | 出处/先例 | 备注 |
|---|---|---|---|
| 学习式状态投影(stitching 层) | 切换时 h,c 经线性/浅非线性适配层映射到目标专家状态空间 | MTS-LSTM `transfer_fcs`(Gauch et al. HESS 2021,linear/identity,源码核验);Nearing et al. Nature 2024(线性 c-transfer + tanh FC h-transfer);Lenc & Vedaldi CVPR 2015、Bansal et al. NeurIPS 2021(独立训练网络间线性 stitch 仅损失 2–5%) | 最直接;model stitching 结果是"独立训练模型状态可对齐"的理论依据;适配层可在重叠模拟段上事后训练 |
| 共同祖先微调(隐式对齐) | 先训单一全局模型,再按工况分别微调出专家;状态空间天然近似对齐,移交可用 identity/低秩修正 | 迁移学习/微调惯例;与 Kratzert 2024 的"先全量后专精"兼容 | 最可能通过审稿的路线;削弱"表征空间不同怎么交接"的质疑 |
| 共享骨干 + 工况专属头/适配器 | 递归状态只存在于共享骨干(天然连续),工况专精放在无状态的头或 LoRA 适配器里 | 多任务标准做法;LoRA per-domain adapter 已是时序基础模型惯例(TimesFM/Chronos-2 生态,2025–2026);DynMoLE arXiv 2025 | 把"切换"降维成头/适配器切换,完全回避状态移交——审稿人会问你为什么不这么做,需作为对照 |
| 权重空间切换/混合 | 状态与 I/O 不变,按工况切换或混合**权重集** | MANN(Zhang, Starke, Komura & Saito, SIGGRAPH/TOG 2018,门控混合专家权重);hypernetworks(Ha et al. 2016 [unverified 细节]);Markovian RNN(per-regime 递归权重) | 与"状态连续"天然相容;硬切权重时状态语义靠共同训练锚定 |
| 全专家并行热运行(回避移交) | 所有专家持续接收输入、各自维护状态,切换只发生在输出端 | MOSAIC(Wolpert & Kawato 1998);Namikawa & Tani 2008;Markovian RNN 的 belief 加权本质相同 | K 倍推理成本换零移交风险;必须作为消融,用以证明"移交"本身有价值(省算力且不掉点) |
| 状态重建/流形初始化 | 切换时由近期观测直接推断目标专家的合理初始状态 | "Initializing LSTM internal states via manifold learning", arXiv 2104.13101;可学习 h0/c0(水文 LSTM 文献常见做法,[摘要核验]) | 移交失败时的兜底;也可与投影法混合 |
| 联合训练的 switching SSM | 用 rSLDS/DS3M 式统一框架端到端学切换与动力学 | Linderman 2017;Dong 2020;Ansari 2021;DS3M 2025 | 若放弃"独立训练"约束,这是原则性最干净的方案;审稿人会要求解释为何不用 |

### 审稿人必然要求的 baseline 清单

1. **单一区域 LSTM**(Kratzert et al. 2018/2019 配置,静态属性条件化 EA-LSTM)——行业默认。
2. **单体模型 + regime 作为输入特征**(one-hot/连续 regime 指标作动态输入;另见 "Strategies for incorporating static features into global deep learning models", HESS 2026)——最便宜的对照,常常很难打。
3. **软 MoE(联合训练门控)**——对齐 Sun et al. 2025 与 HydMoE 2026 的设置。
4. **硬切换 + 冷启动**(切换后用 N 天 warm-up 重算状态;水文惯例 warm-up 为 270–365 天,[摘要核验])——量化"免冷启动"到底值多少。
5. **硬切换 + 全专家并行热状态**(无移交)——隔离"移交算子"的净贡献,这是最关键的消融。
6. **独立训练专家 vs 共同祖先微调专家**——回应表征空间对齐质疑。
7. **移交算子消融:none / identity / linear / 非线性**——直接复用 MTS-LSTM 的实验设计语言(`transfer_mtslstm_states` 配置)。
8. **oracle regime 标签 vs 在线检测器**——切换误判的敏感性分析(Toth 2009 的 SOM 在线分类是历史参照)。
9. **按损失函数专精的 ensemble**(quantile/expectile 多损失 LSTM 集成,Appl. Soft Comput. 2026,[摘要核验])——"专精"的另一种廉价实现。
10. 论述层面必须引用并回应:Kratzert et al. 2024、Fang et al. 2022(分组专训失败的证据)、Frame et al. 2022(单体模型极端事件不差)。

---

## 5. 完整引文列表

水文—模块化/工况(经典):
1. Zhang, B. & Govindaraju, R. S., "Prediction of watershed runoff using Bayesian concepts and modular neural networks", Water Resources Research, 2000. [摘要核验]
2. See, L. & Openshaw, S., "A hybrid multi-model approach to river level forecasting", Hydrological Sciences Journal 45(4), 2000. [摘要核验]
3. Corzo, G. & Solomatine, D., "Baseflow separation techniques for modular artificial neural network modelling in flow forecasting", Hydrological Sciences Journal 52(3): 491–507, 2007. [摘要核验]
4. Corzo, G. & Solomatine, D., "Knowledge-based modularization and global optimization of artificial neural network models in hydrological forecasting", Neural Networks 20: 528–536, 2007. [摘要核验]
5. Toth, E., "Classification of hydro-meteorological conditions and multiple artificial neural networks for streamflow forecasting", HESS 13: 1555, 2009. [摘要核验]
6. Abrahart, R. J. et al., "Two decades of anarchy? Emerging themes and outstanding challenges for neural network river forecasting", Progress in Physical Geography, 2012. [标题核验]

水文—DL 时代:
7. Kratzert, F. et al., "Rainfall–runoff modelling using Long Short-Term Memory (LSTM) networks", HESS 22: 6005, 2018. [标题核验]
8. Gauch, M. et al., "Rainfall–runoff prediction at multiple timescales with a single Long Short-Term Memory network", HESS 25: 2045–2062, 2021. [全文机制经源码核验]
9. Hashemi, R., Brigode, P., Garambois, P.-A. & Javelle, P., "How can we benefit from regime information to make more effective use of long short-term memory (LSTM) runoff models?", HESS 26: 5793–5816, 2022. [摘要核验]
10. Hashemi, R. et al., "How can regime characteristics of catchments help in training of local and regional LSTM-based runoff models?", HESSD preprint hess-2021-511, 2021. [摘要核验]
11. Frame, J. M. et al., "Deep learning rainfall–runoff predictions of extreme events", HESS 26: 3377–3392, 2022. [摘要核验]
12. Fang, K., Kifer, D., Lawson, K., Feng, D. & Shen, C., "The Data Synergy Effects of Time-Series Deep Learning Models in Hydrology", Water Resources Research, 2022. [摘要核验]
13. Kratzert, F., Gauch, M., Klotz, D. & Nearing, G., "HESS Opinions: Never train a Long Short-Term Memory (LSTM) network on a single basin", HESS 28: 4187, 2024. [摘要核验]
14. Nearing, G. et al., "Global prediction of extreme floods in ungauged watersheds", Nature 627, 2024. [摘要核验]
15. Sun, W., Rong, Z., Xie, Y., Huang, Z. & Chen, X., "Mixture of experts leveraging Informer and LSTM variants for enhanced daily streamflow forecasting", Journal of Hydrology, 2025. [摘要核验]
16. "Enhancing Multi-Step Ahead Daily Runoff Prediction via HydMoE Model with Local-Global Hybrid Attention", Water Resources Management, 2026. [摘要核验;作者名 unverified]
17. Bakke, S. J., Barna, D. M., Engeland, K., Kolberg, S. A. & Nordeide, S., "The ability of LSTM to model snowmelt versus rainfall generated floods", EGUsphere preprint egusphere-2026-1056, 2026. [摘要核验]
18. "Strategies for incorporating static features into global deep learning models", HESS 30: 1877, 2026. [标题核验]
19. "Unveiling the limits of deep learning models in hydrological extrapolation tasks", HESS 29: 5871, 2025. [标题核验]
20. "Ensemble streamflow forecasting with diverse loss functions", Applied Soft Computing, 2026. [摘要核验;作者 unverified]

ML 方法—切换/状态空间:
21. Pawelzik, K., Kohlmorgen, J. & Müller, K.-R., "Annealed competition of experts for a segmentation and classification of switching dynamics", Neural Computation 8, 1996. [摘要核验;卷期 unverified]
22. Wolpert, D. & Kawato, M., "Multiple paired forward and inverse models for motor control (MOSAIC)", Neural Networks 11, 1998. [摘要核验]
23. Namikawa, J. & Tani, J., "A model for learning to segment temporal sequences, utilizing a mixture of RNN experts together with adaptive variance", Neural Networks, 2008. [摘要核验;年份 unverified]
24. Linderman, S. et al., "Recurrent switching linear dynamical systems (rSLDS)", AISTATS 2017. [摘要核验]
25. Dong, Z. et al., "Collapsed amortized variational inference for switching nonlinear dynamical systems (SNLDS)", ICML 2020. [摘要核验;venue unverified]
26. Ansari, A. F. et al., "Deep Explicit Duration Switching Models for Time Series (RED-SDS)", NeurIPS 2021. [摘要核验]
27. Ilhan, F., Karaahmetoglu, O., Balaban, I. & Kozat, S. S., "Markovian RNN: An Adaptive Time Series Prediction Network with HMM-Based Switching for Nonstationary Environments", IEEE TNNLS, 2021. [摘要核验]
28. "Deep switching state space model (DS3M) for nonlinear time series forecasting with regime switching", arXiv:2106.02329;International Journal of Forecasting, 2025. [摘要核验;作者 unverified]
29. Du, Y. et al., "AdaRNN: Adaptive Learning and Forecasting of Time Series", CIKM 2021. [摘要核验]
30. "Hybrid hidden Markov LSTM for short-term traffic flow prediction", arXiv:2307.04954, 2023. [摘要核验]
31. "Dynamic TMoE: A Drift-Aware Dynamic Mixture of Experts Framework for Non-Stationary Time Series Forecasting", arXiv, 2026. [仅标题,unverified]
32. "Progressive Mixture-of-Experts with autoencoder routing for continual RANS turbulence modelling", arXiv, 2026. [摘要核验]

状态对齐/移交可行性:
33. Lenc, K. & Vedaldi, A., "Understanding image representations by measuring their equivariance and equivalence", CVPR 2015. [摘要核验]
34. Bansal, Y., Nakkiran, P. & Barak, B., "Revisiting Model Stitching to Compare Neural Representations", NeurIPS 2021. [摘要核验]
35. Zhang, H., Starke, S., Komura, T. & Saito, J., "Mode-Adaptive Neural Networks for Quadruped Motion Control", ACM TOG (SIGGRAPH) 2018. [摘要核验]
36. "Initializing LSTM internal states via manifold learning", arXiv:2104.13101, 2021. [标题核验]
37. Pióro, M. et al., "MoE-Mamba: Efficient Selective State Space Models with Mixture of Experts", arXiv:2401.04081, 2024. [摘要核验;作者 unverified]
38. Ha, D., Dai, A. & Le, Q., "HyperNetworks", ICLR 2017. [背景知识,unverified]
39. Kratzert, F. et al., "Towards learning universal, regional, and local hydrological behaviors via machine learning applied to large-sample datasets (EA-LSTM)", HESS 23, 2019. [背景知识,细节 unverified]

**核心判定重申**:按工况硬切换的多个独立训练 DL 水文模型 + 隐状态跨切换移交,这一精确组合截至 2026 年 7 月未检索到先例——水文侧的切换全部无状态,ML 侧的状态连续切换全部是联合训练单模型,而已有的状态移交(MTS-LSTM、Google Nature 2024)全部发生在固定而非工况触发的交接点。写作时的生死线在于:(1) 与 Markovian RNN / switching SSM 家族划清"独立可插拔专家 + 显式移交算子"的界限;(2) 用"并行热状态"和"冷启动"两个消融证明移交算子本身的净价值;(3) 正面回应 Kratzert 2024 / Fang 2022 的"专精必输"证据。
