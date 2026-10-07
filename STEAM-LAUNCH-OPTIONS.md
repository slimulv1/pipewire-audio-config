# ============================================================================
#  Launch Options khuyến nghị cho Steam/Proton game
# ----------------------------------------------------------------------------
#  Đây KHÔNG phải cấu hình PipeWire, nhưng là nguyên nhân lớn nhất gây
#  tiếng "rè / kêu è è" trong game. Đưa vào đây để mọi người biết.
#
#  NGUYÊN NHÂN 1 — GHI LOG LIÊN TỤC (quan trọng nhất)
#
#    Launch options có:
#        PROTON_LOG=1
#        WINEDEBUG=+loaddll,+seh,+ntdll
#    thì Wine trace MỌI lời gọi hàm nội bộ ntdll. Đo trên máy thật, file
#    log sinh ra đạt 963 MB, nội dung lặp liên tục:
#        trace:ntdll:RtlSetBits (00006FFFFFFA9460,23,1)
#        trace:ntdll:RtlAreBitsClear (00006FFFFFFA9460,19,1)
#        ...
#    Chính README của Proton-CachyOS cảnh báo:
#        "Full tracing floods the log and PERTURBS AUDIO TIMING ENOUGH TO CAUSE
#         CRACKLING. ... only use it for a short capture and remove it for
#         normal play."
#
#    Đây là lý do tiếng rè KHÔNG xuất hiện trong tín hiệu số: nhiễu do ghi log
#    gây nhiễu nhịp thời gian ở tầng hệ thống, không để lại dấu vết trong
#    dữ liệu âm thanh. Nên có thể "tín hiệu sạch hoàn toàn" mà tai vẫn nghe
#    là rè.
#
#    ==> BỎ `PROTON_LOG=1` và `WINEDEBUG=...` khi không còn debug.
#
#  NGUYÊN NHÂN 2 — DRIVER winepipewire.drv THỬ NGHIỆM
#
#    Bản Proton-CachyOS thêm driver `winepipewire.drv` (Wine nói thẳng với
#    PipeWire, bỏ qua pipewire-pulse) và BẬT MẬC ĐỊNH. README ghi:
#        "The driver is enabled by default. To disable it and use
#         `winepulse.drv` set `PROTON_USE_PIPEWIRE=0`."
#        "WINE_AUDIO_DRIVER ... For example WINE_AUDIO_DRIVER=pulse will use
#         `winepulse.drv` exclusively."
#
#    Driver mới = ít được kiểm chứng hơn. Nếu đã bỏ log mà vẫn rè, thử
#    `PROTON_USE_PIPEWIRE=0` để dùng lại đường winepulse.drv lâu đời.
#
#  LAUNCH OPTIONS KHUYẾN NGHỊ
#
#    SteamDeck=0 DXVK_HDR=1 ENABLE_LAYER_MESA_ANTI_LAG=1 PROTON_NO_STEAMINPUT=1 PROTON_PRIORITY_HIGH=1 PROTON_USE_PIPEWIRE=0 game-performance %command% -skip-launcher -dx12
#
#  THỬ THEO THỨ TỰ (để biết chính xác nguyên nhân)
#
#    1. Chỉ bỏ PROTON_LOG + WINEDEBUG, giữ nguyên driver.
#       -> Đây là nghi phạm chính (có 963 MB log làm bằng chứng).
#    2. Nếu vẫn rè, thêm PROTON_USE_PIPEWIRE=0.
#       -> Đánh đổi: audio đi qua thêm pipewire-pulse, thêm một ít độ trễ.
#
#  CÁCH KIỂM TRA GAME CÓ ĐANG GHI LOG KHÔNG
#
#    ls -la ~/steam-<appid>.log
#    # file này phình ra hàng trăm MB => launch options còn PROTON_LOG
#
#  KHI CẦN DEBUG THÌ BẬT TẮT LẠI
#
#    Bật:   PROTON_LOG=1
#    Tắt:  xoá PROTON_LOG=1 và WINEDEBUG khỏi launch options.
#    Theo README Proton, khi báo lỗi driver PipeWire nên dùng
#        PROTON_LOG=warn+pipewire,warn+mmdevapi %command%
#    thay vì PROTON_LOG=1 — nhẹ hơn nhiều và không phá nhịp âm thanh.
# ============================================================================