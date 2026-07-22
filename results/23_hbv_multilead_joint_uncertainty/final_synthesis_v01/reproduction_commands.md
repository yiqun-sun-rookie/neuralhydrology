# 正式结果复现命令与状态

## 结论

`RELEASE`：十六个正式流域已用冻结合同逐流域重新计算，随后只从十六个成功分片重新生成汇总结果。每个流域包含36个数组和366,960个数值，总计576个数组和5,871,360个数值；复现分片、聚合结果和原正式结果三方逐元素最大绝对差为`0.0`。独立审查阻断问题为0，非阻断问题为0。

## 固定环境

工作目录：`G:\github\pycharm\projects\neuralhydrology`

```powershell
$env:OMP_NUM_THREADS='1'
$env:MKL_NUM_THREADS='1'
$env:OPENBLAS_NUM_THREADS='1'
$env:NUMEXPR_NUM_THREADS='1'
$env:VECLIB_MAXIMUM_THREADS='1'
$env:PYTHONHASHSEED='1'
$env:PYTHONDONTWRITEBYTECODE='1'
```

每次运行的资源门槛由冻结合同强制检查：启动时可用内存不低于25%，运行时不低于20%，预计峰值不超过启动时可用内存的60%，磁盘可用空间不低于50吉字节且不低于预计输出的三倍；数值线程为1，保留2个逻辑处理器。失败分片不得复用，重试必须更换分片标识。

## 建立并核验冻结复现会话

```powershell
python src\hbv_multilead_joint_uncertainty\scripts\run_reproduction.py prepare-reproduction-session `
  --contract results\23_hbv_multilead_joint_uncertainty\formal_contract_sixteen_v05 `
  --reference results\23_hbv_multilead_joint_uncertainty\formal_result_sixteen_v01 `
  --session-id formal_reproduction_session_v01

python src\hbv_multilead_joint_uncertainty\scripts\run_reproduction.py verify-reproduction-session `
  --session results\23_hbv_multilead_joint_uncertainty\formal_reproduction_session_v01
```

会话校验清单自身的安全散列算法二百五十六位值为`86c3232fca046b10cfcc269c96b08a8d5ed2a59d80bf91f6b37c2892f089734b`。会话固定37个数值源码文件、62个输入文件和3个控制文件；独立审查发现内容不一致文件0个。

## 串行重算十六个流域

以下是实际执行顺序。新的复现必须替换所有`v01`标识，不能覆盖本次结果。

```powershell
$basins=@(
  '12143600','04127918','09066000','06431500',
  '03479000','02296500','02015700','06892000',
  '05507600','06477500','08158700','11148900',
  '06404000','08189500','09505350','09447800'
)

foreach ($basin in $basins) {
  $shardId="formal_repro_${basin}_v01"
  python src\hbv_multilead_joint_uncertainty\scripts\run_reproduction.py run-reproduction-shard `
    --session results\23_hbv_multilead_joint_uncertainty\formal_reproduction_session_v01 `
    --shard-root results\23_hbv_multilead_joint_uncertainty\formal_reproduction_shards_v01 `
    --shard-id $shardId `
    --basin-id $basin
  if ($LASTEXITCODE -ne 0) { throw "分片 $shardId 失败" }
}
```

每个流域在独立进程中完成“计算、先保存复现数组、再读取原正式数组比较、完整内容核验、结束资源监测、原子发布”。十六个分片全部为`verified`，失败分片0个，未完成分片0个。

## 核验分片并重新生成汇总结果

```powershell
foreach ($basin in $basins) {
  python src\hbv_multilead_joint_uncertainty\scripts\run_reproduction.py verify-reproduction-shard `
    --session results\23_hbv_multilead_joint_uncertainty\formal_reproduction_session_v01 `
    --shard results\23_hbv_multilead_joint_uncertainty\formal_reproduction_shards_v01\formal_repro_${basin}_v01
}

python src\hbv_multilead_joint_uncertainty\scripts\run_reproduction.py aggregate-reproduction-shards `
  --session results\23_hbv_multilead_joint_uncertainty\formal_reproduction_session_v01 `
  --shard-root results\23_hbv_multilead_joint_uncertainty\formal_reproduction_shards_v01 `
  --aggregation-id formal_result_sixteen_reproduction_sharded_v01

python src\hbv_multilead_joint_uncertainty\scripts\run_reproduction.py verify-reproduction-aggregation `
  --aggregation results\23_hbv_multilead_joint_uncertainty\formal_result_sixteen_reproduction_sharded_v01
```

聚合结果包含240行逐流域指标、15行跨流域汇总、18行成对比较、816行候选概率和288行参数与过程噪声边际概率。独立脚本从数组重新计算后，十进制表格解析产生的最大差为`5.684341886080802×10⁻¹⁴`；正式聚合文件与原正式结果对应文件的校验值完全一致，图2/2逐像素一致，报告2/2逐字节一致。

## 资源结果与两次安全停止

成功复现链包含1次会话建立、16次逐流域计算和1次聚合，共18次运行、1,203个资源采样点；18/18份完整日志通过。运行期间最低可用内存比例为`21.666503%`，最大监测间隔为`9.934870`秒，最低磁盘可用空间为`2166.125538`吉字节，最大进程常驻内存为`0.179478`吉字节，所有数值计算线程均为1。

成功前有两次整包复现被资源门槛停止：第一次在完成4/16个流域后测得可用内存`17.916238%`；第二次在完成5/16个流域后测得`19.962392%`。两次失败产物和资源记录均保留，注册表状态均为失败，任何失败数组都未进入成功分片或聚合结果。

- [第一次安全停止记录](resource_abort_formal_reproduction_v01.json)
- [第二次安全停止记录](resource_abort_formal_reproduction_v02.json)

## 测试与独立审查

```powershell
$testFiles=Get-ChildItem test -Filter 'test_hbv_*.py' |
  Sort-Object Name |
  ForEach-Object FullName
python -B -m pytest -q -p no:cacheprovider $testFiles
```

冻结复现代码最后一次受资源监测的完整测试为184项通过、0项失败、1条既有配置警告；运行最低可用内存比例为`27.825184%`，最大资源采样间隔为`1.018011`秒。

独立审查不导入项目计算或验证模块，重新计算全部指标、概率、图和报告，并核验资源、注册表、输入、源码和内容清单。最终结论为`RELEASE`，审查包自检19/19通过。

- [逐流域复现聚合结果](../formal_result_sixteen_reproduction_sharded_v01/aggregation_manifest.json)
- [独立审查报告](../independent_audits/formal_result_sixteen_reproduction_sharded_v01_audit_v01/independent_scientific_audit_report.md)
- [独立审查机器可读摘要](../independent_audits/formal_result_sixteen_reproduction_sharded_v01_audit_v01/scientific_audit_summary.json)
- [独立审查包自检](../independent_audits/formal_result_sixteen_reproduction_sharded_v01_audit_v01/audit_package_self_check.json)
