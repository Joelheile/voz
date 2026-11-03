# dmgbuild settings for the Voz disk image. Run through scripts/make-dmg.sh.
# Icon positions must match the layout in scripts/make-dmg-background.swift.

app = defines["app"]
background = defines["background"]

format = "ULFO"
filesystem = "APFS"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["voz.app"]

window_rect = ((200, 160), (640, 360))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

icon_size = 128
text_size = 13
icon_locations = {
    "voz.app": (176, 188),
    "Applications": (464, 188),
}
