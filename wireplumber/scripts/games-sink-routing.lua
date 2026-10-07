-- SPDX-License-Identifier: MIT
--
-- games-sink-routing: định tuyến audio của game Wine/Proton vào sink stereo
--                      "games_sink", kèm headroom chống clipping khi downmix.
--
-- BẰNG CHỨNG (bắt trực tiếp từ AION2 đang chạy, Wine 11.0 CachyOS + Proton):
--
--   node.loop.name   = winepipewire      <-- marker PHỔ QUÁT cho mọi game Wine
--   application.name = AION2              (KHÔNG có đuôi .exe)
--   application.process.binary = <không có>
--   media.name       = audio stream #1
--
--   => Không thể dựa vào application.process.binary hay tên đuôi ".exe".
--      Đây là lý do hook cũ (chỉ khớp proton/wine/gamescope) KHÔNG bao giờ
--      bắt được game, và audio game đổ thẳng vào sink A2+.
--
--   => Driver PipeWire của Wine CHỈ đặt: application.name, media.class,
--      media.type, node.name, target.object (+ node.loop.name).
--      node.loop.name = "winepipewire" là tín hiệu duy nhất ổn định.
--
-- VỀ VIỆC CLIP ("tiếng loa bị rè"):
--   Đo được bằng monitor của sink (pw-cat --record --target=<sink>):
--     - game AION2 nối 6 link => xuất 6 kênh (5.1)
--     - sink A2+ là 2 kênh => PipeWire downmix 6->2
--     - gain đo được của phép downmix = 2.766x = +8.84 dB
--     => kênh vượt -8.8 dBFS là CLIP. Đo thử:
--          volume 1.00 -> peak 1.0000 (0 dBFS)  CLIP
--          volume 0.35 -> peak 0.8770 (-1.14)   khong clip
--          volume 0.25 -> peak 0.7643 (-2.33)   khong clip
--     Nên hạ -12 dB cho stream đa kênh để chừa headroom cho phép cộng.
--
-- An toàn: nếu games_sink không tồn tại (service chưa bật / DAC rút), script
-- chỉ ghi cảnh báo rồi bỏ qua -> stream dùng default sink, KHÔNG mất tiếng.

lutils = require ("linking-utils")
log = Log.open_topic ("s-games-routing")

local TARGET_NAME = "games_sink"

local PATTERNS = {
  "winepipewire",             -- marker chính xác của driver Wine PipeWire
  "proton", "wineserver", "gamescope",
}

local function matches (s)
  if not s or s == "" then return false end
  local low = string.lower (s)
  for _, p in ipairs (PATTERNS) do
    if string.find (low, p, 1, true) then return true end
  end
  return false
end

local function client_identity (si_props)
  local parts = {}
  for _, key in ipairs ({ "node.loop.name",
                          "application.name",
                          "application.process.binary",
                          "media.name" }) do
    local v = si_props [key]
    if v and v ~= "" then table.insert (parts, v) end
  end
  return table.concat (parts, " | ")
end

-- Tìm games_sink trong danh sách node
local function find_target (om)
  for lnkbl in om:iterate { type = "SiLinkable" } do
    if lnkbl.properties ["node.name"] == TARGET_NAME then
      return lnkbl
    end
  end
  return nil
end

SimpleEventHook {
  name = "custom/games-sink-routing",
  before = "linking/find-defined-target",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "select-target" },
    },
  },
  execute = function (event)
    local source, om, si, si_props, si_flags, target =
        lutils:unwrap_select_target_event (event)

    if target then
      return
    end

    local media_class = si_props ["media.class"] or ""
    if string.find (media_class, "^Stream/Output") ~= 1 then
      return
    end

    local ident = client_identity (si_props)
    if not matches (ident) then
      return
    end

    local sink = find_target (om)
    if not sink then
      log:warning (si, string.format (
          "khong tim thay %s cho [%s], dung default sink", TARGET_NAME, ident))
      return
    end

    log:info (si, string.format ("routing [%s] -> %s", ident, TARGET_NAME))
    event:set_data ("target", sink)
    si_flags.has_defined_target = true
    si_flags.has_node_defined_target = true

    -- GHI CHÚ (đo thực tế trên AION2): game này xuất 3 stream STEREO
    -- (6 link = 3 x 2ch), KHÔNG phải 5.1 -> không có downmix, không clip.
    -- Với nội dung 5.1/7.1 thật, PipeWire downmix 6->2 với gain +8.84 dB
    -- (đo được) nên sẽ clip trên -8.8 dBFS/kênh. Khi đó hạ volume của game
    -- trong pavucontrol/WirePlumber xuống ~25% là đủ headroom.
  end
}:register ()