#!/usr/bin/env bash
# ============================================================================
#  Chẩn đoán "tiếng loa bị rè" khi chơi game.
#
#  CÁCH DÙNG:
#     1. Terminal 1:  ./diagnose.sh          (để chạy, ghi ~15 giây)
#     2. Terminal 2:  bật game, vào chơi, để có tiếng nhạc/gameplay
#     3. Đọc kết quả in ra.
#
#  SCRIPT ĐO ĐƯỢC GÌ:
#     - số kênh mà sink A2+ đang nhận (quyết định có cần downmix không)
#     - peak / RMS / số mẫu bị clip của tín hiệu thật đi tới DAC
#     - stream nào đang phát, đi tới sink nào (đã qua games_sink chưa)
#
#  TẠI SAO ĐO ĐƯỢC:
#     pw-cat --record --target=<sink> tạo monitor của sink đó trong PipeWire,
#     nên ta đọc được đúng tín hiệu sắp đưa vào DAC (chưa qua volume của sink).
# ============================================================================
set -uo pipefail

SECS="${1:-15}"
SPEAKER="alsa_output.usb-Generic_USB_Audio-00.HiFi__Speaker__sink"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

hdr() { printf '\n\033[1;36m== %s ==\033[0m\n' "$*"; }

hdr "1. Sink nào đang là default"
wpctl status 2>/dev/null | grep -E '\*\s+[0-9]+\.' | sed 's/^/  /' || echo "  (không đọc được)"

hdr "2. Định dạng thực tế của từng sink"
pactl list short sinks 2>/dev/null | while read -r id name rest; do
  printf '  %-58s %s\n' "$name" "$(echo "$rest" | awk '{print $1" "$2" "$3}')"
done

hdr "3. Có phải downmix không?"
sp_id=$(pactl list short sinks 2>/dev/null | awk -v s="$SPEAKER" '$2==s{print $1}')
if [ -n "${sp_id:-}" ]; then
  fmt=$(pactl list sinks 2>/dev/null | awk "/^Sink #$sp_id\$/,/^\t*\$/" \
        | grep -m1 "Sample Specification" | sed 's/.*: //')
  echo "  A2+ speakers: $fmt"
  case "$fmt" in
    *2ch*) echo "  -> STEREO. Không có downmix nào xảy ra ở sink." ;;
    *)    echo "  -> ĐA KÊNH! Mọi stream stereo/5.1 đều phải downmix -> nguy cơ clip." ;;
  esac
else
  echo "  !! không thấy $SPEAKER"
fi

hdr "4. Đang ghi $SECS giây - HÃY BẬT GAME NGAY"
echo "  file: $OUT/cap.raw"
# --sample-count giới hạn đúng số mẫu -> script tự dừng, không treo
if ! pw-cat --record --target="$sp_id" --rate=48000 --channels=8 --format=s32 \
        --sample-count=$((48000 * SECS)) "$OUT/cap.raw" 2>/dev/null; then
  echo "  !! không tạo được monitor cho sink (thử chạy lại khi PipeWire rảnh)"
fi

hdr "5. Stream đang phát trong lúc ghi"
pactl list sink-inputs 2>/dev/null | grep -E "Sink Input|Sink: |application.name|application.process.binary|media.name" \
  | sed 's/^/  /' | head -40

hdr "6. Phân tích tín hiệu"
python3 - "$OUT/cap.raw" <<'PY'
import sys, array, math
p = sys.argv[1]
try:
    d = open(p, 'rb').read()
except Exception as e:
    print("  khong doc duoc:", e); sys.exit(0)
if len(d) < 4096:
    print("  khong co du lieu (co the game chua phat am thanh)"); sys.exit(0)
a = array.array('i'); a.frombytes(d[:len(d)//4*4])
# tu phat hien so kenh: thu 2, 6, 8; chon so kenh lam cac khac bi phai
# phat nhieu. mac dinh 2 (cua sink stereo)
for ch in (8, 6, 2):
    n = len(a)//ch
    if n < 4800: continue
    peak = 0.0; over = 0; e = 0
    step = max(1, n//400000)
    tot = 0
    for i in range(0, n, step):
        for c in range(ch):
            v = a[i*ch+c]/2147483648.0
            av = abs(v)
            if av > peak: peak = av
            if av >= 0.99997: over += 1
            e += v*v; tot += 1
    print(f"  gia su {ch} kenh: peak={peak:.4f} ({20*math.log10(peak) if peak>1e-9 else -99:+.2f} dBFS)"
          f"  RMS={math.sqrt(e/tot):.4f}  so mau clip={over}")
print()
print("  -> Neu 'so mau clip' > 0 tren kenh 2 chinh la DANG RE (clipping).")
print("  -> Fix: xem README muc 'Headroom' (giam volume stream da kenh >2).")
PY

hdr "7. Hook có bắt được game không?"
journalctl --user -u wireplumber --since "-${SECS}s" --no-pager 2>/dev/null \
  | grep -i "s-games-routing" | tail -12 | sed 's/^/  /' \
  || echo "  (khong thay dong routing nao)"

echo
echo "Xong. Giai thich:"
echo "  peak >= 0dBFS + so mau clip > 0  =>  co clipping, nghe se 're'"
echo "  peak < -1dBFS, clip = 0           =>  khong clip, nguyen nhân 're' nam o noi khac"