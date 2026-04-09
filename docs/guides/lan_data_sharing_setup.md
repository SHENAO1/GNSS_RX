# 局域网数据共享配置指南

> 创建时间：2026-03-30  
> 目的：让 Windows MATLAB 主机通过局域网直接挂载 Linux 工作站的采集目录，替代旧的 VMware 共享文件夹方案  
> 关联文件：`matlab/functions/gnss_rx_resolve_data_dir.m`、`matlab/gnss_rx_user_paths.m.example`

---

## 一、适用场景

本指南适用于以下硬件拓扑：

- **两台 Linux 工作站**（工作站 A / 工作站 B），各连接一台 Ettus X310，用于 GNSS 信号采集
- **一台 Windows 主机**，运行 MATLAB，负责离线 BER 分析
- 三台设备通过同一局域网互联

旧方案依赖 VMware 共享文件夹（`/mnt/hgfs/GongXiangDocument/`），在裸机工作站环境下不再适用。

---

## 二、方案选择

| | 方案 A：SSHFS-Win | 方案 B：Samba |
|---|---|---|
| Linux 端需要改动 | **零改动**，只需 SSH 可访问 | 需要 root：安装、改系统配置、改防火墙 |
| Windows 端需要安装 | WinFsp + SSHFS-Win | 无（内置 SMB 客户端） |
| 适合公用工作站 | **是** | 否（影响其他用户） |
| 适合独占工作站 | 是 | 是（性能略好） |
| 安全性 | SSH 加密，无需额外配置 | 需要单独配置访问控制 |

### 推荐：方案 A（SSHFS-Win）

公用工作站上安装 Samba 存在以下风险：

- 需要 sudo 权限修改 `/etc/samba/smb.conf`（系统级文件，改动影响所有用户）
- 需要开放防火墙端口（影响整台机器的网络暴露面）
- 配置不当可能意外暴露同机其他用户的目录
- 445 端口可能已被管理员的 Samba 配置占用

只要你在工作站上有一个可写的数据目录，SSHFS-Win 就能工作，对其他用户零影响。

---

## 三、网络拓扑

| 角色 | 系统 | Windows 挂载盘符 | IP（填写实际值） |
|---|---|---|---|
| 工作站 A | Ubuntu 22.04 | `Z:` | `<WS_A_IP>` |
| 工作站 B | Ubuntu 22.04 | `Y:` | `<WS_B_IP>` |
| MATLAB 主机 | Windows 11 | — | `<WIN_IP>` |

> 建议将工作站 IP 固定（路由器绑定 MAC → IP），避免重启后地址变更导致挂载断开。

---

## 四、方案 A：SSHFS-Win（推荐）

### 4.1 前提确认

在 Windows 上验证 SSH 连接正常：

```powershell
ssh <USERNAME>@<WS_A_IP> "echo ok"
```

若提示无法连接，检查工作站的 SSH 服务状态：

```bash
# 在工作站上执行
sudo systemctl status ssh
```

### 4.2 Linux 工作站端（无需任何改动）

只需确认你的数据目录存在且可写：

```bash
# 确认采集输出目录（record_rx.py 默认写到这里）
ls ~/projects/GNSS_RX/results/
```

无需安装任何软件，无需修改任何系统配置。

### 4.3 Windows 端安装

依次安装以下两个 `.msi`（普通用户权限即可）：

1. **WinFsp**：[winfsp.dev/rel](https://winfsp.dev/rel/) — 用户态文件系统驱动
2. **SSHFS-Win**：[github.com/winfsp/sshfs-win/releases](https://github.com/winfsp/sshfs-win/releases)

### 4.4 挂载方式

**图形界面（文件资源管理器）：**

右键「此电脑」→「映射网络驱动器」，文件夹填写：

```
\\sshfs\<USERNAME>@<WS_A_IP>\home\<USERNAME>\projects\GNSS_RX\results
```

工作站 B 同理，选用 `Y:` 盘符：

```
\\sshfs\<USERNAME>@<WS_B_IP>\home\<USERNAME>\projects\GNSS_RX\results
```

**命令行（PowerShell，便于脚本化）：**

```powershell
# 挂载工作站 A → Z:
net use Z: \\sshfs\<USERNAME>@<WS_A_IP>\home\<USERNAME>\projects\GNSS_RX\results /persistent:yes

# 挂载工作站 B → Y:
net use Y: \\sshfs\<USERNAME>@<WS_B_IP>\home\<USERNAME>\projects\GNSS_RX\results /persistent:yes

# 验证
net use
```

> `/persistent:yes` 配合 SSH 密钥认证（见 4.5）可实现开机自动重连，无需每次输入密码。

### 4.5 配置 SSH 密钥（推荐，避免每次输密码）

```powershell
# 在 Windows 上生成密钥（若已有可跳过）
ssh-keygen -t ed25519 -C "matlab-host"

# 将公钥添加到工作站 A（需要一次密码）
ssh-copy-id <USERNAME>@<WS_A_IP>

# 工作站 B 同理
ssh-copy-id <USERNAME>@<WS_B_IP>
```

---

## 五、MATLAB 路径配置

`matlab/functions/gnss_rx_resolve_data_dir.m` 按以下优先级解析数据目录：

1. `matlab/gnss_rx_user_paths.m`（本地配置，不纳入 git）
2. 环境变量 `GNSS_RX_DATA_DIR`
3. 平台默认路径（VMware 路径，已过时）

**新环境只需修改优先级 1**，不需要改任何 MATLAB 分析脚本。

### 5.1 配置步骤

在 Windows MATLAB 主机上，将模板复制为本地配置文件：

```
复制 matlab\gnss_rx_user_paths.m.example
粘贴为 matlab\gnss_rx_user_paths.m
```

修改路径，指向已挂载的盘符：

```matlab
% 工作站 A 的数据目录（Z: 盘）
GNSS_RX_DATA_DIR = 'Z:\';
```

若需要切换到工作站 B，修改盘符即可：

```matlab
GNSS_RX_DATA_DIR = 'Y:\';
```

或在 MATLAB 工作区临时切换，不修改文件：

```matlab
setenv('GNSS_RX_DATA_DIR', 'Y:\');
```

### 5.2 数据目录命名规范

两台工作站的 `results/` 目录下应保持相同的子目录结构：

```
results/
└── <YYYY>/
    └── <YYYY_MM_DD>/
        └── <stem>/
            ├── <stem>.sc16
            ├── <stem>.json
            └── <stem>_tx_truth.json   （可选，BER 分析用）
```

---

## 六、MATLAB 代码同步

`scripts/sync_matlab.sh` 旧的 VMware 目标路径已不再适用。推荐替代方式：

**方式 A（推荐）：直接使用 git**  
MATLAB 代码已通过 git 版本管理，Windows 主机上 `git pull` 即可获取最新代码，无需 `sync_matlab.sh`。

**方式 B：rsync 推送到 Windows**  
需要 Windows 主机开启 OpenSSH Server（Windows 11 内置，在「设置 → 系统 → 可选功能」中启用）：

```bash
# 在 Linux 工作站上执行
./scripts/sync_matlab.sh <WIN_USERNAME>@<WIN_IP>:/c/Users/<WIN_USERNAME>/projects/GNSS_RX/matlab
```

---

## 七、验证步骤

```bash
# 1. Linux 工作站：确认数据目录有文件
ls ~/projects/GNSS_RX/results/
```

```powershell
# 2. Windows：确认挂载正常
net use Z:
dir Z:\
```

```matlab
% 3. MATLAB：确认路径解析
data_dir = gnss_rx_resolve_data_dir()
% 应输出 'Z:\' 或你填写的路径

% 4. 运行 BER 分析
CAPTURE_PATH = 'Z:\2026\2026_03_30\<stem>\<stem>.json';
run('scripts/run_ber_loopback.m')
```

---

## 八、常见问题排查

### SSHFS 挂载后访问很慢

SSH 加密有开销，大文件（>1GB）首次加载会比本地慢。可在 `ssh_config` 中启用压缩或使用更快的加密算法：

```text
# C:\Users\<USERNAME>\.ssh\config
Host <WS_A_IP>
    Compression yes
    Ciphers aes128-gcm@openssh.com
```

### 重启后挂载断开

配合 SSH 密钥认证（见 4.5）并在映射时勾选「登录时重新连接」。若仍断开，检查工作站 SSH 服务是否开机自启：

```bash
sudo systemctl enable ssh
```

### Windows 凭据缓存问题

在「凭据管理器」中删除旧的 `sshfs` 相关条目后重新挂载。

### 文件路径含空格

MATLAB 对含空格的路径处理有限。建议数据目录和 stem 命名全程不含空格（`record_rx.py` 自动生成的 stem 已满足此要求）。

---

## 九、方案 B：Samba（仅适用于独占工作站）

> **公用工作站请跳过本节**，直接使用方案 A。

仅当工作站由你独占管理（有 root 权限且不影响他人）时，Samba 可作为性能略好的备选方案。

### 9.1 安装与配置

```bash
sudo apt update && sudo apt install -y samba

# 在 /etc/samba/smb.conf 末尾追加
sudo tee -a /etc/samba/smb.conf << 'EOF'

[gnss_data]
   path = /home/<USERNAME>/projects/GNSS_RX/results
   browseable = yes
   writable = yes
   valid users = <USERNAME>
EOF

sudo smbpasswd -a <USERNAME>
sudo ufw allow samba
sudo systemctl restart smbd nmbd
```

### 9.2 Windows 端映射

```powershell
net use Z: \\<WS_A_IP>\gnss_data /user:<USERNAME> <PASSWORD> /persistent:yes
```

### 9.3 MATLAB 配置

与方案 A 完全相同，`gnss_rx_user_paths.m` 中设置 `GNSS_RX_DATA_DIR = 'Z:\'`。
