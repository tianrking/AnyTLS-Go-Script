[![DigitalOcean Referral Badge](https://web-platforms.sfo2.cdn.digitaloceanspaces.com/WWW/Badge%203.svg)](https://www.digitalocean.com/?refcode=9b9563b5b0b2&utm_campaign=Referral_Invite&utm_medium=Referral_Program&utm_source=badge)

🚀 速来拼好模，智谱 GLM Coding 超值订阅，邀你一起薅羊毛！Claude Code、Cline 等 20+ 大编程工具无缝支持，“码力”全开，越拼越爽！立即开拼，享限时惊喜价！
      链接：https://www.bigmodel.cn/glm-coding?ic=QJ82Z7R8YK

# AnyTLS-Go 一键安装管理脚本

## 主要功能

* **一键安装/更新**：快速部署最新指定版本 (v0.0.12) 的 `anytls-go` 服务端。
* **自动化依赖处理**：自动检测并安装 `wget`, `unzip`, `curl`, `qrencode` 等必要工具。
* **Systemd 服务管理**：
    * 开机自启
    * 通过 `systemctl` 控制服务的启动、停止、重启
    * 方便地查看服务状态和日志
* **交互式配置**：引导用户设置监听端口和连接密码。
* **二维码生成**：自动为 NekoBox 和 Shadowrocket 生成配置二维码，方便移动端导入。
* **轻松卸载**：提供完整的卸载选项，移除程序和服务文件。
* **架构自动识别**：支持 `amd64 (x86_64)` 和 `arm64 (aarch64)` 架构的 Linux VPS。

## 先决条件

* 一台 Linux VPS（建议使用 Debian, Ubuntu, CentOS 等常见发行版）。
* 拥有 `sudo` 或 `root` 用户权限。
* VPS 已连接到互联网，以便下载所需文件。

## 如何使用

### 1. 下载脚本

你可以通过以下任一命令下载脚本：

```bash
wget -O anytls_manager.sh https://raw.githubusercontent.com/ZedRover/AnyTLS-Go-Script/refs/heads/main/anytls_manager.sh
````

或者

```bash
curl -o anytls_manager.sh -L https://raw.githubusercontent.com/ZedRover/AnyTLS-Go-Script/refs/heads/main/anytls_manager.sh
```

### 2\. 赋予执行权限

```bash
chmod +x anytls_manager.sh
```

### 3\. 运行脚本

通过以下命令与脚本交互：

  * **显示帮助菜单**:

    ```bash
    ./anytls_manager.sh help
    ```

    或者直接运行 `./anytls_manager.sh`

    ![media/help.png](media/help.png)


  * **安装或更新 AnyTLS-Go 服务**:

    ```bash
    sudo ./anytls_manager.sh install
    ```

    脚本会引导你完成端口和密码的设置。

  * **卸载 AnyTLS-Go 服务**:

    ```bash
    sudo ./anytls_manager.sh uninstall
    ```

  * **启动服务**:

    ```bash
    sudo ./anytls_manager.sh start
    ```

  * **停止服务**:

    ```bash
    sudo ./anytls_manager.sh stop
    ```

  * **重启服务**:

    ```bash
    sudo ./anytls_manager.sh restart
    ```

  * **查看服务状态**:

    ```bash
    ./anytls_manager.sh status
    ```

  * **查看服务日志**:

    ```bash
    ./anytls_manager.sh log
    ```

    你还可以附加 `journalctl` 的参数，例如查看最新的100行日志：`./anytls_manager.sh log -n 100`

  * **重新生成二维码**:

    ```bash
    ./anytls_manager.sh qr
    ```

    此命令会要求你输入之前设置的密码。
    
    ![media/qr.png](media/qr.png)

## 支持的客户端

以下是一些已知支持 AnyTLS 协议并可与本脚本搭建的 `anytls-go` 服务端配合使用的客户端软件：

* **Shadowrocket** (iOS):
    * 版本 `2.2.65` 及更高版本。
    * 本脚本可为其生成二维码。
* **NekoBox For Android** (Android):
    * 版本 `1.3.8` 及更高版本。
    * 本脚本可为其生成二维码。
* **sing-box** (多平台):
    * 内核及基于 sing-box 的客户端通常支持 AnyTLS。可手动配置。
    * GitHub: [SagerNet/sing-box](https://github.com/SagerNet/sing-box)
* **mihomo (Clash Meta 内核)** (多平台):
    * 内核及基于 mihomo (Clash Meta) 的客户端通常支持 AnyTLS。可手动配置。
    * GitHub: [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo)
* 其他基于上述内核并实现了 AnyTLS 协议的客户端。

**请注意**：使用 `anytls-go` 搭建的服务端采用自签名证书，因此在客户端配置时，通常需要启用“允许不安全连接”或“跳过证书验证”等选项。


## 免责声明

  * 本脚本仅供学习和技术研究使用，请勿用于任何非法用途。
  * 用户在使用本脚本搭建代理服务时，应自行承担一切风险，并确保遵守当地的法律法规。
  * 对于因使用本脚本而可能产生的任何问题或纠纷，脚本作者概不负责。


