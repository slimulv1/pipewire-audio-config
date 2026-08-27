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
```

## Cài đặt

```bash
cp -r pipewire/*   ~/.config/pipewire/
cp -r wireplumber/* ~/.config/wireplumber/
systemctl --user restart pipewire wireplumber
```

## Mỗi file làm gì

### `50-audioengine-a2p-rate.conf` (PipeWire)
- `default.clock.rate = 48000` — A2+ native 48k.
- `default.clock.allowed-rates = [ 44100, 48000 ]` — nhạc 44.1k phát **native**, không resample.
- `resample.quality = 10` — resampler tier cao cho file hi-res.

### `50-audioengine-a2p-no-suspend.conf` (WirePlumber)
- Tắt idle-suspend cho sink A2+ (`session.suspend-timeout-seconds = 0`) → DAC không ngủ → **không câm** (lỗi đã biết của USB DAC dưới PipeWire, đặc biệt lúc vào game).
- `device.priority = 2000` → A2+ sticky làm default.

### `50-epos-gsx300-gaming.conf` (WirePlumber)
- Tắt suspend cho EPOS output **và** mic.
- `node.latency = 256/48000` — latency thấp cho gaming (sync âm/hình).
- `audio.rate = 48000` pin (EPOS **không hỗ trợ 44100**).
- `audio.format = S24_3LE`, `audio.channels = 2` pin (24-bit stereo native).

## Quirks đã xử lý

- **A2+**: đường USB thực tế hiện trong ALSA là `"Generic USB Audio"` (DAC high-res 32-bit/192k), **KHÔNG phải** PCM2704C 16/48. Card tên `"Audioengine 2+"` thực chất là module Bluetooth (CSRA64210) bên trong loa, không phải đường USB DAC.
- **EPOS GSX 300**: chip Conexant CX21988, 24-bit/96k, **stereo-only** (7.1 surround là Windows-only qua EPOS Gaming Suite, không có trên Linux). Lỗi suspend/resume là **#1** → bắt buộc tắt suspend.
- Nút volume trên EPOS = gain analog local, **không** đồng bộ software trên Linux.
- `lib32-libpulse` cần thiết cho game 32-bit / Proton có tiếng.

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
