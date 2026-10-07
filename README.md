# pipewire-audio-config

Cấu hình **PipeWire + WirePlumber** cho desktop Linux dùng **2 DAC USB**:

| Thiết bị | Vai trò |
|---|---|
| 🔊 **Audioengine A2+ Wireless** (USB Type-B) | Loa nghe nhạc chính — **default sink** |
| 🎮 **EPOS GSX 300** (USB) | DAC gaming — đổi sang khi chơi game |

Đã kiểm chứng bằng **đo tín hiệu thật** trên CachyOS · kernel 7.2.8 ·
**PipeWire 1.6.9** · **WirePlumber 0.5.18** · Proton-CachyOS (Wine 11.0).

---

## 🔧 Sửa lỗi "tiếng loa bị rè" khi chơi game Steam

### Triệu chứng

Chơi game (AION2, Where Winds Meet) qua Steam/Proton → tiếng loa bị **rè**.

### Nguyên nhân thật (đã đo, không phải phỏng đoán)

**1. Băng thông USB bị vượt — đây là nguyên nhân chính**

Bản gốc để A2+ ở profile `HiFi 7+1`, tức PipeWire gửi **8 kênh S32LE @48kHz**:

| Chế độ | Băng thông |
|---|---|
| `HiFi 7+1` — 8ch S32LE 48k | 1.536.000 B/s = **12,288 Mbit/s** |
| `HiFi` — 2ch S32LE 48k | 384.000 B/s = **3,072 Mbit/s** |

A2+ cắm ở **USB 2.0 High-Speed** (`lsusb -t` → `480M`). Descriptor của chính
thiết bị cho thấy endpoint isochronous lớn nhất chỉ **992 byte/ms**
(`lsusb -v`: `wMaxPacketSize 0x03e0`), tức khoảng **7,9 Mbit/s**, và **không
endpoint nào có `bInterval 0`**.

> **12,288 Mbit/s > 7,9 Mbit/s → vượt băng thông bus.**

Kết quả: USB isochronous không kịp → underrun → tiếng rè/crackle, nặng nhất ở
cảnh combat to. Đây là lý do DAC stereo vẫn bị rè dù game chỉ phát stereo.

**Sửa:** ghim A2+ về profile **`HiFi`** (stereo) → giảm **4×** băng thông.
`install.sh` tự làm việc này.

**2. Hook định tuyến game không bao giờ chạy (dead code)**

Đo trực tiếp từ stream của AION2 đang chạy:

```
node.loop.name            = winepipewire
application.name          = AION2
application.process.binary= <không tồn tại>
media.name                = audio stream #1
```

Driver PipeWire của Wine (`winepipewire.so`) chỉ đặt `application.name`,
`media.class`, `media.type`, `node.name`, `target.object` — **không hề đặt
`application.process.binary`**. Hook cũ khớp `proton|wine|gamescope|*.exe` nên
**không khớp `AION2`** → audio game đổ thẳng vào sink A2+.

**Sửa:** khớp `node.loop.name = winepipewire` — marker phổ quát cho **mọi**
game Wine/Proton, không cần đoán tên game. Đã xác nhận hook bắt được cả 3
stream của AION2:

```
routing [winepipewire | AION2 | audio stream #1] -> games_sink
routing [winepipewire | AION2 | audio stream #2] -> games_sink
routing [winepipewire | AION2 | audio stream #4] -> games_sink
```

### Đính chính: giả thuyết clipping của bản gốc là **sai**

Bản gốc cho rằng game phát 5.1/7.1 rồi firmware A2+ downmix không normalize
nên clip. Đo thật thì **AION2 phát 3 stream stereo (6 link = 3×2ch), không phải
5.1** → không có downmix, không clip.

Tín hiệu game thật đo được tại monitor của sink:

```
peak 0.5014 (-6.00 dBFS)   RMS 0.084   số mẫu clip = 0
```

Nên với game này, clipping **không** phải nguyên nhân — nguyên nhân là băng thông.

### Tuy nhiên clipping **có thật** với nội dung đa kênh thật

Đo phép downmix của PipeWire (monitor của sink stereo, input 5.1):

| Input | Kết quả |
|---|---|
| gain đo được của downmix 6→2 | **2,766× = +8,84 dB** |
| 5.1 @ −10,5 dBFS/kênh (nhiễu nhiễu) | peak −3,22 dBFS — không clip |
| 5.1 @ −6 dBFS/kênh | peak **1,0000 (0 dBFS) — CLIP** |
| 5.1 @ −6 dBFS + volume 0,35 | peak −1,14 dBFS — không clip |

→ Ngưỡng clip là **−8,8 dBFS/kênh**. Nếu sau này game/phim thật sự phát 5.1,
hạ volume stream đó xuống ~25% là đủ headroom.

---

## Cài đặt

```bash
git clone https://github.com/slimulv1/pipewire-audio-config
cd pipewire-audio-config
./install.sh
```

### ⚠️ Đường dẫn — dễ sai nhất

| Loại file | Đường dẫn đúng |
|---|---|
| fragment `.conf` | `~/.config/wireplumber/wireplumber.conf.d/` |
| script `.lua` | `~/.local/share/wireplumber/scripts/` ← **khác chỗ** |
| unit `.service` | `~/.config/systemd/user/` |

WirePlumber 0.5 **không** tìm `.lua` trong `~/.config/wireplumber/`.

---

## Chẩn đoán lại (nếu vẫn nghe "rè")

```bash
./diagnose.sh 20
```

Chạy ở terminal 1, rồi **bật game** ở terminal 2 trong lúc nó đang ghi.
Script in ra: sink nào là default, định dạng thật của từng sink, stream nào đang
phát và đi tới đâu, và **peak / RMS / số mẫu bị clip** của tín hiệu thật đi vào DAC.

Cách đo: `pw-cat --record --target=<sink>` tạo monitor của sink trong PipeWire nên
đọc được đúng tín hiệu sắp đưa vào DAC.

Đọc kết quả:

- `clip > 0` → đang clip → xem mục headroom ở trên
- `clip = 0`, peak < −1 dBFS → không clip, nguyên nhân nằm ở chỗ khác
  (kiểm tra lại băng thông USB bằng `lsusb -t`)

---

## Cấu trúc

```
pipewire/pipewire.conf.d/50-audioengine-a2p-rate.conf
    └─ context: clock 48k, cấm đổi rate, resample quality 11
wireplumber/wireplumber.conf.d/50-audioengine-a2p-no-suspend.conf
    └─ A2+: tắt idle-suspend + device.priority = 2000
wireplumber/wireplumber.conf.d/50-epos-gsx300-gaming.conf
    └─ EPOS: S24_3LE @48k, latency 256/48000, tắt suspend
wireplumber/wireplumber.conf.d/51-games-sink-routing-hook.conf
    └─ đăng ký Lua hook
wireplumber/scripts/games-sink-routing.lua
    └─ hook select-target: game Wine/Proton -> games_sink
systemd/user/pw-loopback-games.service
    └─ games_sink stereo ảo -> A2+, tự phục hồi
install.sh · diagnose.sh
```

---

## Đo đạc sau khi sửa

| Hạng mục | Kết quả | Cách đo |
|---|---|---|
| A2+ profile | `HiFi` stereo, `s32le 2ch 48000Hz` | `pactl list short sinks` |
| Băng thông A2+ | 3,072 Mbit/s (giảm 4×) | tính từ format |
| Clock rate | `48000`, allowed-rates `[ 48000 ]` | `pw-dump` Core props |
| resample.quality | `11` (160 taps) | nguồn `resample-native.c` |
| A2+ latency | QUANT 1024 = 21,3 ms | `pw-top -b` |
| EPOS format | `s16le` → **`s24le 2ch 48000Hz`** | `pactl list short sinks` |
| EPOS latency | QUANT 256 = **5,33 ms** | `pw-top -b` |
| Game AION2 | route vào `games_sink` ✔ | log `s-games-routing` |
| Tín hiệu game thật | peak −6,00 dBFS, **clip = 0** | monitor của sink |
| xrun / lỗi | 0 | `journalctl` |

---

## Vì sao `allowed-rates = [ 48000 ]`

Bản gốc dùng `[ 44100, 48000 ]`. Đo cho thấy ngược lại — A2+ native 48 kHz, và
PipeWire sẽ **cấu hình lại cả DAC** khi graph đổi rate:

```
[ 44100, 48000 ] + client 44.1kHz → R 58 2048 44100 S32LE 8 44100   ← đổi rate
[ 48000 ]        + client 44.1kHz → R 58 1024 48000 S32LE 8 48000   ← giữ native
```

Client 44.1 kHz chỉ bị resample cục bộ; DAC không bao giờ phải đổi rate.

---

## Gỡ cài đặt

```bash
systemctl --user disable --now pw-loopback-games.service
rm -f ~/.config/systemd/user/pw-loopback-games.service
rm -f ~/.config/pipewire/pipewire.conf.d/50-audioengine-a2p-rate.conf
rm -f ~/.config/wireplumber/wireplumber.conf.d/50-*.conf
rm -f ~/.config/wireplumber/wireplumber.conf.d/51-*.conf
rm -f ~/.local/share/wireplumber/scripts/games-sink-routing.lua
systemctl --user daemon-reload
systemctl --user restart pipewire pipewire-pulse wireplumber
```

---

## Ghi chú

- **A2+**: ALSA nhận diện là `"Generic USB Audio"` (không phải "Audioengine").
  Có module Bluetooth riêng (`Audioengine_2`) — config này không đụng tới.
- **EPOS GSX 300**: chip Conexant CX21988, 24-bit, stereo-only trên Linux.
  PipeWire mặc định chọn `s16le`; config ép `S24_3LE` → đo được `s24le`.
- **Game 32-bit**: cần `lib32-libpulse`.
- **Đổi sang EPOS khi chơi game**:
  `wpctl set-default $(wpctl status | grep -oE '[0-9]+\. EPOS GSX 300 Analog Stereo' | grep -oE '^[0-9]+')`