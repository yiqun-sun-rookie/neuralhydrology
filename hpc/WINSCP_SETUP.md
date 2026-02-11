# WinSCP 同步配置指南

## 一、首次配置（保存会话）

### 1. 打开 WinSCP，创建新站点

1. 启动 WinSCP
2. 点击 **新建站点 (New Site)**
3. 填写连接信息：

| 字段 | 值 |
|------|-----|
| 文件协议 | SFTP |
| 主机名 | `hpcbh.hhu.edu.cn` |
| 端口 | 22 |
| 用户名 | `sunyiq` |
| 密码 | (留空，每次输入更安全) |

4. 点击 **保存**，站点名称填写：`hhu_hpc`
5. 勾选 **保存密码**（可选，不推荐）

### 2. 设置默认目录

1. 在站点列表中选择 `hhu_hpc`
2. 点击 **编辑 → 高级**
3. 左侧选择 **目录**
4. 设置：
   - 远程目录: `/data1/home/sunyiq/neuralhydrology`
   - 本地目录: `G:\github\pycharm\projects\neuralhydrology`
5. 点击 **确定** 保存

---

## 二、手动同步操作（推荐新手）

### 步骤 1: 连接 HPC

1. 双击 `hhu_hpc` 站点
2. 输入密码（静态密码 + OTP 动态码，无空格）

### 步骤 2: 打开同步对话框

1. 菜单栏点击 **命令 (Commands) → 同步 (Synchronize)**
2. 或按快捷键 `Ctrl+S`

### 步骤 3: 配置同步选项

在同步对话框中设置：

| 选项 | 设置 |
|------|------|
| 方向 | **Local → Remote** (本地到远程) |
| 模式 | **同步文件 (Synchronize files)** |
| 同步选项 | ☑ 预览变更 |

### 步骤 4: 设置排除规则 ⭐重要

1. 点击 **文件掩码 (File mask)** 右边的 `...` 按钮
2. 在弹出的对话框中，切换到 **排除 (Exclude)** 标签
3. 添加以下排除规则（每行一个）：

```
data/
runs/
results/*/*.pt
results/*/*.0
.git/
__pycache__/
*.pyc
*.pt
*.tar.gz
*.zip
.idea/
.vscode/
```

4. 点击 **确定**

### 步骤 5: 预览并执行

1. 点击 **比较 (Compare)** 查看将同步的文件
2. 检查列表，确保没有大文件
3. 点击 **同步 (Synchronize)** 执行

---

## 三、快速同步（只同步特定目录）

如果只想同步 caravan 相关的文件：

1. 在左侧导航到 `G:\github\pycharm\projects\neuralhydrology\src\`
2. 在右侧导航到 `/data1/home/sunyiq/neuralhydrology/src/`
3. 选中左侧的 `caravan_global` 文件夹
4. 右键 → **上传 (Upload)**

同样方法上传 `draft/` 目录。

---

## 四、使用脚本自动同步（高级）

### 方法 A: 在 WinSCP 中运行脚本

1. 连接到 HPC
2. 菜单 **命令 → 运行脚本 (Run Script)**
3. 选择 `hpc/winscp_sync.txt`

### 方法 B: 命令行运行

打开 PowerShell：

```powershell
cd "G:\github\pycharm\projects\neuralhydrology"

# 运行同步脚本
& "C:\Program Files (x86)\WinSCP\WinSCP.com" /script=hpc/winscp_sync.txt /log=hpc/winscp.log
```

> 注意：首次运行需要手动输入密码，或在脚本中配置密钥认证

---

## 五、同步后验证

在 HPC 上执行：

```bash
# 登录 HPC
ssh sunyiq@hpcbh.hhu.edu.cn

cd ~/neuralhydrology

# 检查新文件
ls -la src/caravan_global/
ls -la draft/
ls -la hpc/

# 验证配置
head src/caravan_global/configs/caravan_hpc.yml

# 测试提交（干跑）
sbatch --test-only src/caravan_global/hpc/submit_caravan.slurm
```

---

## 六、常见问题

### Q: 同步太慢？
- 排除 `data/` 和 `runs/` 目录
- 使用"只同步新文件"选项

### Q: 权限问题？
```bash
chmod +x hpc/*.sh
chmod +x src/*/hpc/*.slurm
```

### Q: 如何只上传修改过的文件？
- 同步对话框中选择 **只比较时间戳**
- 或使用 **同步 → 仅较新文件**

---

## 七、推荐的同步顺序

每次修改代码后：

1. **同步 src/** - 代码和配置
2. **同步 draft/** - 文档
3. **同步 hpc/*.sh** - 通用脚本（如有修改）
4. **SSH 验证** - 确认文件到位
5. **提交作业** - `sbatch src/caravan_global/hpc/submit_caravan.slurm`
