# 十五状态模型三阶段因素切换实现计划

**目标：** 建立三个互相隔离、可从原始数组复算的三阶段切换实验，检验参数、过程噪声及其联合候选识别和一日、三日、七日无观测预报。

**结构：** 新增独立的三阶段切换核心模块和打包脚本，复用现有候选滤波器、独立真值传播和无观测预报函数，不改变旧实验默认行为或冻结结果。每个场景使用独立配置和输出目录，最后再生成只读综合结论。

**技术：** Python、NumPy、pandas、pytest；单进程串行执行。

---

### 任务一：冻结三阶段逐日真值标签

**文件：**

- 新建 `test/test_hbv_three_stage_switching_validation.py`
- 新建 `src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py`

先写失败测试，要求三个阶段长度严格覆盖45天、预报7天保持第三阶段、参数和噪声联合标签在第16天与第31天同步改变，并拒绝缺失或重复候选。运行测试确认因功能不存在而失败，再实现最小标签生成函数并确认通过。

### 任务二：保存逐日概率和严格因果预报

**文件：**

- 修改 `test/test_hbv_three_stage_switching_validation.py`
- 修改 `src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py`

先写失败测试，要求参数、噪声和联合场景分别返回正确候选数、逐日概率、逐日真值标签、十五状态真值、同化终点状态及一日、三日、七日预报；改变未来流量不得改变已发布预报。实现时复用现有候选库和无观测预报，不读取未来流量。

### 任务三：打包可复算证据和动态资源核对

**文件：**

- 新建 `src/hbv_multilead_joint_uncertainty/scripts/run_three_stage_switching_validation.py`
- 新建三个 `src/hbv_multilead_joint_uncertainty/configs/three_stage_*_v01.json`
- 修改 `test/test_hbv_three_stage_switching_validation.py`

先写失败测试，要求输出包含冻结配置、原始数值数组、候选识别表、预报比较表、资源实测与估算、源码快照、保护路径前后校验和及完整文件清单。实现原子发布和串行资源门控，不覆盖已有目录。

### 任务四：小规模实测、正式运行和独立验证

先运行单随机区块实测并保存峰值内存与运行时间。确认正式规模内存安全余量后，依次运行参数切换、过程噪声切换和联合切换三个配置。独立上下文审查实现与方法，另一个独立上下文从原始数组复算所有判断。存在问题则生成新版本，不修改已发布证据。

