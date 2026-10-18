# dmgbuild settings for the MagicWall installer window.
#
# Invoked by Scripts/build-dmg.sh:
#   dmgbuild -s Scripts/dmg-settings.py \
#     -D app=/path/to/MagicWall.app \
#     -D version=0.5.0 \
#     -D background=/path/to/Scripts/dmg/background.png \
#     "MagicWall 0.5.0" dist/MagicWall-0.5.0.dmg
#
# The Finder content area is 660×420 pt; the window is 448 pt tall so the
# standard title bar does not eat into the artwork. Text and icon labels stay
# above y≈300, leaving the bottom decorative brick pattern free to be clipped
# by the title bar or the user's path bar if they have it enabled.

import os

app = defines["app"]
app_name = defines.get("app_name", "MagicWall")
version = defines.get("version", "")
background_path = defines["background"]

volume_name = f"{app_name} {version}".strip()
volume_icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

files = [(app, f"{app_name}.app")]
symlinks = {"Applications": "/Applications"}

# Finder coordinates are in points, measured from the top-left of the content
# area. The icons are 128 pt; their labels sit underneath.
icon_locations = {
    f"{app_name}.app": (180, 200),
    "Applications": (480, 200),
}

background = background_path
if os.path.exists(volume_icon):
    icon = volume_icon

# The extra 28 pt is the Finder title bar; 660×420 is the actual content.
window_rect = ((200, 120), (660, 448))

default_view = "icon-view"
icon_size = 128
text_size = 14
label_pos = "bottom"
arrange_by = None
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False

# Do not use hide_extensions: SetFile -a E attaches com.apple.FinderInfo to
# the signed app bundle, which makes `codesign --strict` reject it. Finder
# hides the .app extension by default anyway.

format = "UDZO"
filesystem = "HFS+"
compression_level = 9
