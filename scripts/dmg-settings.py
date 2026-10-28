# dmgbuild 設定：安裝視窗的大小、背景與圖示位置。由 scripts/make-dmg.sh 以 `-D app=<Ripen.app>` 呼叫。
# 圖示座標必須與 scripts/generate-dmg-background.swift 的箭頭位置一致（點，左上角為原點、圖示中心）。
import os

# dmgbuild 以 exec 載入本檔，沒有 __file__；路徑由 make-dmg.sh 以 -D 傳入
app = defines["app"]  # noqa: F821（dmgbuild 執行時注入）
here = defines["scripts"]  # noqa: F821

format = "UDZO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")

# 背景旁的 background@2x.png 會自動合成 Retina 版本
background = os.path.join(here, "dmg/background.png")
# 高度含標題列（約 32 點），內容區與 600×400 的背景等高
window_rect = ((200, 120), (600, 432))
default_view = "icon-view"
show_status_bar = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
icon_locations = {
    "Ripen.app": (160, 200),
    "Applications": (440, 200),
}
