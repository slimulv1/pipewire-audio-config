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
UNIT_DIR="$HOME/.config/systemd/user"

mkdir -p "$PW_DIR" "$WP_DIR"

# 1) PipeWire: context properties (clock rate, resample quality)
cp -v "$SRC/pipewire/pipewire.conf.d/"*.conf "$PW_DIR/"

# 2) WirePlumber: rules (suspend, device priority)
cp -v "$SRC/wireplumber/wireplumber.conf.d/"*.conf "$WP_DIR/"

systemctl --user daemon-reload

# Áp dụng: PipeWire đọc context.properties lúc khởi động -> phải restart.
systemctl --user restart pipewire pipewire-pulse wireplumber

sleep 6

# ---------------------------------------------------------------------------
#  Ghim profile STEREO ("HiFi") cho A2+.
#
#  VÌ SAO BẮT BUỘC:
#    A2+ là DAC high-speed, native 48kHz, chỉ có 2 kênh ra loa.
#    Profile mặc định "HiFi 7+1" ép PipeWire gửi 8 kênh S32LE:
#        8 x 4 x 48000 = 1.536.000 B/s = 12,288 Mbit/s
#    nhưng bus USB 2.0 High-Speed (480M) chỉ cấp tối đa ~992 byte/ms
#    (~7,9 Mbit/s isochronous) -> VƯỢT BĂNG THÔNG -> underrun, tiếng "rè".
#    Profile "HiFi" (stereo) chỉ cần 384.000 B/s = 3,072 Mbit/s -> dư 4 lần.
#
#  WirePlumber nhớ profile đã chọn trong state, nên chạy lệnh này là đủ.
# ---------------------------------------------------------------------------
pactl set-card-profile alsa_card.usb-Generic_USB_Audio-00 HiFi 2>/dev/null || true
sleep 4

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