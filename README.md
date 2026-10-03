# pipewire-audio-config

Cấu hình **PipeWire + WirePlumber** cho desktop Linux dùng **2 DAC USB**:

| Thiết bị | Vai trò |
|---|---|
| 🔊 **Audioengine A2+ Wireless** (USB Type-B) | Loa nghe nhạc chính — **default sink** |
| 🎮 **EPOS GSX 300** (USB) | DAC gaming — đổi sang khi chơi game |

Mục tiêu: **loa stereo không bao giờ bị hỏng tiếng khi chơi game**, DAC ở đúng
sample rate gốc, và **không để game chiếm đường âm thanh của hệ thống**.

> ⚠️ **Cấu hình này phụ thuộc phần cứng.** Regex được khoá theo đúng tên card ALSA
> của A2+ và EPOS GSX 300. Nếu bạn dùng thiết bị khác, phải sửa lại regex và
> `target.object` trong `pw-loopback-games.service`. Xem [Tương thích](#tương-thích).

**Đã kiểm chứng thực tế** trên CachyOS · kernel 7.2.8 · **PipeWire 1.6.9** ·
**WirePlumber 0.5.18** — mọi con số trong tài liệu này đều từ đo trên máy thật.

---

## TL;DR — 6 lỗi đã tìm và sửa

Phiên bản trước của repo **không bao giờ chạy đúng phần định tuyến game**, và có
2 lỗi làm mất ổn định toàn hệ thống. Tất cả đều đã tái hiện được:

| # | Vấn đề | Hậu quả | Cách sửa |
|---|---|---|---|
| 1 | `device.rules` không tồn tại ở WP 0.5 | `device.priority = 2000` là **dead code** | chuyển sang `monitor.alsa.rules` |
| 2 | `node.rules` không tồn tại ở WP 0.5 | toàn bộ rule game là **dead code** | bỏ, dùng Lua hook |
| 3 | Regex `~*proton*` không hợp lệ | WirePlumber **từ chối cả rule** | dùng Lua hook |
| 4 | `stream.rules` không ghi props xuống node | có cũng **không định tuyến được** | dùng Lua hook |
| 5 | `PartOf=pipewire.service` | `games_sink` **chết vĩnh viễn** khi restart daemon | bỏ `PartOf=`, dùng `Restart=always` |
| 6 | `games_sink` tranh default sink | **mọi âm thanh máy** đi qua loopback | `priority.session = -1000` |

Chi tiết + bằng chứng: [Chi tiết các lỗi](#chi-tiết-các-lỗi-đã-sửa).

---

## Yêu cầu

- PipeWire **≥ 1.6**, WirePlumber **≥ 0.5** (bắt buộc — cấu hình dùng API 0.5)
- `pw-loopback` (đi kèm PipeWire)
- Arch / CachyOS / distro dùng PipeWire làm audio server

---

## Cài đặt

```bash
git clone https://github.com/slimulv1/pipewire-audio-config
cd pipewire-audio-config
./install.sh
```

Script copy đúng **3 vị trí khác nhau**, bật service, restart cả 3 daemon và in ra
trạng thái để bạn kiểm tra ngay.

### ⚠️ Đường dẫn — dễ sai nhất

| Loại file | Đường dẫn đúng |
|---|---|
| fragment `.conf` | `~/.config/wireplumber/wireplumber.conf.d/` |
| script `.lua` | `~/.local/share/wireplumber/scripts/` ← **khác chỗ** |
| unit `.service` | `~/.config/systemd/user/` |

WirePlumber 0.5 **không** tìm file `.lua` trong `~/.config/wireplumber/`.
Nếu copy tất cả về cùng một chỗ thì hook sẽ **im lặng không bao giờ chạy** —
không có lỗi nào được báo, chỉ đơn giản là game không được chuyển sink.

### Kiểm tra sau khi cài

```bash
# 1. games_sink đã có chưa (nằm ở mục Filters, không phải Sinks)
wpctl status | grep games_sink

# 2. service đang chạy
systemctl --user status pw-loopback-games.service

# 3. sink nào đang làm default (phải là A2+, KHÔNG phải games_sink)
pwctl status | grep '\*'

# 4. định tuyến game có hoạt động không
journalctl --user -u wireplumber -f | grep s-games-routing
#   dự kiến: routing <tên game> (proton) -> games_sink
```

---

## Cấu trúc

```
pipewire/pipewire.conf.d/50-audioengine-a2p-rate.conf
    └─ context: clock rate 48k, cấm đổi rate, resample quality 11

wireplumber/wireplumber.conf.d/50-audioengine-a2p-no-suspend.conf
    └─ A2+: tắt idle-suspend + ghim device.priority = 2000

wireplumber/wireplumber.conf.d/50-epos-gsx300-gaming.conf
    └─ EPOS: S24_3LE @ 48k, latency 256/48000, tắt suspend

wireplumber/wireplumber.conf.d/51-games-sink-routing-hook.conf
    └─ đăng ký Lua hook vào profile "main"

wireplumber/scripts/games-sink-routing.lua
    └─ hook select-target: chuyển stream Steam/Proton/Wine -> games_sink

systemd/user/pw-loopback-games.service
    └─ games_sink (stereo ảo) -> A2+ 7.1, tự phục hồi

install.sh
```

---

## Thiết kế: tại sao cần `games_sink`?

A2+ có loa stereo nhưng profile mặc định là **7.1**. Nếu game phát 5.1/7.1 thẳng
ra loa, firmware bên trong A2+ sẽ downmix 8→2 **không normalize** → clip/rê.
Vì vậy:

```
game (2 kênh) → games_sink (ảo, stereo) → upmix 2→8 → A2+ 7.1
                                                  → firmware downmix 8→2
```

Loa stereo luôn nghe đúng 2 kênh, không bao giờ bị clip.
Còn nhạc, phim, game native Linux stereo → đi thẳng A2+, **không** qua vòng loopback.

---

## Đo đạc thực tế

Mọi giá trị dưới đây được đo sau khi sửa, trên đúng phần cứng của repo.

| Hạng mục | Kết quả | Cách đo |
|---|---|---|
| `default.clock.rate` | `48000` | `pw-dump` → Core props |
| `default.clock.allowed-rates` | `[ 48000 ]` | `pw-dump` |
| `resample.quality` | `11` (160 taps) | `pw-dump`; nguồn `resample-native.c` |
| A2+ format | `s32le 8ch 48000Hz` (native) | `pactl list short sinks` |
| A2+ latency | QUANT 1024 @48k = **21.3 ms**, ERR 0 | `pw-top -b` |
| EPOS format | `s24le 2ch 48000Hz` — **nâng từ `s16le`** | `pactl list short sinks` |
| EPOS latency | QUANT 256 @48k = **5.33 ms**, ERR 0 | `pw-top -b` |
| game → `games_sink` | ✔ (`proton`) | `pactl list sink-inputs` |
| app thường → A2+ | ✔ không bị đụng (`pw-play`) | `pactl list sink-inputs` |
| xrun / underrun | **0** | `journalctl -u pipewire` |
| lỗi / warning | **0** | `journalctl` |
| `device.priority` (A2+) | `2000` | `pw-dump` |

---

## Chi tiết các lỗi đã sửa

### 1 & 2. `device.rules` và `node.rules` không tồn tại ở WP 0.5

Hai section này không tồn tại trong WirePlumber 0.5.18. Danh sách section rules
hợp lệ lấy trực tiếp từ mã nguồn:

```bash
grep -rn get_section_as_json /usr/share/wireplumber/scripts/
```

```
access.rules              monitor.libcamera.rules
device.profile.priority.rules   monitor.v4l2.rules
monitor.alsa.rules        node.filter-graph.rules
monitor.bluez.rules       node.software-dsp.rules
monitor.bluez-midi.rules  stream.rules
```

→ không có `device.rules`, không có `node.rules`.

**Bằng chứng lỗi 1:** sau khi cài bản gốc, `pw-dump` cho
`device.priority = <không có>` trên `alsa_card.usb-Generic_USB_Audio-00`.
Tức là `device.priority = 2000` chưa từng được đặt, dù README khẳng định A2+
"sticky làm default".

**Sửa lỗi 1:** đưa rule device vào `monitor.alsa.rules`. Cùng một `config.rules`
được áp cho cả node (`alsa.lua:487`) lẫn device (`alsa.lua:678`), nên match
`device.name` là hợp lệ. Sau khi sửa: `device.priority = 2000` ✔

**Sửa lỗi 2:** bỏ hẳn `node.rules`, thay bằng Lua hook (mục 4).

### 3. Regex `~*proton*` không hợp lệ

Ngay cả khi section đúng, pattern này vẫn lỗi. `~` nghĩa là **regex POSIX ERE**,
mà `*` ở đầu là "nothing to repeat":

```
pw.conf: invalid regex *proton*: Invalid preceding regular expression
```

Đúng phải là `~".*proton.*"`.

### 4. `stream.rules` không định tuyến được (dù đúng tên section)

`stream.rules` **không** ghi props xuống node. Xem
`/usr/share/wireplumber/scripts/node/state-stream.lua:149` — props sau khi rule
update chỉ được dùng để tính key và **kiểm tra** có nên restore hay không,
không bao giờ áp `target.object` vào node hay metadata.
File mẫu chính thức cũng chỉ minh hoạ `state.*`:
`/usr/share/doc/wireplumber/examples/wireplumber.conf.d/stream.conf`.

**Sửa:** `wireplumber/scripts/games-sink-routing.lua` hook thẳng sự kiện
`select-target`, chạy **trước** `linking/find-defined-target`, tự chọn target →
các policy sau (media-role, audio-group, best-target, default-target) đều bị skip
vì target đã có.

Bằng chứng hook hoạt động:

```
I s-games-routing [games-sink-routing.lua:75] routing TestGame (proton) -> games_sink
```

Kiểm chứng cả 2 chiều — chỉ client khớp pattern mới bị chuyển:

| Client | `application.process.binary` | Đi tới |
|---|---|---|
| `proton` (giả lập qua libpulse) | `proton` | `games_sink` ✔ |
| `pw-play` (native PipeWire) | `pw-play` | A2+ (không đụng) ✔ |

### 5. `PartOf=` làm `games_sink` chết vĩnh viễn

Bản gốc dùng `PartOf=pipewire.service` + `Restart=on-failure`.
`PartOf` chỉ lan truyền lệnh **stop**. Khi `systemctl --user stop pipewire`,
service bị dừng theo, nhưng lệnh `start` sau đó **không** lan truyền ngược lại:

```bash
systemctl --user stop pipewire
systemctl --user start pipewire
# → pw-loopback-games.service = inactive, MainPID=0, games_sink biến mất vĩnh viễn
```

**Sửa:** bỏ `PartOf=`, dùng `Restart=always`. Đã kiểm chứng cả hai đường hỏng:

| Tình huống | Kết quả sau khi sửa |
|---|---|
| `stop` rồi `start` pipewire | games_sink **tự hồi phục** ✔ |
| `kill -9` tiến trình pw-loopback | **tự sống lại** ✔ (`NRestarts=3`) |

### 6. `games_sink` từng bị chọn làm default sink của **cả hệ thống**

Rủi ro nghiêm trọng nhất, chỉ lộ ra khi đọc log.
`games_sink` không thuộc device nào nên `priority.session` mặc định = 0 —
**bằng** với sink A2+. PipeWire phân định bằng `object.serial`, mà `games_sink`
được tạo **trước** (service user khởi động sớm, DAC USB chưa enumerate) nên
serial nhỏ hơn → nó thắng:

```
s-default-nodes: considering games_sink: prio 0, route_prio 0
s-default-nodes: -> selected games_sink: prio 0, route_prio 0
s-default-nodes: set default node for default.audio.sink games_sink
```

Hệ quả: **mọi âm thanh trên máy** đều đi qua vòng loopback.

**Sửa:** `priority.session = -1000` → `games_sink` không bao giờ thắng, chỉ nhận
stream khi hook chủ động chỉ định. Sau khi sửa, cold-boot cho thấy default sink
vẫn đúng là A2+ ✔

---

## Vì sao `allowed-rates = [ 48000 ]` chứ không phải `[ 44100, 48000 ]`?

Bản gốc dùng `[ 44100, 48000 ]` với lý do "44.1k phải chạy native". Đo thực tế cho
thấy ngược lại: A2+ là DAC high-speed, **native 48 kHz**, và PipeWire sẽ **cấu
hình lại cả DAC** khi graph đổi rate:

```
allowed-rates = [ 44100, 48000 ]  +  client 44.1kHz
  → R 58  2048  44100  S32LE 8 44100     ← đổi rate: mất nhịp, tiếng click

allowed-rates = [ 48000 ]         +  client 44.1kHz
  → R 58  1024  48000  S32LE 8 48000     ← giữ native, chỉ resample cục bộ
```

Client 44.1 kHz chỉ bị resample 44.1→48 (cục bộ, an toàn); DAC không bao giờ
phải đổi rate. Đây là mất ổn định, không phải lợi ích.

---

## Tương thích

Cấu hình dùng các tên node thật của phần cứng trong repo:

```
alsa_card.usb-Generic_USB_Audio-00                              (A2+ DAC, ALSA id "A2")
alsa_card.usb-Audioengine_Ltd._Audioengine_2__ABCDEFB1180003-00  (module Bluetooth trong loa)
alsa_card.usb-Sennheiser_EPOS_GSX_300_A003200202602692-00       (EPOS, ALSA id "E300")
```

Regex được **khoá theo đúng card** (`-00`) và escape dấu chấm, nên không lỡ khớp
card USB "Generic USB Audio" khác, và **không** chạm vào module Bluetooth trong loa.

Dùng thiết bị khác thì sửa:

| Cần đổi | File |
|---|---|
| regex `node.name` / `device.name` | `50-*.conf` |
| `target.object` trong `ExecStart` | `pw-loopback-games.service` |
| `application.process.binary` patterns | `games-sink-routing.lua` |

---

## Ghi chú đã xác minh

- **A2+**: ALSA nhận diện là `"Generic USB Audio"` (không phải "Audioengine").
  Loa còn có module Bluetooth riêng (`Audioengine_2`) — tách hoàn toàn, config
  này không đụng tới.
- **EPOS GSX 300**: chip Conexant CX21988, 24-bit, **stereo-only** trên Linux
  (7.1 chỉ có trên Windows qua EPOS Gaming Suite). PipeWire mặc định chọn
  `s16le`; config này ép `S24_3LE` → đo được `s24le`.
- **Game 32-bit / Proton**: cần `lib32-libpulse`.
- **Chuyển sang EPOS khi chơi game**:

  ```bash
  wpctl set-default $(wpctl status \
    | grep -oE '[0-9]+\. EPOS GSX 300 Analog Stereo' | grep -oE '^[0-9]+')
  ```

  Hoặc chọn trong Steam → Settings → Audio → Output device.
  Xong nhớ `wpctl set-default <id A2+>` để quay lại.

---

## Cấu hình hỏng có làm mất toàn bộ âm thanh không?

Không. Đã kiểm chứng cả ba tình huống:

| Thử nghiệm | Kết quả |
|---|---|
| Fragment WirePlumber sai cú pháp | WirePlumber vẫn `active`, các fragment khác vẫn áp dụng |
| `pipewire.conf.d` sai cú pháp | PipeWire vẫn `active`, client vẫn kết nối được |
| `games_sink` không tồn tại (service tắt / DAC rút) | PipeWire tự fallback sang default sink, **không mất tiếng** |

Cấu hình hỏng chỉ mất tính năng, không mất âm thanh. Đây là điểm cố ý giữ khi
sửa: mọi rule đều **fail-safe**.

---

## Gỡ cài đặt

```bash
systemctl --user disable --now pw-loopback-games.service
rm -f ~/.config/systemd/user/pw-loopback-games.service
rm -f ~/.config/pipewire/pipewire.conf.d/50-audioengine-a2p-rate.conf
rm -f ~/.config/wireplumber/wireplumber.conf.d/50-audioengine-a2p-no-suspend.conf
rm -f ~/.config/wireplumber/wireplumber.conf.d/50-epos-gsx300-gaming.conf
rm -f ~/.config/wireplumber/wireplumber.conf.d/51-games-sink-routing-hook.conf
rm -f ~/.local/share/wireplumber/scripts/games-sink-routing.lua
systemctl --user daemon-reload
systemctl --user restart pipewire pipewire-pulse wireplumber
```