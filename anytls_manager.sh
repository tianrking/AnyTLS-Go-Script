#!/bin/bash

# AnyTLS-Go 服务端一键管理脚本
# 版本: v0.0.12 (基于 anytls/anytls-go)

# --- 全局配置参数 ---
ANYTLS_VERSION="v0.0.12"
BASE_URL="https://github.com/anytls/anytls-go/releases/download"
INSTALL_DIR_TEMP="/tmp/anytls_install_$$" # 使用 $$ 增加随机性
BIN_DIR="/usr/local/bin"
SERVER_BINARY_NAME="anytls-server"
SERVER_BINARY_PATH="${BIN_DIR}/${SERVER_BINARY_NAME}"
SERVICE_FILE_BASENAME="anytls-server.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_FILE_BASENAME}"

# --- 工具函数 ---

# 检查命令是否存在
check_command() {
  command -v "$1" >/dev/null 2>&1
}

# 安装必要的软件包
install_packages() {
  local packages_to_install=("$@")
  if [ ${#packages_to_install[@]} -eq 0 ]; then
    return 0
  fi
  echo "正在尝试安装必要的软件包: ${packages_to_install[*]}"
  if check_command apt-get; then
    apt-get update -qq && apt-get install -y -qq "${packages_to_install[@]}"
  elif check_command yum; then
    yum install -y -q "${packages_to_install[@]}"
  elif check_command dnf; then
    dnf install -y -q "${packages_to_install[@]}"
  else
    echo "错误：无法确定系统的包管理器。请手动安装: ${packages_to_install[*]}"
    return 1
  fi
  for pkg in "${packages_to_install[@]}"; do
    if ! check_command "$pkg"; then
      echo "错误：软件包 $pkg 安装失败。"
      return 1
    fi
  done
  echo "软件包 ${packages_to_install[*]} 安装成功。"
  return 0
}

# URL 编码函数
urlencode() {
    local string="${1}"
    local strlen=${#string}
    local encoded=""
    local pos c o
    for (( pos=0 ; pos<strlen ; pos++ )); do
       c=${string:$pos:1}
       case "$c" in
          [-_.~a-zA-Z0-9] ) o="${c}" ;;
          * )               printf -v o '%%%02x' "'$c"
       esac
       encoded+="${o}"
    done
    echo "${encoded}"
}

# 获取公网 IP 地址
get_public_ip() {
  echo "正在尝试获取服务器公网IP地址..." >&2 # Output to stderr
  local IP_CANDIDATES=()
  IP_CANDIDATES+=("$(curl -s --max-time 8 --ipv4 https://api.ipify.org)")
  IP_CANDIDATES+=("$(curl -s --max-time 8 --ipv4 https://ipinfo.io/ip)")
  IP_CANDIDATES+=("$(curl -s --max-time 8 --ipv4 https://checkip.amazonaws.com)")
  IP_CANDIDATES+=("$(curl -s --max-time 8 --ipv4 https://icanhazip.com)")
  
  local valid_ip=""
  for ip_candidate in "${IP_CANDIDATES[@]}"; do
    if [[ "$ip_candidate" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      if ! [[ "$ip_candidate" =~ ^10\. ]] && \
         ! [[ "$ip_candidate" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && \
         ! [[ "$ip_candidate" =~ ^192\.168\. ]] && \
         ! [[ "$ip_candidate" =~ ^127\. ]]; then
        valid_ip="$ip_candidate"
        break
      fi
    fi
  done

  if [ -n "$valid_ip" ]; then
    echo "$valid_ip"
    return 0
  else
    local local_ips
    local_ips=$(hostname -I 2>/dev/null)
    if [ -n "$local_ips" ]; then
        for ip_candidate in $local_ips; do
             if [[ "$ip_candidate" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                if ! [[ "$ip_candidate" =~ ^10\. ]] && \
                   ! [[ "$ip_candidate" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && \
                   ! [[ "$ip_candidate" =~ ^192\.168\. ]] && \
                   ! [[ "$ip_candidate" =~ ^127\. ]]; then
                    echo "$ip_candidate"
                    echo "警告: 上述IP地址通过 'hostname -I' 获取，请确认其为公网IP。" >&2
                    return 0
                fi
            fi
        done
    fi
    echo "" # Return empty if no IP found
    return 1
  fi
}

# 清理临时文件
cleanup_temp() {
  if [ -d "$INSTALL_DIR_TEMP" ]; then
    echo "正在清理临时安装目录: $INSTALL_DIR_TEMP..." >&2
    rm -rf "$INSTALL_DIR_TEMP"
  fi
}
trap cleanup_temp EXIT SIGINT SIGTERM # Ensure cleanup on exit

# 检查root权限
require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误：此操作 '$1' 需要 root 权限。请使用 'sudo $0 $1' 再次尝试。"
        exit 1
    fi
}

# --- 服务管理与安装卸载函数 ---

do_install() {
    require_root "install"
    echo "开始安装/更新 AnyTLS-Go 服务 (目标版本: ${ANYTLS_VERSION})..."
    echo "=================================================="

    read -r -p "请输入 AnyTLS 服务端监听端口 (默认 8443): " ANYTLS_PORT
    ANYTLS_PORT=${ANYTLS_PORT:-8443}
    if ! [[ "$ANYTLS_PORT" =~ ^[0-9]+$ ]] || [ "$ANYTLS_PORT" -lt 1 ] || [ "$ANYTLS_PORT" -gt 65535 ]; then
        echo "错误：端口号 \"$ANYTLS_PORT\" 无效。"
        exit 1
    fi

    local ANYTLS_PASSWORD ANYTLS_PASSWORD_CONFIRM
    while true; do
      read -r -s -p "请输入 AnyTLS 服务端密码 (必须填写): " ANYTLS_PASSWORD
      echo
      if [ -z "$ANYTLS_PASSWORD" ]; then echo "错误：密码不能为空，请重新输入。"; continue; fi
      read -r -s -p "请再次输入密码以确认: " ANYTLS_PASSWORD_CONFIRM
      echo
      if [ "$ANYTLS_PASSWORD" == "$ANYTLS_PASSWORD_CONFIRM" ]; then break; else echo "两次输入的密码不一致，请重新输入。"; fi
    done

    local deps_to_install=()
    if ! check_command wget; then deps_to_install+=("wget"); fi
    if ! check_command unzip; then deps_to_install+=("unzip"); fi
    if ! check_command curl; then deps_to_install+=("curl"); fi
    if ! check_command qrencode; then deps_to_install+=("qrencode"); fi
    if ! install_packages "${deps_to_install[@]}"; then echo "依赖安装失败，无法继续。"; exit 1; fi

    local ARCH_RAW ANYTLS_ARCH
    ARCH_RAW=$(uname -m)
    case $ARCH_RAW in
      x86_64 | amd64) ANYTLS_ARCH="amd64" ;;
      aarch64 | arm64) ANYTLS_ARCH="arm64" ;;
      *) echo "错误: 不支持的系统架构 ($ARCH_RAW)。"; exit 1 ;;
    esac
    echo "检测到系统架构: $ANYTLS_ARCH"

    local VERSION_FOR_FILENAME FILENAME DOWNLOAD_URL
    VERSION_FOR_FILENAME=${ANYTLS_VERSION#v}
    FILENAME="anytls_${VERSION_FOR_FILENAME}_linux_${ANYTLS_ARCH}.zip"
    DOWNLOAD_URL="${BASE_URL}/${ANYTLS_VERSION}/${FILENAME}"

    mkdir -p "$INSTALL_DIR_TEMP"
    echo "正在从 $DOWNLOAD_URL 下载 AnyTLS-Go..."
    if ! wget -q -O "${INSTALL_DIR_TEMP}/${FILENAME}" "$DOWNLOAD_URL"; then
      echo "错误: 下载 AnyTLS-Go 失败。"; exit 1
    fi

    echo "正在解压文件到 $INSTALL_DIR_TEMP ..."
    if ! unzip -q -o "${INSTALL_DIR_TEMP}/${FILENAME}" -d "$INSTALL_DIR_TEMP"; then
      echo "错误: 解压 AnyTLS-Go 失败。"; exit 1
    fi
    if [ ! -f "${INSTALL_DIR_TEMP}/${SERVER_BINARY_NAME}" ]; then
        echo "错误: 解压后未找到 ${SERVER_BINARY_NAME}。"; exit 1
    fi

    echo "正在安装服务端程序到 ${SERVER_BINARY_PATH} ..."
    if systemctl is-active --quiet "${SERVICE_FILE_BASENAME}"; then # Stop service before replacing binary
        systemctl stop "${SERVICE_FILE_BASENAME}"
    fi
    if ! mv "${INSTALL_DIR_TEMP}/${SERVER_BINARY_NAME}" "${SERVER_BINARY_PATH}"; then
      echo "错误: 移动 ${SERVER_BINARY_NAME} 失败。"; exit 1
    fi
    chmod +x "${SERVER_BINARY_PATH}"

    echo "正在创建/更新 systemd 服务文件: ${SERVICE_FILE} ..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=AnyTLS Server Service (Version ${ANYTLS_VERSION})
Documentation=https://github.com/anytls/anytls-go
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${SERVER_BINARY_PATH} -l 0.0.0.0:${ANYTLS_PORT} -p "${ANYTLS_PASSWORD}"
Restart=on-failure
RestartSec=10s
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    echo "正在重载 systemd 配置并启动 AnyTLS 服务..."
    systemctl daemon-reload
    if ! systemctl enable "${SERVICE_FILE_BASENAME}"; then echo "错误：设置开机自启失败。"; exit 1; fi
    if ! systemctl restart "${SERVICE_FILE_BASENAME}"; then # Use restart to ensure it starts fresh
        echo "错误：启动/重启 AnyTLS 服务失败。请检查日志。"; status_service; log_service -n 20; exit 1;
    fi
    
    sleep 2
    if systemctl is-active --quiet "${SERVICE_FILE_BASENAME}"; then
        echo ""
        echo "🎉 AnyTLS 服务已成功安装/更新并启动！🎉"
        local SERVER_IP
        SERVER_IP=$(get_public_ip)
        generate_and_display_qr_codes "${SERVER_IP}" "${ANYTLS_PORT}" "${ANYTLS_PASSWORD}" "install"
        display_manage_commands
    else
        echo "错误: AnyTLS 服务未能成功启动。"; status_service; log_service -n 20;
    fi
}

do_uninstall() {
    require_root "uninstall"
    echo "正在卸载 AnyTLS-Go 服务..."
    if systemctl list-unit-files | grep -q "${SERVICE_FILE_BASENAME}"; then
        systemctl stop "${SERVICE_FILE_BASENAME}"
        systemctl disable "${SERVICE_FILE_BASENAME}"
        rm -f "${SERVICE_FILE}"
        echo "Systemd 服务文件 ${SERVICE_FILE} 已移除。"
        systemctl daemon-reload
        systemctl reset-failed # Important for cleaning up failed state
        echo "Systemd 配置已重载。"
    else
        echo "未找到 AnyTLS-Go Systemd 服务。"
    fi

    if [ -f "${SERVER_BINARY_PATH}" ]; then
        rm -f "${SERVER_BINARY_PATH}"
        echo "服务端程序 ${SERVER_BINARY_PATH} 已移除。"
    else
        echo "未找到服务端程序 ${SERVER_BINARY_PATH}。"
    fi
    # Consider removing /etc/anytls-server if config files were stored there. Not in this script.
    echo "AnyTLS-Go 服务卸载完成。"
}

start_service() { require_root "start"; echo "正在启动 AnyTLS 服务..."; systemctl start "${SERVICE_FILE_BASENAME}"; sleep 1; status_service; }
stop_service() { require_root "stop"; echo "正在停止 AnyTLS 服务..."; systemctl stop "${SERVICE_FILE_BASENAME}"; sleep 1; status_service; }
restart_service() { require_root "restart"; echo "正在重启 AnyTLS 服务..."; systemctl restart "${SERVICE_FILE_BASENAME}"; sleep 1; status_service; }
status_service() { echo "AnyTLS 服务状态:"; systemctl status "${SERVICE_FILE_BASENAME}" --no-pager; }
log_service() { echo "显示 AnyTLS 服务日志 (按 Ctrl+C 退出):"; journalctl -u "${SERVICE_FILE_BASENAME}" -f "$@"; }

generate_and_display_qr_codes() {
    local server_ip="$1"
    local server_port="$2"
    local server_password="$3"
    local source_action="$4" # "install" or "qr"

    if [ -z "$server_ip" ] || [ "$server_ip" == "YOUR_SERVER_IP" ]; then # YOUR_SERVER_IP is a placeholder
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "!! 警告: 未能自动获取到服务器的公网 IP 地址。            !!"
        if [ "$source_action" == "install" ]; then
            echo "!! 二维码和分享链接中的IP将为空。请手动填写。              !!"
        else # qr action
            echo "!! 请手动获取公网IP并在客户端配置。                      !!"
        fi
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        if [ "$source_action" == "qr" ] && [ "$server_ip" == "YOUR_SERVER_IP" ]; then return 1; fi # Abort QR if IP is placeholder from qr action
        server_ip="YOUR_SERVER_IP" # Use placeholder for URI if install
    fi
    
    echo "-----------------------------------------------"
    echo "【客户端配置信息】"
    echo "  服务器地址  : ${server_ip}"
    echo "  服务器端口  : ${server_port}"
    echo "  密码        : ${server_password}"
    echo "  协议        : AnyTLS"
    echo "  注意        : anytls-go 使用自签名证书, 客户端需启用 '允许不安全' 或 '跳过证书验证'。"
    echo "-----------------------------------------------"

    if ! check_command qrencode; then
        echo "警告: 未找到 qrencode 命令，无法生成二维码。"
        echo "请尝试运行 'sudo $0 install' (会自动安装qrencode) 或手动安装 (如: sudo apt install qrencode)。"
        return 1
    fi
    
    local ENCODED_PASSWORD REMARKS NEKOBOX_URI SHADOWROCKET_URI
    ENCODED_PASSWORD=$(urlencode "${server_password}")
    REMARKS=$(urlencode "AnyTLS-${server_port}")

    NEKOBOX_URI="anytls://${ENCODED_PASSWORD}@${server_ip}:${server_port}?allowInsecure=true#${REMARKS}"
    echo ""
    echo "【NekoBox 配置链接】:"
    echo "${NEKOBOX_URI}"
    echo "【NekoBox 二维码】 (请确保终端支持UTF-8且有足够空间显示):"
    qrencode -t ANSIUTF8 -m 1 "${NEKOBOX_URI}"
    echo "-----------------------------------------------"

    SHADOWROCKET_URI="anytls://${ENCODED_PASSWORD}@${server_ip}:${server_port}#${REMARKS}"
    echo ""
    echo "【Shadowrocket 配置链接】:"
    echo "${SHADOWROCKET_URI}"
    echo "【Shadowrocket 二维码】 (请确保终端支持UTF-8且有足够空间显示):"
    qrencode -t ANSIUTF8 -m 1 "${SHADOWROCKET_URI}"
    echo "提醒: Shadowrocket用户扫描后，请在节点的TLS设置中手动开启“允许不安全”。"
    echo "-----------------------------------------------"
    return 0
}

show_qr_codes_interactive() {
    echo "重新生成配置二维码..."
    if [ ! -f "${SERVICE_FILE}" ]; then
        echo "错误: AnyTLS 服务似乎尚未安装 (未找到 ${SERVICE_FILE})。"
        echo "请先运行 'sudo $0 install'。"
        exit 1
    fi

    local deps_to_install_qr=()
    if ! check_command qrencode; then deps_to_install_qr+=("qrencode"); fi
    if ! check_command curl; then deps_to_install_qr+=("curl"); fi # For get_public_ip
    if ! install_packages "${deps_to_install_qr[@]}"; then echo "依赖安装失败，无法继续。"; exit 1; fi

    local SAVED_PORT password_for_qr server_ip_for_qr
    SAVED_PORT=$(grep -Po 'ExecStart=.*-l 0\.0\.0\.0:\K[0-9]+' "${SERVICE_FILE}" 2>/dev/null)
    if [ -z "$SAVED_PORT" ]; then
        echo "警告: 无法从服务文件中自动读取端口号。"
        read -r -p "请输入 AnyTLS 服务端当前配置的端口: " SAVED_PORT
        if ! [[ "$SAVED_PORT" =~ ^[0-9]+$ ]]; then echo "端口号无效。"; exit 1; fi
    else
        echo "从服务配置中读取到端口: ${SAVED_PORT}"
    fi
    
    read -r -s -p "请输入您为 AnyTLS 服务设置的密码: " password_for_qr; echo
    if [ -z "$password_for_qr" ]; then echo "密码不能为空。"; exit 1; fi

    server_ip_for_qr=$(get_public_ip)
    # generate_and_display_qr_codes will handle empty IP with a placeholder
    
    generate_and_display_qr_codes "${server_ip_for_qr}" "${SAVED_PORT}" "${password_for_qr}" "qr"
}

display_manage_commands() {
    echo "【常用管理命令】"
    echo "  安装/更新: sudo $0 install"
    echo "  卸载服务  : sudo $0 uninstall"
    echo "  启动服务  : sudo $0 start"
    echo "  停止服务  : sudo $0 stop"
    echo "  重启服务  : sudo $0 restart"
    echo "  服务状态  : $0 status"
    echo "  查看日志  : $0 log (可加参数如 -n 50)"
    echo "  显示二维码: $0 qr"
    echo "  查看帮助  : $0 help"
    echo "-----------------------------------------------"
}

show_help_menu() {
    echo "AnyTLS-Go 服务端管理脚本"
    echo "用法: $0 [命令]"
    echo ""
    echo "可用命令:"
    printf "  %-12s %s\n" "install" "安装或更新 AnyTLS-Go 服务 (需要sudo)"
    printf "  %-12s %s\n" "uninstall" "卸载 AnyTLS-Go 服务 (需要sudo)"
    printf "  %-12s %s\n" "start" "启动 AnyTLS-Go 服务 (需要sudo)"
    printf "  %-12s %s\n" "stop" "停止 AnyTLS-Go 服务 (需要sudo)"
    printf "  %-12s %s\n" "restart" "重启 AnyTLS-Go 服务 (需要sudo)"
    printf "  %-12s %s\n" "status" "查看服务当前状态"
    printf "  %-12s %s\n" "log" "实时查看服务日志 (例如: $0 log -n 100)"
    printf "  %-12s %s\n" "qr" "重新生成并显示配置二维码 (需要输入密码)"
    printf "  %-12s %s\n" "help" "显示此帮助菜单"
    echo ""
    echo "示例: sudo $0 install"
}


# --- 主程序入口 ---
main() {
    ACTION="$1"
    shift # Remove the first argument, so log can take its own args like -n 50

    case "$ACTION" in
        install) do_install ;;
        uninstall) do_uninstall ;;
        start) start_service ;;
        stop) stop_service ;;
        restart) restart_service ;;
        status) status_service ;;
        log) log_service "$@" ;; # Pass remaining arguments to log_service
        qr) show_qr_codes_interactive ;;
        "" | "-h" | "--help" | "help") show_help_menu ;;
        *)
            echo "错误: 无效的命令 '$ACTION'" >&2
            show_help_menu
            exit 1
            ;;
    esac
}

# 执行主函数，并传递所有命令行参数
main "$@"