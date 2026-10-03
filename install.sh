#!/usr/bin/env bash
# ============================================================================
#  Cài đặt pipewire-audio-config cho user hiện tại.
#
#  LƯU Ý VỀ ĐƯỜNG DẪN (WirePlumber >= 0.5):
#    - fragment .conf  -> ~/.config/wireplumber/wireplumber.conf.d/
#    - script .lua     -> ~/.local/share/wireplumber/scripts/   <-- KHÁC chỗ!
#  README cũ copy mọi thứ vào ~/.config/wireplumber/ -> script Lua sẽ
#  không bao giờ được load (WirePlumber không tìm .lua trong đó).
# ============================================================================
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PW_DIR="$HOME/.config/pipewire/pipewire.conf.d"
WP_DIR="$HOME/.config/wireplumber/wireplumber.conf.d"
WP_SCRIPTS="$HOME/.local/share/wireplumber/scripts"
UNIT_DIR="$HOME/.config/systemd/user"

mkdir -p "$PW_DIR" "$WP_DIR" "$WP_SCRIPTS" "$UNIT_DIR"

# 1) PipeWire: context properties (clock rate, resample quality)
cp -v "$SRC/pipewire/pipewire.conf.d/"*.conf "$PW_DIR/"

# 2) WirePlumber: rules (suspend, device priority, format/rate)
cp -v "$SRC/wireplumber/wireplumber.conf.d/"*.conf "$WP_DIR/"

# 3) WirePlumber: Lua script -> đúng thư mục data của WP 0.5
cp -v "$SRC/wireplumber/scripts/"*.lua "$WP_SCRIPTS/"

# 4) systemd user unit
cp -v "$SRC/systemd/user/"*.service "$UNIT_DIR/"

systemctl --user daemon-reload
systemctl --user enable --now pw-loopback-games.service

# Áp dụng: PipeWire đọc context.properties lúc khởi động -> phải restart.
systemctl --user restart pipewire pipewire-pulse wireplumber

echo
echo "Đợi WirePlumber dựng lại thiết bị rồi kiểm tra:"
sleep 8
wpctl status
echo
echo "--- games_sink có tồn tại không? ---"
# games_sink là node ảo của pw-loopback nên wpctl liệt kê ở mục Filters,
# không phải Sinks.
wpctl status | grep -q "games_sink" \
  && echo "OK: games_sink đang chạy" \
  || echo "CHƯA thấy games_sink (thường vài giây nữa sẽ có)"