# pipewire-audio-config

Cấu hình **PipeWire + WirePlumber** cho desktop Linux dùng **2 DAC USB**:

- 🎵 **Audioengine A2+ Wireless (USB Type-B)** — loa nghe nhạc chính (default sink).
- 🎮 **EPOS GSX 300 (USB)** — DAC gaming phụ (chuyển thủ công khi chơi game).

Môi trường test: Arch Linux, PipeWire 1.6.x, WirePlumber 0.5.x, dwm.

## Cấu trúc

```
pipewire/pipewire.conf.d/50-audioengine-a2p-rate.conf
wireplumber/wireplumber.conf.d/50-audioengine-a2p-no-suspend.conf
wireplumber/wireplumber.conf.d/50-epos-gsx300-gaming.conf
wireplumber/wireplumber.conf.d/52-games-sink-routing.conf
systemd/user/pw-loopback-games.service
```

## Cài đặt

```bash
cp -r pipewire/*   ~/.config/pipewire/
cp -r wireplumber/* ~/.config/wireplumber/
cp -r systemd/user/* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now pw-loopback-games.service
systemctl --user restart pipewire wireplumber
```

## Mỗi file làm gì

### `50-audioengine-a2p-rate.conf` (PipeWire)
- `default.clock.rate = 48000` — A2+ native 48k.
- `default.clock.allowed-rates = [ 44100, 48000 ]` — nhạc 44.1k phát **native**, không resample.
- `resample.quality = 11` — tier "critical listening" (-140dB stopband). Chỉ có tác dụng KHI có resampling (file hi-res 96k/192k → 48k, hoặc nhạc 44.1k lúc graph đang 48k). Nhạc native 44.1k/48k phát BIT-PERFECT (không resample) nên mức này vô can.

### `50-audioengine-a2p-no-suspend.conf` (WirePlumber)
- Tắt idle-suspend cho sink A2+ (`session.suspend-timeout-seconds = 0`) → DAC không ngủ → **không câm** (lỗi đã biết của USB DAC dưới PipeWire, đặc biệt lúc vào game).
- `device.priority = 2000` → A2+ sticky làm default.

### `50-epos-gsx300-gaming.conf` (WirePlumber)
- Tắt suspend cho EPOS output **và** mic.
- `node.latency = 256/48000` — latency thấp cho gaming (sync âm/hình).
- `audio.rate = 48000` pin (EPOS **không hỗ trợ 44100**).
- `audio.format = S24_3LE`, `audio.channels = 2` pin (24-bit stereo native).

### `52-games-sink-routing.conf` + `pw-loopback-games.service` — hết rè game trên A2+ (giữ 7.1 cho nhạc)
- **Vấn đề**: sink A2+ chạy profile "HiFi 7+1" (S32LE, 8 kênh) nhưng loa vật lý là **stereo** — khi game phát 5.1/7.1, 8 kênh nguyên vẹn qua USB và **firmware bên trong A2+ tự trộn 8→2 KHÔNG normalize → clip → rè** khi có nhiều âm lớn cùng lúc. Nhạc (stereo) không bao giờ chạm đường này.
- **Giải pháp**: `systemd/user/pw-loopback-games.service` tạo sink stereo ảo **`games_sink`** (pw-loopback, capture stereo, playback `target.object` = A2+ 7.1 sink). Game → `games_sink` (2 kênh) → loopback đẩy 2ch sang A2+ → PipeWire upmix 2→8 (không thể clip). Nhạc vẫn đi thẳng A2+ 7.1.
- **Routing**: `52-games-sink-routing.conf` tự route client `proton/wine/gamescope/reaper` → `games_sink`. Lưu ý: KHÔNG match `*steam*` (Steam client nhạc/video giữ 7.1); binary stream game = tên exe (vd `Cyberpunk2077.exe`) nên rule **không bắt được game** → dùng launch option:
  ```
  PULSE_SINK=games_sink %command%
  ```
  (Steam → Properties → Launch Options; game native Linux thêm cả `SDL_AUDIODRIVER=pulseaudio` nếu cần.)

## Quirks đã xử lý

- **A2+**: đường USB thực tế hiện trong ALSA là `"Generic USB Audio"` (DAC high-res 32-bit/192k), **KHÔNG phải** PCM2704C 16/48. Card tên `"Audioengine 2+"` thực chất là module Bluetooth (CSRA64210) bên trong loa, không phải đường USB DAC.
- **EPOS GSX 300**: chip Conexant CX21988, 24-bit/96k, **stereo-only** (7.1 surround là Windows-only qua EPOS Gaming Suite, không có trên Linux). Lỗi suspend/resume là **#1** → bắt buộc tắt suspend.
- Nút volume trên EPOS = gain analog local, **không** đồng bộ software trên Linux.
- `lib32-libpulse` cần thiết cho game 32-bit / Proton có tiếng (đã có trên máy).

## Chuyển sang EPOS khi chơi game (thủ công)

```bash
wpctl set-default $(wpctl status | grep -oE '[0-9]+\. EPOS GSX 300 Analog Stereo' | grep -oE '[0-9]+')
```

Hoặc chọn `"EPOS GSX 300 Analog Stereo"` ngay trong cài đặt âm thanh của game / launcher
(Steam → Settings → Audio → Output device) — cách này chỉ game đó đi EPOS, nhạc hệ thống vẫn A2+.

## Verify

```bash
# A2+ (phải suspend-timeout = "0")
wpctl inspect $(wpctl status | grep -oE '[0-9]+\. USB Audio Speakers' | grep -oE '[0-9]+') | grep suspend-timeout

# EPOS (khi đang phát, phải S24_3LE / 48000 / 2ch)
cat /proc/asound/card*/pcm0p/sub0/hw_params
```
