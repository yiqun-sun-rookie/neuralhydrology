#!/bin/bash
# 在 HPC 端执行解包和安装的脚本
# 使用方法: 把所有 tar.gz 包上传到 ~/ 目录（或者任意你喜欢的目录），然后把这个脚本也放过去运行

# 设置出错立即停止
set -e

ECHO_PREFIX="[NeuralHydrology Setup]"

echo "$ECHO_PREFIX 开始解包流程..."

# 1. 解压代码包
if [ -f "nh_code.tar.gz" ]; then
    echo "$ECHO_PREFIX 正在解压代码包 nh_code.tar.gz..."
    # 这会解压出 neuralhydrology 文件夹
    tar -xzvf nh_code.tar.gz
    
    # 将解压后的文件夹移动到当前目录（如果 tar 包里包含了上级目录结构）
    # 注意：pack_for_migration.ps1 是把整个 'neuralhydrology' 文件夹打包的
    # 所以解压后当前目录下应该会出现 'neuralhydrology' 文件夹
else
    echo "$ECHO_PREFIX 警告: 未找到 nh_code.tar.gz，跳过代码解压。"
fi

# 进入项目目录
if [ -d "neuralhydrology" ]; then
    cd neuralhydrology
    echo "$ECHO_PREFIX 已进入项目目录: $(pwd)"
else
    echo "$ECHO_PREFIX 错误: 未找到 neuralhydrology 目录。请检查解压是否成功。"
    exit 1
fi

# 2. 解压数据包 (如果存在)
# 将上层目录的数据包解压到 data/ 目录中

# 创建 data 目录
mkdir -p data

# 解压 Namou
if [ -f "../data_namou.tar.gz" ]; then
    echo "$ECHO_PREFIX 正在解压 Namou 数据..."
    tar -xzvf ../data_namou.tar.gz -C .
fi

# 解压 Caravan Meta
if [ -f "../caravan_meta.tar.gz" ]; then
    echo "$ECHO_PREFIX 正在解压 Caravan Meta 数据..."
    tar -xzvf ../caravan_meta.tar.gz -C .
fi

# 解压 Caravan TimeSeries
if [ -f "../caravan_ts.tar.gz" ]; then
    echo "$ECHO_PREFIX 正在解压 Caravan Timeseries 数据 (这可能需要几分钟)..."
    tar -xzvf ../caravan_ts.tar.gz -C .
fi

echo "$ECHO_PREFIX 解包完成。"

# 3. 运行环境设置
# 给予脚本执行权限
if [ -f "hpc/setup_hpc.sh" ]; then
    chmod +x hpc/setup_hpc.sh
    echo "$ECHO_PREFIX 准备运行环境安装脚本 hpc/setup_hpc.sh (需要联网)..."
    echo "$ECHO_PREFIX 你确定要现在安装 Conda 环境吗? (y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])+$ ]]; then
        bash hpc/setup_hpc.sh
    else
        echo "$ECHO_PREFIX 跳过环境安装。"
    fi
else
    echo "$ECHO_PREFIX 未找到 hpc/setup_hpc.sh，请检查代码包完整性。"
fi

echo "$ECHO_PREFIX 所有步骤完成！"
