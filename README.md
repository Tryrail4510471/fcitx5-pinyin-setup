# Ubuntu / KDE Plasma 6 Wayland 下启用 Fcitx5 汉语拼音

在 **Ubuntu 26.04 + KDE Plasma 6（Wayland）** 上安装并修复 Fcitx5 拼音输入法的完整记录。  
适用于输入法软件已安装、进程也在跑，但打字仍是英文、候选框不出现的情况。

## 环境

| 项目 | 本机实测 |
|------|----------|
| 系统 | Ubuntu 26.04 LTS (aarch64) |
| 桌面 | KDE Plasma 6.6 / `kwin_wayland` |
| 显示协议 | Wayland（`XDG_SESSION_TYPE=wayland`） |
| 输入法框架 | Fcitx 5.1.19 |
| 拼音引擎 | `fcitx5-pinyin` + `fcitx5-chinese-addons` |

## 快速结论

Wayland 上仅启动 `fcitx5` 不够。KWin 必须把 Fcitx 注册为 **Virtual Keyboard / Input Method**，按键才会交给输入法。

关键配置：

```ini
# ~/.config/kwinrc
[Wayland]
InputMethod=/usr/share/applications/fcitx5-wayland-launcher.desktop
VirtualKeyboardEnabled=true
```

并保证：

1. `fcitx5` 以前台方式常驻（`fcitx5 -D`，不要用会被 systemd 误判为退出的 `-d`）
2. `fcitx5-wayland-launcher --reopen` 由 KWin 拉起
3. 输入法组里有 `pinyin`，且当前为激活状态

## 安装软件包

```bash
sudo apt update
sudo apt install -y \
  fcitx5 \
  fcitx5-chinese-addons \
  fcitx5-pinyin \
  fcitx5-config-qt \
  fcitx5-frontend-gtk3 \
  fcitx5-frontend-gtk4 \
  fcitx5-frontend-qt5 \
  fcitx5-frontend-qt6 \
  im-config
```

用 `im-config` 选择 `fcitx5`（本机 `im-config -m` 显示已选 `fcitx5`）。

## 环境变量

会话里应有：

```bash
GTK_IM_MODULE=fcitx5
QT_IM_MODULE=fcitx5
SDL_IM_MODULE=fcitx5
XMODIFIERS=@im=fcitx5
GLFW_IM_MODULE=fcitx
```

KDE 下通常由 `im-config` / 会话脚本注入；可用下面命令检查：

```bash
env | grep -E 'IM_MODULE|XMODIFIERS'
```

## 配置文件（本仓库样例）

样例放在 [`configs/`](./configs/)：

| 文件 | 作用 |
|------|------|
| `kwinrc.snippet.ini` | 写入 `~/.config/kwinrc` 的 `[Wayland]` 段 |
| `fcitx5.desktop` | `~/.config/autostart/fcitx5.desktop`，以前台方式自启 |
| `fcitx5-config` | `~/.config/fcitx5/config`，跨程序共享输入状态 |
| `fcitx5-profile` | `~/.config/fcitx5/profile`，默认组含英文键盘 + 拼音 |
| `fcitx5-autostart.override.conf` | systemd user drop-in，失败自动重启 |

### 1. KWin Wayland 输入法

编辑 `~/.config/kwinrc`，加入或修改：

```ini
[Wayland]
InputMethod=/usr/share/applications/fcitx5-wayland-launcher.desktop
VirtualKeyboardEnabled=true
```

让 KWin 立刻读取（推荐带通知写入）：

```bash
kwriteconfig6 --notify --file kwinrc --group Wayland \
  --key InputMethod /usr/share/applications/fcitx5-wayland-launcher.desktop
kwriteconfig6 --notify --file kwinrc --group Wayland \
  --key VirtualKeyboardEnabled true
```

若 `available` 仍是 `false`，可先清空再写回触发一次：

```bash
kwriteconfig6 --notify --file kwinrc --group Wayland --key InputMethod ""
kwriteconfig6 --notify --file kwinrc --group Wayland \
  --key InputMethod /usr/share/applications/fcitx5-wayland-launcher.desktop
```

检查：

```bash
busctl --user get-property org.kde.KWin /VirtualKeyboard \
  org.kde.kwin.VirtualKeyboard available
# 期望: b true

pgrep -af 'fcitx5|wayland-launcher'
# 期望同时看到:
#   /usr/bin/fcitx5 ...
#   /usr/libexec/fcitx5-wayland-launcher --reopen
```

也可在 **系统设置 → 键盘 → 虚拟键盘** 中选择 **Fcitx 5**。

### 2. 自启：用前台模式

错误写法（daemon 化后父进程立刻退出，systemd-xdg-autostart 会清掉进程组）：

```desktop
Exec=fcitx5 -d
```

正确写法：

```desktop
# ~/.config/autostart/fcitx5.desktop
Exec=fcitx5 -D
```

可选加强（失败自动重启）：

```ini
# ~/.config/systemd/user/app-fcitx5@autostart.service.d/override.conf
[Service]
Restart=on-failure
RestartSec=2
```

然后：

```bash
systemctl --user daemon-reload
systemctl --user restart app-fcitx5@autostart.service
```

### 3. 拼音输入法组

`~/.config/fcitx5/profile`：

```ini
[Groups/0]
Name=默认
Default Layout=us
DefaultIM=pinyin

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=pinyin
Layout=

[GroupOrder]
0=默认
```

### 4. 跨程序共享输入状态

`~/.config/fcitx5/config`：

```ini
[Behavior]
ShareInputState=All
```

否则每个输入框各自记住「英文 / 拼音」，换窗口容易掉回英文。

重载配置：

```bash
busctl --user call org.fcitx.Fcitx5 /controller \
  org.fcitx.Fcitx.Controller1 ReloadConfig
```

## 常用操作

| 操作 | 默认快捷键 / 命令 |
|------|-------------------|
| 中英切换 | `Ctrl + Space` |
| 临时切换（左 Shift） | `Shift_L`（AltTrigger） |
| 上屏 | 数字键 / 空格 |
| 翻页 | `-` / `=` |
| 查看状态 | `fcitx5-remote`（0 关闭 / 1 英文侧 / 2 拼音激活） |
| 当前输入法名 | `fcitx5-remote -n` |
| 切到拼音 | `fcitx5-remote -s pinyin` 后必要时再激活 |
| 强制激活 | `busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 Activate` |

说明：在 Wayland 上，`fcitx5-remote` / D-Bus 切换的是**最近有焦点的输入上下文**。先点进文本框再切换更稳。

## 故障排查

### 现象：能打英文，没有候选框

按顺序查：

```bash
# 1. fcitx 是否在跑
pgrep -a fcitx5

# 2. KWin 是否已挂上输入法
busctl --user get-property org.kde.KWin /VirtualKeyboard \
  org.kde.kwin.VirtualKeyboard available

# 3. 是否有 wayland-launcher
pgrep -af fcitx5-wayland-launcher

# 4. 调试信息里应出现 frontend:wayland 的 InputContext
busctl --user call org.fcitx.Fcitx5 /controller \
  org.fcitx.Fcitx.Controller1 DebugInfo
```

若 `available` 为 `false`，回头做「KWin Wayland 输入法」一节。

### 现象：进程起一下就没了

检查自启是否用了 `fcitx5 -d`。改成 `-D`，并看：

```bash
systemctl --user status app-fcitx5@autostart.service
```

### 现象：D-Bus 切到 pinyin 马上又显示 keyboard-us

- 先点击目标输入框获得焦点
- 再执行 `Activate` / `SetCurrentIM pinyin`
- 或设置 `ShareInputState=All`

密码框默认禁用输入法（`AllowInputMethodForPassword=False`），这是预期行为。

### 现象：只在部分软件可用

- Qt / GTK 原生 Wayland 客户端：走 `zwp_input_method` / text-input，依赖 KWin + launcher
- 部分 Electron / Chromium：可再确认 `GTK_IM_MODULE` / Ozone Wayland；个别应用有兼容问题

## 一键应用样例（本机）

在仓库根目录：

```bash
./scripts/apply-configs.sh
```

脚本会备份已有文件，再写入本文档对应的配置，并尝试通知 KWin / 重载 Fcitx。

## 参考

- Fcitx5：<https://fcitx-im.org/>
- KWin `InputMethod` 配置项：`kwinrc` → `[Wayland]` → `InputMethod`（desktop 文件路径）
- 桌面入口：`/usr/share/applications/fcitx5-wayland-launcher.desktop`

## 许可

文档与样例配置以 MIT 许可发布，见 [LICENSE](./LICENSE)。
