# 应用图标（2026-11-26）

v0.4.31 之前 `mipmap-*/ic_launcher.png` 还是 **Flutter 默认图标**（浅蓝 Z 字），
装到机器上跟别的 Flutter App 混在一起完全认不出来。这里换成一套按品牌色画的
图标，并且由脚本生成，不再手改 PNG。

## 1. 图形

```
深青对角渐变底（#0A332C → #2F6B5F = kSeedColor）
└─ 圆角「对话气泡」+ 左下尾巴        近白 #F2FFFA
   └─ 五根圆头声纹条                深青 #064239
```

- **气泡**：这个 App 的核心对象就是对话，比「信封/盒子/麦克风」都直白。
- **声纹**：「留声」的字面意思，也让图标不像一个普通的聊天气泡。
- **零阴影、零描边**：和 `lib/core/skin_tokens.dart` 里三套皮肤的零阴影规则一致；
  图标靠底色对比，不靠细节。
- **48px 检验**：缩到 48×48 只剩「浅色气泡 + 深色竖条」两层信息，仍然认得出
  （见 `docs/brand/` 的母版，或跑一次 `--preview`）。

试过但没采用的方案：

| 方案 | 为什么不用 |
| --- | --- |
| 唱片（留声机）+ 中心标签 | 48px 上同心纹路会变成噪点，而且读起来像「音乐播放器」 |
| 双气泡叠加 | 96px 以下两个气泡的边缘会糊在一起 |
| 下颚与左边缘共线（Material `chat_bubble` 那种） | 气泡一宽就变成「折角文件」，像文档图标 |

## 2. 产物

| 文件 | 用途 |
| --- | --- |
| `mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png` | 传统图标（48/72/96/144/192），API < 26 |
| `mipmap-{..}/ic_launcher_round.png` | 传统圆形图标，`android:roundIcon` 用 |
| `mipmap-{..}/ic_launcher_foreground.png` | 自适应前景层（108dp 画布） |
| `mipmap-{..}/ic_launcher_monochrome.png` | Android 13+ 主题图标（系统按 alpha 染色，声纹是洞） |
| `mipmap-anydpi-v26/ic_launcher{,_round}.xml` | 自适应图标声明 |
| `drawable/ic_launcher_background.xml` | 自适应背景（纯 XML 渐变，不占位图） |
| `docs/brand/icon-512.png`、`icon-1024*.png` | 商店图 / README（不进 APK） |
| `docs/brand/icon-preview.png` | 一张对比图：母版、圆形遮罩、主题图标、各密度缩小后 |

## 3. 两条容易踩的线

1. **自适应前景只能占画布的 52%。** 自适应图标是 108dp 画布 + 72dp 圆形安全区，
   气泡是横向的（宽:高 ≈ 1.25），画到 0.62 时外接矩形的四角会伸出圆外，
   Pixel 这类圆形遮罩的启动器会把气泡两端切掉。`ADAPTIVE_MARK_RATIO = 0.52`
   是「整颗外接矩形都在 72dp 圆内」的最大值。
2. **自适应前景不能用同一张传统图标位图。** 传统图标自带圆角方底，塞进
   `<foreground>` 会看到一个「方图套在圆底里」。前景层必须是**透明底**的图形。

## 4. 改图标

```bash
python tool/make_icon.py                 # 覆盖 res/ 与 docs/brand/
python tool/make_icon.py --preview p.png # 先出对比图看效果
python tool/make_icon.py --diagram d/    # 出规范图：遮罩预演 + 108dp 安全区标注
python tool/make_icon.py --variant mint  # 换薄荷气泡配色
```

几何/颜色都在 `tool/make_icon.py` 顶部：

- `GEO`：气泡宽高、圆角、尾巴、五根声纹的位置与高度（归一化到图形方框）；
- `BG_TOP` / `BG_BOTTOM` / `BUBBLE_LIGHT` / `BARS_LIGHT`：颜色；
- `SS = 4`：超采样倍率（改小边缘会脏，改大只是更慢）。

`--diagram` 会**现场量**前景层里最远的不透明像素：当前 34.35dp ＜ 72dp 遮罩圆半径 36dp
（余量 1.65dp）。改完几何跑一次，这个数变大就说明可能被圆形遮罩切掉。

> 设计侧的完整规范在 `keepsake-design` 仓库的 `docs/app-icon.md`（v3.9）与 `brand/`；
> 本文件是工程侧的落地记录，两边冲突时以设计库为准。

改完**一定**跑一次 `--preview`：尾巴根部（`tail_top`）如果压到气泡体底边以下，
并集会出现一道缝，48px 上就是「底下多一块」。

## 5. 依赖

`Pillow` + `numpy`（脚本目录里没有 requirements，跑之前 `pip install pillow numpy`）。
产物是 PNG（不是 WebP）：Android 的 `aapt2` 对两者都支持，但 PNG 在有损压缩之外
还能保住 1px 圆头，声纹条不会糊成方块。
