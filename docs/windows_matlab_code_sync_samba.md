# Ubuntu 到 Windows 的 MATLAB 代码同步方案（Samba，代码专用）

> 创建时间：2026-03-30
> 适用场景：Ubuntu 采集机与 Windows MATLAB 主机在同一局域网；采集数据仍走本地落盘 + 移动硬盘转运；局域网只用于同步 MATLAB 代码
> 当前结论：在“只同步 MATLAB 代码、不同步采集数据”的前提下，**方案 B（Samba）通常比 SSHFS-Win 更省事**，因为 Windows 原生支持 SMB，不需要额外安装 WinFsp / SSHFS-Win

---

## 一、这份文档解决什么问题

本轮我们不打算通过局域网共享采集数据，只希望：

- Ubuntu 端维护 `GNSS_RX/matlab/` 这份代码真相源
- Windows 端能通过局域网访问或复制最新 MATLAB 代码
- 采集数据仍旧保存在 Ubuntu 本地 `~/GNSS_RX_Data_local/`
- 采集完成后，再通过移动硬盘把数据带回 Windows 主机

一句话口径：

```text
代码走局域网共享；数据走本地落盘 + 移动硬盘。
```

---

## 二、为什么当前更偏向 Samba

在本轮约束下，Samba 更可行的原因是：

- 你只需要给 Windows 暴露一个“小体量 MATLAB 代码目录”，不是高吞吐采集数据目录
- Windows 自带 SMB 客户端，不需要额外安装软件
- Ubuntu 端只要做一次系统级共享配置，后续 Windows 映射盘符比较直接
- 即使后面决定不用网络分析数据，也不影响当前采集链路

但它也有前提：

- 你对这台 Ubuntu 机器有 `sudo` 权限
- 这台 Ubuntu 机器可以接受新增一个 Samba 共享
- 该共享最好只暴露一个专用目录，不直接暴露整个 home 或整个仓库

若这些前提不满足，再退回 SSHFS-Win。

---

## 三、推荐目录设计

推荐不要直接把整个仓库共享给 Windows，而是单独准备一个“MATLAB 代码镜像目录”：

```text
/home/<USER>/GNSS_RX_matlab_share/
├── functions/
├── scripts/
├── README.md
├── architecture.drawio
├── gnss_rx_user_paths.m.example
└── ber.m
```

这个目录由 Ubuntu 端的 `scripts/sync_matlab.sh` 生成和更新。

这样做的好处是：

- Windows 只看到 MATLAB 相关文件
- 不暴露 `.venv`、实验记录、采集数据等无关目录
- 后面若要重建共享，只需要重跑一次同步脚本

---

## 四、整体流程

```text
Ubuntu 仓库源码：~/projects/GNSS_RX/matlab
    ↓
sync_matlab.sh
    ↓
Ubuntu 共享目录：~/GNSS_RX_matlab_share
    ↓
Samba 暴露为 \\<UBUNTU_IP>\gnss_rx_matlab
    ↓
Windows 挂载为 Z:
    ↓
MATLAB 从 Z:\ 读取代码，或复制到 Windows 本地目录
```

---

## 五、执行步骤

下面先给出第一版命令模板。等你把实际输出贴回来后，再把 `<...>` 占位符替换成实值。

### 5.1 Ubuntu 端：准备 MATLAB 代码镜像目录

```bash
mkdir -p ~/GNSS_RX_matlab_share
cd ~/projects/GNSS_RX
bash ./scripts/sync_matlab.sh ~/GNSS_RX_matlab_share
ls -lh ~/GNSS_RX_matlab_share
```

预期结果：

- `~/GNSS_RX_matlab_share` 被创建
- 目录下出现 `functions/`、`scripts/`、`ber.m`
- 这一步只同步代码，不会复制采集数据

本轮已实测通过，终端输出表明：

- `sync_matlab.sh` 已成功把 `matlab/` 镜像到 `/home/shenao/GNSS_RX_matlab_share`
- 已创建 `functions/`、`scripts/`
- 根目录文件已出现：`architecture.drawio`、`ber.m`、`gnss_rx_user_paths.m.example`、`README.md`

这说明“MATLAB 代码镜像目录”这一步已经完成，后续可以直接进入 Samba 安装与共享配置。

### 5.2 Ubuntu 端：安装并启用 Samba

```bash
sudo apt update
sudo apt install -y samba
sudo systemctl enable --now smbd nmbd
sudo systemctl status smbd --no-pager
```

本轮已实测通过，当前状态为：

- `smbd.service` 已 `enabled`
- `smbd.service` 已 `active (running)`
- 状态摘要为 `ready to serve connections...`

这说明 Samba 主服务已经启动成功，可以继续进入共享目录配置。

### 5.3 Ubuntu 端：追加共享配置

先备份原配置：

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak_$(date +%Y%m%d_%H%M%S)
```

然后在 `/etc/samba/smb.conf` 末尾追加：

```ini
[gnss_rx_matlab]
   path = /home/shenao/GNSS_RX_matlab_share
   browseable = yes
   read only = yes
   guest ok = no
   valid users = shenao
```

若希望 Windows 端也能往这个共享里写文件，再把 `read only = yes` 改成 `no`。当前默认建议保持只读。

### 5.4 Ubuntu 端：设置 Samba 口令并重启服务

```bash
sudo smbpasswd -a shenao
sudo systemctl restart smbd nmbd
sudo testparm -s
```

注意：

- `sudo smbpasswd -a shenao` 是交互式命令
- 终端出现 `New SMB password:` 后，会等待你输入密码
- 输入时终端**不会显示任何字符**，这是正常现象
- 需要连续输入两次同一个密码，随后命令才会继续往下执行

本轮若终端停在：

```text
New SMB password:
```

不要按 `Ctrl+C`。直接输入你想设置的 Samba 密码，回车，再按提示再输入一次同样的密码即可。

本轮已实测通过，成功标志包括：

- 终端出现 `Added user shenao.`
- `sudo testparm -s` 输出 `Loaded services file OK.`
- 配置末尾能看到：

```text
[gnss_rx_matlab]
    path = /home/shenao/GNSS_RX_matlab_share
    valid users = shenao
```

说明 Samba 用户与共享节都已生效，Ubuntu 端的共享配置已经完成。

如启用了 `ufw`，再放行 Samba：

```bash
sudo ufw allow samba
```

### 5.5 Ubuntu 端：确认本机 IP

```bash
hostname -I
```

本轮 `hostname -I` 输出了多个地址：

- `192.168.100.86`
- `100.65.171.95`
- `198.18.0.1`
- 以及若干 IPv6 地址

当前应优先使用同一家庭/办公室局域网里的 IPv4 地址：

```text
192.168.100.86
```

不要优先使用：

- `100.65.171.95` 这类 Tailscale / overlay 网络地址
- `198.18.0.1` 这类测试或虚拟接口地址
- IPv6 地址（除非 Windows 端已明确验证可达）

因此后续 Windows 端挂载命令里的 `<UBUNTU_IP>`，本轮先替换为 `192.168.100.86`。

### 5.6 Windows 端：映射网络驱动器

在 PowerShell 中执行：

```powershell
net use Z: \\192.168.100.86\gnss_rx_matlab /user:shenao <SAMBA_PASSWORD> /persistent:yes
```

注意：

- 文档里的 `<SAMBA_PASSWORD>` 只是占位符，实际执行时**不要**把尖括号 `< >` 一起输入
- 在 PowerShell 中，更稳妥的方式是直接用 `*` 让系统现场提示输入密码：

```powershell
net use Z: \\192.168.100.86\gnss_rx_matlab /user:shenao * /persistent:yes
```

- 若你确定要把密码直接写在命令行里，也应写成真实密码本身，例如 `123`，而不是 `<123>`

若挂载成功，再执行：

```powershell
net use
dir Z:\
```

预期至少能看到：

- `functions`
- `scripts`
- `ber.m`
- `README.md`

本轮已实测通过，Windows 端已成功显示：

- `Z:` 已映射到 `\\192.168.100.86\gnss_rx_matlab`
- `dir Z:\` 能看到 `functions/`、`scripts/`
- 根目录文件已可见：`architecture.drawio`、`ber.m`、`gnss_rx_user_paths.m.example`、`README.md`

这说明 Ubuntu → Samba → Windows 的 MATLAB 代码同步链路已经打通。

验证：

```powershell
net use
dir Z:\
```

预期结果：

- `Z:` 成功映射
- 能看到 `functions\`、`scripts\`、`ber.m`

### 5.7 Windows MATLAB 端：两种使用方式

方式 A：直接把网络盘作为 MATLAB 代码根目录使用

```matlab
addpath('Z:\');
addpath('Z:\functions');
addpath('Z:\scripts');
which ber -all
which run_ber_loopback -all
```

方式 B：把 `Z:\` 下的代码复制到 Windows 本地，再从本地运行 MATLAB

```powershell
robocopy Z:\ E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab /MIR
```

当前更推荐方式 B，因为 MATLAB 从本地盘读代码通常更稳定。

本轮建议下一步直接采用方式 B，也就是先把 `Z:\` 镜像到 Windows 本地目录，再让 MATLAB 从本地目录加载代码；这样可以把“代码同步”和“MATLAB 本地运行”两件事拆开，降低后续排障复杂度。

若你不希望使用 `C:`，当前推荐的 Windows 本地目录可直接定为：

```text
E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab
```

重要警告：

- `robocopy ... /MIR` 的含义是“把目标目录镜像成和源目录完全一致”
- 若目标目录里原先有其他文件，而源目录里没有，这些文件可能会被删除
- 因此**不要**把 `/MIR` 直接用在一个长期手工维护的通用目录根上
- 推荐始终使用一个专用子目录，例如 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab`

本轮已发生过一次实际案例：

- 执行了 `robocopy Z:\ E:\MATLAB_code_Gongwei_Local /MIR`
- 随后发现 `E:\MATLAB_code_Gongwei_Local` 被镜像成了 Samba 共享中的 MATLAB 代码目录
- 这意味着若该目录原先存在与 `Z:\` 不一致的文件，它们可能已经被 `/MIR` 删除

因此从本轮起，统一改用“专用子目录镜像”的口径，避免再覆盖 `E:\MATLAB_code_Gongwei_Local` 根目录中原有文件。

本轮代码镜像已实测通过，`robocopy` 摘要显示：

- `文件: 22 复制: 22 失败: 0`
- 随后 `dir E:\MATLAB_code_Gongwei_Local` 已能看到：
  - `functions/`
  - `scripts/`
  - `architecture.drawio`
  - `ber.m`
  - `gnss_rx_user_paths.m.example`
  - `README.md`

这说明 MATLAB 代码已经成功从 `Z:` 镜像到 Windows 本地目录。后续 MATLAB 运行应优先使用 Windows 本地目录，而不是直接从网络盘 `Z:` 运行。

### 5.8 本轮实测总结与最终口径

本轮实际发生的过程可以总结为：

1. 先通过 Samba 将 Ubuntu 端 `~/GNSS_RX_matlab_share` 成功映射为 Windows 的 `Z:`
2. 随后误执行：

```powershell
robocopy Z:\ E:\MATLAB_code_Gongwei_Local /MIR
```

3. 这导致 `E:\MATLAB_code_Gongwei_Local` 根目录被直接镜像成 MATLAB 代码目录
4. 之后改正为：

```powershell
robocopy Z:\ E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab /MIR
```

5. 最终在 `E:\MATLAB_code_Gongwei_Local` 下同时出现了两套内容：
   - 根目录下一套：属于早先误同步留下的残留
   - `GNSS_RX_matlab\` 子目录下一套：这是当前确认采用的正式目录

本轮最终统一口径：

```text
Windows MATLAB 代码正式目录 = E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab
```

后续都按下面规则执行：

- MATLAB 只从 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab` 运行
- 后续代码同步只使用：

```powershell
robocopy Z:\ E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab /MIR
```

- `E:\MATLAB_code_Gongwei_Local` 根目录下那套 `functions/`、`scripts/`、`ber.m`、`README.md` 等文件，属于误同步残留
- 在确认 MATLAB 已切到 `GNSS_RX_matlab` 子目录运行后，可将根目录那套残留文件手工清理

建议的清理顺序：

1. 先在 MATLAB 中切到 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab`
2. 用 `which ber -all` 等命令确认实际加载路径已指向该子目录
3. 再删除 `E:\MATLAB_code_Gongwei_Local` 根目录下那套误同步残留

本轮最终验证已实测通过。MATLAB 中执行：

```matlab
dir('E:\MATLAB_code_Gongwei_Local')
dir('E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab')

cd('E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab')
addpath(pwd)
addpath(fullfile(pwd,'functions'))
addpath(fullfile(pwd,'scripts'))
rehash

which ber -all
which run_ber_loopback -all
which run_prn_acquisition -all
which recover_nav_bits -all
which gnss_rx_resolve_accel_options -all
```

得到的关键结果为：

- 父目录 `E:\MATLAB_code_Gongwei_Local` 下当前只保留了 `GNSS_RX_matlab` 子目录
- `ber` 指向 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\ber.m`
- `run_ber_loopback` 指向 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\scripts\run_ber_loopback.m`
- `run_prn_acquisition` 指向 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\functions\run_prn_acquisition.m`
- `recover_nav_bits` 指向 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\functions\recover_nav_bits.m`
- `gnss_rx_resolve_accel_options` 指向 `E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab\functions\gnss_rx_resolve_accel_options.m`

这说明 MATLAB 代码运行目录已经切换正确，Samba 代码同步链路到这里可以视为完成。

从这一步开始，后续统一按下面执行：

- MATLAB 启动后优先执行：

```matlab
cd('E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab')
addpath(pwd)
addpath(fullfile(pwd,'functions'))
addpath(fullfile(pwd,'scripts'))
rehash
```

- 代码更新时，Windows 端继续使用：

```powershell
robocopy Z:\ E:\MATLAB_code_Gongwei_Local\GNSS_RX_matlab /MIR
```

- 真正进入 BER 分析前，再把采集数据通过移动硬盘复制到 Windows 本地，并在 MATLAB 中显式指定 `CAPTURE_PATH` 或配置 `gnss_rx_user_paths.m`

---

## 六、和采集数据的边界

这份方案只处理 MATLAB 代码，不处理采集数据。

当前边界如下：

- MATLAB 代码：可走 Samba 共享
- 采集数据 `.sc16/.json/_tx_truth.json`：仍走 Ubuntu 本地落盘
- 数据转运：仍用移动硬盘

不要把正式 `250 s` 采集结果直接写到 Samba 共享目录。正式采集仍应先写：

```text
/home/<USER>/GNSS_RX_Data_local/...
```

---

## 七、第一轮最小验证命令

建议先只验证到“Windows 能看见 Ubuntu 上的 MATLAB 镜像目录”，不要一上来就把所有东西都改完。

第一轮最小验证顺序：

1. Ubuntu 上先跑：

```bash
mkdir -p ~/GNSS_RX_matlab_share
cd ~/projects/GNSS_RX
bash ./scripts/sync_matlab.sh ~/GNSS_RX_matlab_share
ls -lh ~/GNSS_RX_matlab_share
```

2. 再跑：

```bash
hostname -I
sudo systemctl status smbd --no-pager
```

3. 然后我们根据你的实际用户名、IP、Windows 用户名，把 Samba 配置和 `net use` 命令填实。

---

## 八、后续准备填实的变量

等你后面贴命令结果时，我们会把下面这些占位符替换掉：

- `<USER>`：Ubuntu 用户名
- `<UBUNTU_IP>`：Ubuntu 在局域网中的实际 IP
- `<SAMBA_PASSWORD>`：你设置的 Samba 密码
- `<WIN_USER>`：Windows 用户名

---

## 九、当前建议

在“只同步 MATLAB 代码、数据仍然走移动硬盘”的前提下，当前建议是：

1. 先按本文件试通 Samba 代码共享
2. 数据链路保持不变，不要和网络共享混在一起
3. 一旦 `Z:` 成功可见，再决定 MATLAB 是直接跑网络盘，还是先复制到 Windows 本地

这能把问题拆成两个独立部分：

- 局域网代码同步是否可用
- 采集数据转运是否稳定

两者不要同时改。
