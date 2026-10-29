#!/usr/bin/env bash
# 将本仓库 configs/ 中的样例应用到当前用户环境（会先备份）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFG="$ROOT/configs"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/fcitx5-pinyin-setup-backup-$TS"

backup() {
  local src="$1"
  if [[ -e "$src" ]]; then
    mkdir -p "$BACKUP_DIR"
    local dest="$BACKUP_DIR/${src#$HOME/}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    echo "已备份: $src -> $dest"
  fi
}

echo "==> 备份并写入 Fcitx5 / KWin 配置"

mkdir -p "$HOME/.config/autostart"
mkdir -p "$HOME/.config/fcitx5"
mkdir -p "$HOME/.config/systemd/user/app-fcitx5@autostart.service.d"

backup "$HOME/.config/autostart/fcitx5.desktop"
backup "$HOME/.config/fcitx5/config"
backup "$HOME/.config/fcitx5/profile"
backup "$HOME/.config/kwinrc"
backup "$HOME/.config/systemd/user/app-fcitx5@autostart.service.d/override.conf"

cp "$CFG/fcitx5.desktop" "$HOME/.config/autostart/fcitx5.desktop"
cp "$CFG/fcitx5-config" "$HOME/.config/fcitx5/config"
cp "$CFG/fcitx5-profile" "$HOME/.config/fcitx5/profile"
cp "$CFG/fcitx5-autostart.override.conf" \
  "$HOME/.config/systemd/user/app-fcitx5@autostart.service.d/override.conf"

if command -v kwriteconfig6 >/dev/null 2>&1; then
  kwriteconfig6 --notify --file kwinrc --group Wayland \
    --key InputMethod /usr/share/applications/fcitx5-wayland-launcher.desktop
  kwriteconfig6 --notify --file kwinrc --group Wayland \
    --key VirtualKeyboardEnabled true
  echo "已更新 kwinrc [Wayland] InputMethod"
else
  echo "警告: 未找到 kwriteconfig6，请手动合并 configs/kwinrc.snippet.ini"
fi

systemctl --user daemon-reload || true
systemctl --user restart app-fcitx5@autostart.service 2>/dev/null \
  || (pgrep -x fcitx5 >/dev/null || fcitx5 -D &)

# 若 KWin available 仍为 false，尝试 toggle 触发启动器
if command -v busctl >/dev/null 2>&1; then
  sleep 0.5
  avail="$(busctl --user get-property org.kde.KWin /VirtualKeyboard \
    org.kde.kwin.VirtualKeyboard available 2>/dev/null || true)"
  if [[ "$avail" != *"true"* ]]; then
    echo "KWin InputMethod 未就绪，尝试重新写入以触发..."
    kwriteconfig6 --notify --file kwinrc --group Wayland --key InputMethod "" || true
    sleep 0.3
    kwriteconfig6 --notify --file kwinrc --group Wayland \
      --key InputMethod /usr/share/applications/fcitx5-wayland-launcher.desktop || true
  fi

  if busctl --user call org.fcitx.Fcitx5 /controller \
    org.fcitx.Fcitx.Controller1 ReloadConfig >/dev/null 2>&1; then
    busctl --user call org.fcitx.Fcitx5 /controller \
      org.fcitx.Fcitx.Controller1 SetCurrentIM s pinyin >/dev/null 2>&1 || true
    busctl --user call org.fcitx.Fcitx5 /controller \
      org.fcitx.Fcitx.Controller1 Activate >/dev/null 2>&1 || true
    echo "已请求切换到拼音并激活"
  fi
fi

echo
echo "完成。请点进文本框后按 Ctrl+Space 切换中英文。"
echo "检查命令:"
echo "  pgrep -af 'fcitx5|wayland-launcher'"
echo "  fcitx5-remote; fcitx5-remote -n"
echo "  busctl --user get-property org.kde.KWin /VirtualKeyboard org.kde.kwin.VirtualKeyboard available"
