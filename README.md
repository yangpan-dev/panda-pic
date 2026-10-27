# 熊猫图库

使用 **SwiftUI、AppKit、Core Image、ImageIO** 实现的 macOS 原生图片浏览与轻量编辑软件。无需浏览器、Electron、网络服务或第三方依赖。

## 下载与安装

**普通用户直接下载安装包即可，不需要 Xcode、Swift 或其他开发环境。**

| 下载 | 说明 |
| --- | --- |
| [下载 DMG 安装包](https://github.com/yangpan-dev/panda-pic/releases/latest/download/PandaGallery-macOS-universal.dmg) | 推荐，拖动安装；Apple Silicon / Intel 通用 |
| [下载 ZIP 压缩包](https://github.com/yangpan-dev/panda-pic/releases/latest/download/PandaGallery-macOS-universal.zip) | 解压后将应用拖入「应用程序」 |
| [查看所有版本](https://github.com/yangpan-dev/panda-pic/releases) | 发行说明、历史版本与校验值 |

系统要求：**macOS 14 或更新版本**。安装包包含 `arm64` 与 `x86_64` 两种架构。本机已在 Apple Silicon 上实测；Intel 已交叉编译，尚未做 Intel 实机测试。

1. 下载 DMG 并双击打开。
2. 将 **熊猫图库.app** 拖到 **Applications（应用程序）**。
3. 从「应用程序」启动，点击「打开」或按 `⌘O` 选择一张图片，随后可按 `←` / `→` 浏览同目录图片。

**首次打开说明：** 当前安装包使用 ad-hoc 签名，尚未使用 Apple Developer ID 签名或经过 Apple 公证。如果系统阻止首次打开，在确认来源和校验值后，可按 [Apple 官方步骤](https://support.apple.com/zh-cn/102445) 前往「系统设置 → 隐私与安全性 → 仍要打开」。

完整操作说明见 **[中文下载安装教程](docs/INSTALL.md)**，包含首次打开、文件权限、默认看图软件、更新卸载和校验方法。

## 从源码构建

开发者需要 macOS 14+、Swift 6+ / Xcode Command Line Tools。在项目目录执行：

```sh
bash scripts/build-app.sh
open 'output/熊猫图库.app'
```

构建脚本会创建原生 `.app`、生成熊猫 `.icns` 图标并添加本地 ad-hoc 签名。默认构建当前 CPU 架构；如需 Apple Silicon / Intel 通用应用：

```sh
bash scripts/build-app.sh release universal
```

也可以使用 Xcode 打开 `Package.swift` 编辑源码，或运行 `swift run --build-system native PandaGallery`。后一种方式需从项目根目录启动，以便找到 `Resources/` 示例资源。

## 无需选择文件夹，直接看下一张

打开任意一张图片时，程序会读取该图片的父目录，筛选系统支持的图片文件，再以自然文件名顺序显示。`photo2` 会排在 `photo10` 前面，不会把子文件夹、隐藏文件和其他文档加入图片列表。

可通过以下任一方式打开：

- `⌘O` 选择一张图片。
- 将图片直接拖入应用窗口。
- Finder 右键图片 →「打开方式」→「熊猫图库」。首次可以通过「其他」选择本项目生成的 `.app`。
- 命令行：`open -a '/完整路径/熊猫图库.app' '/完整路径/图片.jpg'`。

打开后按 `←`、`→`，点击画面两侧按钮，或点击底部缩略图切换图片。普通浏览在首尾停止；幻灯片可选择循环播放。

**文件访问说明：** 应用不启用 App Sandbox，以支持从单个图片 URL 枚举同级文件，而不额外要求用户选择文件夹。它仍遵守 macOS 的 TCC、目录权限与磁盘访问限制；系统询问访问桌面、文稿或下载目录时需允许。当前版本面向本地直接分发，不是 Mac App Store 沙盒版本。

## 界面与主题

默认白天模式，采用中性浅灰与白色；设置中可切换黑夜模式，选择会保留到下次启动。窗口、编辑器、设置、原生文件面板与图片画布随主题一起切换。

主界面仅保留一条工具栏与图片网格，隐藏默认详情栏，移除宣传文案、图片格式标签、尺寸和大小信息。图片名称默认悬停显示，可在设置中改为始终显示。阅读视图自动收起左侧导航；编辑工具只在点击「编辑」后出现，图片信息通过更多菜单或 `⌘I` 查看。

排序与格式筛选收进右上角「…」菜单；主题、缩略图大小、名称显示、底部胶片栏、幻灯片间隔、循环播放、示例图库与帮助集中在「设置」（`⌘,`）。相册可从更多菜单或设置中创建。

缩略图大小使用「小 / 中 / 大」三档，默认「中」，对应网格最小宽度 180 / 240 / 320pt；实际显示宽度会随窗口自适应。旧版滑块值会迁移到最接近的档位。1.1.1 的界面字体统一增加 2pt：主标题 14→16pt，侧栏 12→14pt，常用按钮与文件名 11→13pt，辅助信息 10→12pt，编辑标签 9→11pt。

## 功能

- 支持白天 / 黑夜模式的简洁中文图库与专注阅读视图，窗口、菜单栏、文件选择器和保存面板均为原生实现。
- 本地示例图库；按名称、修改时间、文件大小排序；名称搜索；JPG / PNG / 其他格式筛选；可调缩略图大小。
- 原图阅读、缩放、1:1、适应窗口、拖动平移、触控板捏合、全屏、底部胶片栏。
- 定时幻灯片，可设置间隔与循环播放。
- 收藏、最近打开、最近文件菜单、自建相册与相册分组，使用本机 UserDefaults 持久保存记录，不移动或上传原图片。
- 自由裁剪、1:1 / 4:3 / 3:2 / 16:9 / 2:3 比例，选框可拖动与缩放。
- 左右旋转、水平 / 垂直翻转、亮度 / 对比度 / 饱和度，六种原生 Core Image 滤镜。
- 撤销 / 重做、恢复原图、按住对比、未导出编辑的离开确认。
- PNG / JPEG / TIFF / HEIC 导出（按当前系统编码能力显示），可调 JPEG / HEIC 质量，保存副本且避免覆盖当前原图，原子写入保证导出失败不破坏已有文件。
- Finder 定位，确认后移至 macOS 废纸篓。
- JPEG、PNG、HEIC、TIFF、BMP、WebP、GIF 首帧及系统支持的 RAW 等图片；读取 EXIF 方向，避免手机照片方向错误。具体解码格式取决于当前 macOS 的 ImageIO 能力。

当前 GIF 以首帧静态显示；相册记录文件路径，外部移动或重命名后的图片需重新打开。首版会在打开文件时扫描目录，不实时监控目录变动。单张图片最大为 1 亿像素，撤销记录按图片大小限制内存占用。

## 快捷键

| 操作 | 快捷键 |
| --- | --- |
| 打开图片 | `⌘O` |
| 上一张 / 下一张 | `←` / `→` |
| 播放 / 暂停幻灯片 | `空格` |
| 放大 / 缩小 | `+` / `−` |
| 适应窗口 / 实际大小 | `⌘0` / `⌘1` |
| 图库 / 阅读视图 | `⌘2` / `⌘3` |
| 搜索 | `⌘F` |
| 收藏 | `F` |
| 裁剪 / 向右旋转 | `C` / `R` |
| 导出副本 | `⌘S` |
| 撤销 / 重做 | `⌘Z` / `⇧⌘Z` |
| 显示 / 隐藏详情 | `⌘I` |
| 全屏 | `⌃⌘F` |
| 返回图库 / 退出全屏 | `Esc` |

## 验证

```sh
bash scripts/test.sh
```

9 项 Swift Testing 自动测试涵盖白天模式默认值和主题偏好恢复、单文件打开后同级图片发现、自然排序、隐藏文件与非图片排除、导航首尾与循环、精确像素裁剪比例与边界、旋转裁剪导出完整流程、原图文件保护、EXIF 方向与错误文件处理。脚本会自动识别 Command Line Tools 或 Xcode 的测试框架路径；Core Image 测试需要系统图形服务可用。

图标 PNG 位于 `Resources/PandaGallery.png`，完整多尺寸 macOS 图标位于 `Resources/AppIcon.icns`。图标由内置 image_gen 生成；实际使用的提示词存于 `Resources/IconPrompt.txt`。示例图片来源见 `Resources/PhotoCredits.md`。

本地签名可用于当前机器体验；对外正式分发前，可使用开发者自己的 Developer ID 进行签名和 Apple 公证。

## 打包与发布

生成通用应用、DMG、ZIP、中文教程和 SHA-256 校验文件：

```sh
bash scripts/package-release.sh
```

产物保存在 `output/releases/v<版本号>/`；源码、示例图片和图标保存在 Git 仓库，安装包保存在 [GitHub Releases](https://github.com/yangpan-dev/panda-pic/releases)。构建缓存、测试输出、个人图片与安装包不会纳入源码提交。

维护者发布新版本的步骤见 [发布指南](docs/RELEASING.md)。当前分发包是 ad-hoc 签名版本，使用者可能需要按教程确认首次打开；正式免提示分发需由维护者使用自己的 Developer ID 签名并通过 Apple 公证。
