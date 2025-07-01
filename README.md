## Dify 1.0 插件下载与重打包工具


### 环境要求

操作系统支持: Linux amd64/aarch64, MacOS x86_64/arm64

**注意事项**: 本脚本使用 `yum` 安装 `unzip` 命令，这只适用于基于 RPM 的 Linux 系统（如 `Red Hat Enterprise Linux`、`CentOS`、`Fedora` 和 `Oracle Linux`），并且在较新的发行版中已被 `dnf` 所替代。如果您使用其他 Linux 发行版，请提前安装 `unzip` 命令。

Python 版本要求：需要与 `dify-plugin-daemon` 相同，目前为 3.12.x


#### 克隆仓库
```shell
git clone https://github.com/junjiem/dify-plugin-repackaging.git
```

### 命令使用说明

本脚本支持三种主要操作：本地重打包、市场插件下载重打包和跨平台打包。

#### 基本命令结构

```shell
./plugin_repackaging.sh <操作类型> <包路径> [-p 平台] [-s 后缀]
```

参数说明：
- `操作类型`: 可选 `local`（本地）或 `market`（市场）
- `包路径`: 插件包的路径或插件ID（市场操作时）
- `-p 平台`: （可选）目标平台标识，用于跨平台打包
- `-s 后缀`: （可选）输出包名的自定义后缀

#### 1. 本地插件包重打包

本地插件包重打包的使用方法：

```shell
# 基本用法
./plugin_repackaging.sh local ./plugin.difypkg

# 针对 x86_64/amd64 平台
./plugin_repackaging.sh local ./plugin.difypkg -p manylinux2014_x86_64 -s linux-amd64

# 针对 ARM64/aarch64 平台
./plugin_repackaging.sh local ./plugin.difypkg -p manylinux2014_aarch64 -s linux-arm64
```

#### 2. 市场插件下载与重打包

从 Dify 市场下载并重打包插件：

```shell
# 基本用法
./plugin_repackaging.sh market <插件ID> <版本号>

# 示例
./plugin_repackaging.sh market langgenius-google 0.0.9

# 指定平台的打包示例
./plugin_repackaging.sh market langgenius-google 0.0.9 -p manylinux2014_x86_64 -s linux-amd64
```

#### 3. 跨平台打包说明

脚本通过 `-p` 选项支持跨平台打包。常用平台标识如下：

x86_64/amd64 平台标识：
- manylinux_2_17_x86_64
- manylinux2014_x86_64
- manylinux_2_28_x86_64
- manylinux_2_39_x86_64

ARM64/aarch64 平台标识：
- manylinux_2_17_aarch64
- manylinux2014_aarch64
- manylinux_2_28_aarch64
- manylinux_2_39_aarch64

使用示例：
```shell
# 用于 x86_64 Linux
./plugin_repackaging.sh local ./plugin.difypkg -p manylinux2014_x86_64 -s linux-amd64

# 用于 ARM64 Linux
./plugin_repackaging.sh local ./plugin.difypkg -p manylinux2014_aarch64 -s linux-arm64

# 使用特定平台标识和自定义后缀
./plugin_repackaging.sh local ./plugin.difypkg -p manylinux_2_17_x86_64 -s custom-suffix
```

### Dify 平台环境配置说明

要允许安装未上架插件和大型插件，需要修改以下配置：

- 在 `.env` 配置文件中将 `FORCE_VERIFYING_SIGNATURE` 改为 `false`，Dify 平台将允许安装所有未在 Dify Marketplace 上架（审核）的插件。

- 在 `.env` 配置文件中将 `PLUGIN_MAX_PACKAGE_SIZE` 增大为 `524288000`，Dify 平台将允许安装 500M 大小以内的插件。

- 在 `.env` 配置文件中将 `NGINX_CLIENT_MAX_BODY_SIZE` 增大为 `500M`，Nginx 客户端将允许上传 500M 大小以内的内容。

### 本地插件安装方法

访问 Dify 平台的插件管理页面，选择"本地插件包"方式完成安装。

![install_plugin_via_local](./images/install_plugin_via_local.png)

### Star History

[![Star History Chart](https://api.star-history.com/svg?repos=junjiem/dify-plugin-repackaging&type=Date)](https://star-history.com/#junjiem/dify-plugin-repackaging&Date)

