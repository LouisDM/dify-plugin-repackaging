#!/bin/bash
# author: Junjie.M

set -e  # 遇到错误立即退出
set -x  # 打印执行的命令

# 安装 unzip
install_unzip() {
	if ! command -v unzip &> /dev/null; then
		echo "Installing unzip ..."
		yum -y install unzip
		if [ $? -ne 0 ]; then
			echo "Install unzip failed."
			exit 1
		fi
	fi
}

# 检查 Docker 是否可用
check_docker() {
	if ! command -v docker &> /dev/null; then
		echo "Error: Docker is not installed"
		exit 1
	fi
	
	if ! docker info &> /dev/null; then
		echo "Error: Docker daemon is not running"
		exit 1
	fi
}

# 根据平台设置对应的架构标签和 Docker 镜像
set_platform_tags() {
	local platform=$1
	case "$platform" in
		*"aarch64"*|*"arm64"*)
			PLATFORM_TAGS=(
				"--platform=manylinux_2_17_aarch64"
				"--platform=manylinux2014_aarch64"
				"--platform=manylinux_2_28_aarch64"
				"--platform=manylinux_2_39_aarch64"
			)
			USE_DOCKER=false
			;;
		*"x86_64"*|*"amd64"*)
			PLATFORM_TAGS=(
				"--platform=manylinux_2_17_x86_64"
				"--platform=manylinux2014_x86_64"
				"--platform=manylinux_2_28_x86_64"
				"--platform=manylinux_2_39_x86_64"
			)
			USE_DOCKER=false
			;;
		*)
			echo "Unsupported platform: $platform"
			exit 1
			;;
	esac
}

# 在 Docker 中下载包
download_packages_in_docker() {
	local package_dir=$1
	local requirements_file=$2
	local max_retries=3
	local retry_count=0
	
	# 检查 Docker
	check_docker
	
	# 创建临时 Dockerfile
	cat > Dockerfile.tmp << EOF
FROM ${DOCKER_IMAGE}
RUN pip install --upgrade pip
WORKDIR /app
COPY ${requirements_file} .
RUN pip download -r requirements.txt -d /wheels ${PLATFORM_TAGS} --index-url ${PIP_MIRROR_URL} --trusted-host mirrors.aliyun.com --pre --only-binary=:all:
EOF
	
	# 构建 Docker 镜像（带重试）
	while [ $retry_count -lt $max_retries ]; do
		if docker build -t plugin-builder -f Dockerfile.tmp .; then
			break
		fi
		retry_count=$((retry_count + 1))
		if [ $retry_count -eq $max_retries ]; then
			echo "Error: Failed to build Docker image after $max_retries attempts"
			rm -f Dockerfile.tmp
			exit 1
		fi
		echo "Retrying Docker build (attempt $((retry_count + 1))/$max_retries)..."
		sleep 5
	done
	
	# 运行容器并复制包（带重试）
	retry_count=0
	while [ $retry_count -lt $max_retries ]; do
		if docker run --rm -v ${package_dir}/wheels:/wheels plugin-builder cp -r /wheels/* /wheels/; then
			break
		fi
		retry_count=$((retry_count + 1))
		if [ $retry_count -eq $max_retries ]; then
			echo "Error: Failed to copy packages from Docker container after $max_retries attempts"
			rm -f Dockerfile.tmp
			exit 1
		fi
		echo "Retrying package copy (attempt $((retry_count + 1))/$max_retries)..."
		sleep 5
	done
	
	# 清理
	rm -f Dockerfile.tmp
	docker rmi plugin-builder
}

# 重新打包函数
repackage() {
	local PACKAGE_PATH=$1
	local PACKAGE_NAME_WITH_EXTENSION=$(basename ${PACKAGE_PATH})
	local PACKAGE_NAME=${PACKAGE_NAME_WITH_EXTENSION%.*}

	echo "Unziping ..."
	install_unzip
	unzip -o ${PACKAGE_PATH} -d ${PACKAGE_NAME}
	if [[ $? -ne 0 ]]; then
		exit 1
	fi
	echo "Unzip success."

	echo "Repackaging ..."
	cd ${PACKAGE_NAME}
	
	# 创建临时wheels目录用于新包
	rm -rf ./wheels_temp
	mkdir -p ./wheels_temp

	if [[ $USE_DOCKER == true ]]; then
		echo "Using Docker to download packages..."
		download_packages_in_docker "$(pwd)" "requirements.txt"
	else
		echo "Using local Python environment to download packages..."
		# 使用数组中的所有平台标签
		if [ ${#PLATFORM_TAGS[@]} -gt 0 ]; then
			pip download -r requirements.txt -d ./wheels_temp --index-url ${PIP_MIRROR_URL} --trusted-host mirrors.aliyun.com --pre --only-binary=:all: "${PLATFORM_TAGS[@]}"
		else
			# 如果没有指定平台，使用默认的 aarch64 平台标签
			pip download -r requirements.txt -d ./wheels_temp --index-url ${PIP_MIRROR_URL} --trusted-host mirrors.aliyun.com --pre --only-binary=:all: \
				--platform=manylinux_2_17_aarch64 \
				--platform=manylinux2014_aarch64 \
				--platform=manylinux_2_28_aarch64 \
				--platform=manylinux_2_39_aarch64
		fi
	fi
	
	# 如果下载成功，合并wheels目录
	if [[ $? -eq 0 ]]; then
		# 如果原wheels目录不存在，重命名临时目录
		if [[ ! -d ./wheels ]]; then
			mv ./wheels_temp ./wheels
		else
			# 如果原wheels目录存在，合并内容
			cp -rf ./wheels_temp/* ./wheels/
			rm -rf ./wheels_temp
		fi
	else
		rm -rf ./wheels_temp
		exit 1
	fi

	if [[ "linux" == "${OS_TYPE}" ]]; then
		sed -i '1i--no-index --find-links=./wheels/' requirements.txt
	elif [[ "darwin" == "${OS_TYPE}" ]]; then
		sed -i .bak '1i\
--no-index --find-links=./wheels/
		  ' requirements.txt
		rm -f requirements.txt.bak
	fi

	IGNORE_PATH=.difyignore
	if [ ! -f .difyignore ]; then
		IGNORE_PATH=.gitignore
	fi

	cd ${CURR_DIR}
	chmod 755 ${CURR_DIR}/${CMD_NAME}
	${CURR_DIR}/${CMD_NAME} plugin package ${PACKAGE_NAME} -o ${PACKAGE_NAME}-${PACKAGE_SUFFIX}.difypkg
	echo "Repackage success."
	exit 0
}

# 从市场下载插件
market() {
	local PLUGIN_ID=$1
	local PLUGIN_VERSION=$2
	local PLUGIN_PACKAGE_PATH=""

	if [[ -z "$PLUGIN_ID" ]]; then
		echo "Error: PLUGIN_ID is required for market action"
		exit 1
	fi

	if [[ -z "$PLUGIN_VERSION" ]]; then
		echo "Error: PLUGIN_VERSION is required for market action"
		exit 1
	fi

	echo "Downloading plugin from market ..."
	PLUGIN_PACKAGE_PATH=$(curl -s -X GET "${MARKETPLACE_API_URL}/api/v1/plugins/${PLUGIN_ID}/versions/${PLUGIN_VERSION}/download" -H "accept: application/json" | jq -r '.data.url')
	if [[ -z "$PLUGIN_PACKAGE_PATH" ]]; then
		echo "Download plugin package failed."
		exit 1
	fi

	repackage ${PLUGIN_PACKAGE_PATH}
}

DEFAULT_GITHUB_API_URL=https://github.com
DEFAULT_MARKETPLACE_API_URL=https://marketplace.dify.ai
DEFAULT_PIP_MIRROR_URL=https://mirrors.aliyun.com/pypi/simple

GITHUB_API_URL="${GITHUB_API_URL:-$DEFAULT_GITHUB_API_URL}"
MARKETPLACE_API_URL="${MARKETPLACE_API_URL:-$DEFAULT_MARKETPLACE_API_URL}"
PIP_MIRROR_URL="${PIP_MIRROR_URL:-$DEFAULT_PIP_MIRROR_URL}"

CURR_DIR=`dirname $0`
cd $CURR_DIR
CURR_DIR=`pwd`
USER=`whoami`
ARCH_NAME=`uname -m`
OS_TYPE=$(uname)
OS_TYPE=$(echo "$OS_TYPE" | tr '[:upper:]' '[:lower:]')

# 默认架构设置
CMD_NAME="dify-plugin-${OS_TYPE}-amd64-5g"
if [[ "arm64" == "$ARCH_NAME" || "aarch64" == "$ARCH_NAME" ]]; then
	CMD_NAME="dify-plugin-${OS_TYPE}-arm64-5g"
fi

PIP_PLATFORM=""
PACKAGE_SUFFIX="offline"
PLATFORM_TAGS=""
USE_DOCKER=false
DOCKER_IMAGE=""

# 保存所有参数
ALL_ARGS=("$@")

# 处理位置参数
if [[ $# -lt 2 ]]; then
	echo "Usage: $0 [local|market] PACKAGE_PATH [-p PLATFORM] [-s SUFFIX]"
	exit 1
fi

ACTION=$1
PACKAGE_PATH=$2
shift 2

# 处理选项参数
while getopts "p:s:" opt; do
	case $opt in
		p)
			set_platform_tags "$OPTARG"
			;;
		s)
			PACKAGE_SUFFIX="${OPTARG}"
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done

case "$ACTION" in
	local)
		if [[ -z "$PACKAGE_PATH" ]]; then
			echo "Error: PACKAGE_PATH is required for local action"
			exit 1
		fi
		repackage "$PACKAGE_PATH"
		;;
	market)
		if [[ -z "$PACKAGE_PATH" ]]; then
			echo "Error: PACKAGE_PATH is required for market action"
			exit 1
		fi
		market "$PACKAGE_PATH"
		;;
	*)
		echo "Error: Invalid action. Use 'local' or 'market'"
		exit 1
		;;
esac
