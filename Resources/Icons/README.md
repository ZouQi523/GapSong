# GapSong App Icon

| 文件 | 说明 |
|---|---|
| `gapsong-icon-v1.png` | 母图，1254×1254 |
| `gapsong-icon-v1-prompt.txt` | 生成/精修时使用的提示词 |

设计：一对八分音符，右侧符头被替换成薄荷绿的横条——对应“歌词里被挖掉的那个空”。

构建时 `build.sh` 会用 `sips` + `iconutil` 从母图生成 16–1024 px 的完整 `AppIcon.icns`，并由 `Info.plist` 的 `CFBundleIconFile` 指向它。

## 版权

图标随项目以 **GPL-3.0** 发布，Copyright (C) 2026 NeoZou。

母图是满幅方形（无透明圆角）；macOS 在 Finder / 授权弹窗里会按系统 app icon 形状自动裁切并加阴影，不需要自己再做圆角。`docs/screenshots/icon.png` 就是系统渲染后的样子。
