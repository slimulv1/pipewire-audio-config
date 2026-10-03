-- SPDX-License-Identifier: MIT
--
-- games-sink-routing: chuyển stream của Steam/Proton/Wine sang sink "games_sink"
--
-- BẢN GỐC TRONG REPO KHÔNG BAO GIỜ HOẠT ĐỘNG, vì 2 lý do độc lập:
--   1) dùng section `node.rules` -> WirePlumber 0.5 không đọc section này;
--   2) regex `~*proton*` -> LỖI: "nothing to repeat".
--      journalctl: "pw.conf: invalid regex *proton*: Invalid preceding regular expression"
--
-- Ngoài ra `stream.rules` (section ĐÚNG tên) KHÔNG giải quyết được:
--   stream.rules chỉ dùng props sau khi update để tính "key" và kiểm tra
--   restore-target; nó KHÔNG ghi props đó xuống node
--   (xem /usr/share/wireplumber/scripts/node/state-stream.lua:149).
--
-- Cách đúng trong WP 0.5: hook thẳng vào sự kiện "select-target", chạy TRƯỚC
-- linking/find-defined-target, và tự chọn target -> các policy sau (media-role,
-- audio-group, best-target, default-target) đều bị skip vì target đã có.
--
-- An toàn: nếu games_sink không tồn tại (service chưa bật / DAC rút), script
-- im lặng bỏ qua -> stream dùng default sink bình thường, KHÔNG mất tiếng.

lutils = require ("linking-utils")
log = Log.open_topic ("s-games-routing")

local TARGET_NAME = "games_sink"

local PATTERNS = {
  "proton", "wine", "wine64", "wineserver", "gamescope",
}

local function matches (s)
  if not s then return false end
  for _, p in ipairs (PATTERNS) do
    if string.find (s, p, 1, true) then
      return true
    end
  end
  return false
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

    -- đã có target rồi -> không can thiệp
    if target then
      return
    end

    -- chỉ stream phát ra
    local media_class = si_props ["media.class"] or ""
    if string.find (media_class, "^Stream/Output") ~= 1 then
      return
    end

    -- client nền tảng native không có application.process.binary
    local appbin = si_props ["application.process.binary"]
    local appname = si_props ["application.name"]
    if not matches (appbin) and not matches (appname) then
      return
    end

    -- tìm node games_sink
    for lnkbl in om:iterate { type = "SiLinkable" } do
      local tprops = lnkbl.properties
      if tprops ["node.name"] == TARGET_NAME then
        log:info (si, string.format (
            "routing %s (%s) -> %s", tostring (si_props ["node.name"]),
            tostring (appbin or appname), TARGET_NAME))
        event:set_data ("target", lnkbl)
        si_flags.has_defined_target = true
        si_flags.has_node_defined_target = true
        return
      end
    end

    log:debug (si, TARGET_NAME .. " not present, using default target")
  end
}:register ()