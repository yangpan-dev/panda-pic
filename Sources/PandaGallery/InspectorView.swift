import SwiftUI
import AppKit

struct InspectorView: View {
    @ObservedObject var model: GalleryModel
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.mode == .viewer && model.tool != .info ? "编辑" : "图片信息").font(.system(size: 14, weight: .medium))
                Spacer()
                IconButton(symbol: "xmark", help: "关闭侧栏") { model.showInspector = false }
            }.foregroundStyle(Palette.text).padding(.horizontal, 20).frame(height: 49)
            if let photo = model.selected {
                if model.mode == .viewer {
                    HStack(spacing: 0) {
                        ForEach(GalleryModel.EditorTool.allCases, id: \.self) { tool in
                            Button { model.beginEditing(tool) } label: {
                                VStack(spacing: 8) { Text(tool.rawValue).font(.system(size: 13)); Rectangle().fill(model.tool == tool ? Palette.mint : .clear).frame(height: 2) }.foregroundStyle(model.tool == tool ? Palette.mint : Palette.muted).frame(maxWidth: .infinity)
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16).padding(.top, 5).overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if model.mode == .grid || model.tool == .info { info(photo) }
                        else if model.tool == .adjust { adjustments }
                        else if model.tool == .crop { cropTools }
                        else { filters }
                    }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 22)
                }.scrollIndicators(.hidden)
                if model.mode == .viewer && model.tool != .info { editorFooter }
            } else {
                Spacer(); Image(systemName: "photo").font(.system(size: 34, weight: .ultraLight)); Text("选择图片以查看详情").font(.system(size: 13)).padding(.top, 10); Spacer()
            }
        }.frame(maxHeight: .infinity).background(Palette.background).foregroundStyle(Palette.muted)
    }

    private func info(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(photo.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text).textSelection(.enabled).padding(.bottom, 25)
            detail("图片尺寸", photo.dimensions)
            detail("文件大小", photo.sizeText)
            detail("图片格式", photo.format)
            detail("修改时间", photo.date.formatted(.dateTime.year().month().day()))
            detail("所在位置", model.isDemo ? "内置示例图库" : photo.url.deletingLastPathComponent().lastPathComponent)
            if let edit = model.edit, edit.base.width != photo.width || edit.base.height != photo.height { detail("编辑后尺寸", "\(edit.base.width) × \(edit.base.height)") }
            Rectangle().fill(Palette.line).frame(height: 0.5).padding(.vertical, 18)
            Menu {
                if model.albums.isEmpty { Text("请先新建相册") }
                ForEach(model.albums) { album in Button { model.addToAlbum(album.id) } label: { Label(album.name, systemImage: album.paths.contains(photo.id) ? "checkmark" : "folder") } }
                Divider(); Button("新建相册…") { model.showNewAlbum = true }
            } label: { Text(model.albums.first(where: { $0.paths.contains(photo.id) })?.name ?? "添加到相册").font(.system(size: 13)) }.menuStyle(.borderlessButton).padding(.bottom, 18)
            Button(action: model.revealInFinder) { Label("在 Finder 中显示", systemImage: "folder").font(.system(size: 13)) }.buttonStyle(.plain).foregroundStyle(Palette.muted)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View { HStack(alignment: .top) { Text(label).foregroundStyle(Palette.muted); Spacer(minLength: 8); Text(value).foregroundStyle(Palette.text.opacity(0.8)).multilineTextAlignment(.trailing).textSelection(.enabled) }.font(.system(size: 12)).padding(.bottom, 13) }
    private func sectionDivider(_ text: String, icon: String) -> some View { VStack(spacing: 17) { Rectangle().fill(Palette.line).frame(height: 1); HStack { Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text.opacity(0.75)); Spacer(); Image(systemName: icon).font(.system(size: 12)) } }.padding(.bottom, 17) }
    private func quickTool(_ title: String, icon: String, action: @escaping () -> Void) -> some View { Button(action: action) { VStack(spacing: 9) { Image(systemName: icon).font(.system(size: 19, weight: .light)); Text(title).font(.system(size: 11)) }.frame(maxWidth: .infinity).padding(.vertical, 13).background(Palette.card, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Palette.line)) }.buttonStyle(.plain).foregroundStyle(Palette.mint.opacity(0.8)) }

    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("旋转与翻转").font(.system(size: 13)).foregroundStyle(Palette.text.opacity(0.8)).padding(.bottom, 16)
            HStack(spacing: 7) {
                quickTool("左转", icon: "rotate.left") { model.transform(.left) }
                quickTool("右转", icon: "rotate.right") { model.transform(.right) }
                quickTool("水平", icon: "arrow.left.and.right.righttriangle.left.righttriangle.right") { model.transform(.upMirrored) }
                quickTool("垂直", icon: "arrow.up.and.down.righttriangle.up.righttriangle.down") { model.transform(.downMirrored) }
            }.padding(.bottom, 28)
            HStack { Text("光影与色彩").font(.system(size: 13)).foregroundStyle(Palette.text.opacity(0.8)); Spacer(); Button("重置", action: model.resetAdjustments).buttonStyle(.plain).font(.system(size: 12)) }.padding(.bottom, 23)
            adjustmentSlider("亮度", keyPath: \.brightness, range: -0.5...0.5, value: Int((model.edit?.brightness ?? 0) * 100))
            adjustmentSlider("对比度", keyPath: \.contrast, range: 0.3...1.7, value: Int(((model.edit?.contrast ?? 1) - 1) * 100))
            adjustmentSlider("饱和度", keyPath: \.saturation, range: 0...2, value: Int(((model.edit?.saturation ?? 1) - 1) * 100))
        }
    }

    private func adjustmentSlider(_ title: String, keyPath: WritableKeyPath<EditState, Double>, range: ClosedRange<Double>, value: Int) -> some View {
        VStack(spacing: 12) {
            HStack { Text(title); Spacer(); Text(value > 0 ? "+\(value)" : "\(value)").monospacedDigit().foregroundStyle(Palette.text.opacity(0.8)) }.font(.system(size: 12))
            Slider(value: Binding(get: { model.edit?[keyPath: keyPath] ?? range.lowerBound }, set: { model.adjust(keyPath, value: $0) }), in: range, onEditingChanged: { editing in if !editing { model.commitEdit() } }).controlSize(.regular)
        }.padding(.bottom, 24)
    }

    private var cropTools: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("选择裁剪比例").font(.system(size: 13)).foregroundStyle(Palette.text.opacity(0.8))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 9) {
                aspectButton("自由", ratio: nil, width: 19, height: 16)
                aspectButton("1:1", ratio: 1, width: 17, height: 17)
                aspectButton("4:3", ratio: 4 / 3, width: 21, height: 16)
                aspectButton("3:2", ratio: 1.5, width: 24, height: 16)
                aspectButton("16:9", ratio: 16 / 9, width: 27, height: 15)
                aspectButton("2:3", ratio: 2 / 3, width: 13, height: 20)
            }
            Label("拖动选框移动位置，拖动四角调整大小。", systemImage: "cursorarrow.motionlines").font(.system(size: 12)).lineSpacing(5)
            AccentButton(title: "应用裁剪", symbol: "checkmark", action: model.applyCrop).frame(maxWidth: .infinity)
            Button("重置选框") { model.resetCrop(aspect: model.cropAspect) }.font(.system(size: 13)).frame(maxWidth: .infinity).padding(.vertical, 8).buttonStyle(.plain).background(Palette.card, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func aspectButton(_ title: String, ratio: CGFloat?, width: CGFloat, height: CGFloat) -> some View {
        Button { model.resetCrop(aspect: ratio) } label: { VStack(spacing: 9) { RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1).frame(width: width, height: height).frame(height: 22); Text(title).font(.system(size: 12)) }.frame(maxWidth: .infinity).frame(height: 65).foregroundStyle(model.cropAspect == ratio ? Palette.mint : Palette.muted).background(model.cropAspect == ratio ? Palette.selected : Palette.card, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(model.cropAspect == ratio ? Palette.mint : Palette.line)) }.buttonStyle(.plain)
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 18) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                ForEach(PhotoPreset.allCases) { preset in
                    Button { model.preset(preset) } label: {
                        VStack(spacing: 9) { if let photo = model.selected { FilterPreview(url: photo.url, preset: preset).frame(height: 70).clipped() }; Text(preset.rawValue).font(.system(size: 12)).padding(.bottom, 8) }.background(model.edit?.preset == preset ? Palette.selected : Palette.card).clipShape(RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(model.edit?.preset == preset ? Palette.mint : Palette.line))
                    }.buttonStyle(.plain).foregroundStyle(model.edit?.preset == preset ? Palette.mint : Palette.muted)
                }
            }
        }
    }

    private var editorFooter: some View {
        HStack(spacing: 7) {
            IconButton(symbol: "arrow.uturn.backward", help: "撤销（⌘Z）", action: model.undo).disabled(!model.canUndo)
            IconButton(symbol: "arrow.uturn.forward", help: "重做（⇧⌘Z）", action: model.redo).disabled(!model.canRedo)
            IconButton(symbol: "arrow.counterclockwise", help: "恢复原图", action: model.resetEdits)
            Spacer(minLength: 0)
            AccentButton(title: model.isRendering ? "处理…" : "导出", symbol: "square.and.arrow.up") { model.requestExport() }.disabled(model.isRendering || model.isLoading)
        }.padding(16).frame(maxWidth: .infinity).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 0.5) }
    }
}

struct FilterPreview: View {
    let url: URL
    let preset: PhotoPreset
    @ViewState private var image: NSImage?
    var body: some View {
        GeometryReader { geometry in
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: geometry.size.width, height: geometry.size.height).clipped() }
            else { Palette.card }
        }.task(id: url) {
            let result = await Task.detached(priority: .utility) { () -> NSImage? in
                guard let thumbnail = ThumbnailCache.shared.image(for: url, size: 220), let cg = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
                var state = EditState(base: cg); state.preset = preset
                guard let rendered = ImageEngine.render(state) else { return nil }
                return NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
            }.value
            if !Task.isCancelled { image = result }
        }
    }
}

struct ExportSheet: View {
    @ObservedObject var model: GalleryModel
    @ViewState private var format: ExportFormat = .png
    @ViewState private var quality = 0.92
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("导出图片副本", systemImage: "square.and.arrow.up").font(.system(size: 23, weight: .medium))
            Text("为编辑后的图片选择格式。原始文件将始终保留。").font(.system(size: 14)).foregroundStyle(Palette.muted)
            Picker("文件格式", selection: $format) { ForEach(ExportFormat.available) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            if format.lossy { HStack { Text("画质").font(.system(size: 14)); Slider(value: $quality, in: 0.3...1); Text("\(Int(quality * 100))%").font(.system(size: 13, design: .monospaced)).frame(width: 35) } }
            if let edit = model.edit { Text("输出尺寸：\(edit.base.width) × \(edit.base.height) 像素").font(.system(size: 13)).foregroundStyle(Palette.muted) }
            HStack { Spacer(); Button("取消") { model.cancelExport() }.keyboardShortcut(.cancelAction); Button("选择保存位置…") { model.export(format: format, quality: quality) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }.padding(30).frame(width: 420).tint(Palette.mint).preferredColorScheme(model.theme.colorScheme)
    }
}

struct SettingsSheet: View {
    @ObservedObject var model: GalleryModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("设置").font(.system(size: 21, weight: .semibold)); Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction).controlSize(.regular) }.padding(24)
            Form {
                Section("外观") {
                    Picker("显示模式", selection: $model.theme) {
                        ForEach(GalleryTheme.allCases) { theme in Label(theme.title, systemImage: theme.symbol).tag(theme) }
                    }.pickerStyle(.segmented)
                }
                Section("浏览") {
                    Toggle("显示图片名称", isOn: $model.showFilenames)
                    Toggle("显示底部缩略图", isOn: $model.showFilmstrip)
                    Picker("缩略图大小", selection: $model.thumbnailSize) {
                        ForEach(ThumbnailSize.allCases) { size in Text(size.title).tag(size) }
                    }.pickerStyle(.segmented)
                }
                Section("幻灯片") {
                    Picker("切换间隔", selection: $model.slideshowInterval) { ForEach([2.0, 3, 5, 8, 10], id: \.self) { Text("\(Int($0)) 秒").tag($0) } }
                    Toggle("循环播放", isOn: $model.loopPlayback)
                }
                Section("更多") {
                    Button("新建相册…") { nextSheet { model.showNewAlbum = true } }
                    Button("打开示例图库") { dismiss(); model.loadSamples() }
                    Button("快捷键与使用帮助") { nextSheet { model.showHelp = true } }
                }
            }.formStyle(.grouped).controlSize(.regular).font(.system(size: 14))
        }.frame(width: 470, height: 570).tint(Palette.mint).preferredColorScheme(model.theme.colorScheme)
    }
    private func nextSheet(_ action: @escaping () -> Void) { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: action) }
}

struct HelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let shortcuts = [("打开图片", "⌘ O"), ("上一张 / 下一张", "← / →"), ("播放 / 暂停幻灯片", "空格"), ("放大 / 缩小", "+ / −"), ("适应窗口 / 实际大小", "⌘ 0 / ⌘ 1"), ("收藏 / 取消收藏", "F"), ("裁剪 / 旋转", "C / R"), ("导出图片副本", "⌘ S"), ("撤销 / 重做", "⌘ Z / ⇧ ⌘ Z"), ("显示或隐藏详情", "⌘ I"), ("返回图库 / 退出全屏", "Esc")]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("快捷键与使用帮助").font(.system(size: 22, weight: .medium))
            Text("从 Finder 选择「打开方式 → 熊猫图库」，或直接把图片拖入窗口。自动按文件名自然排序，同目录下一张无需选择文件夹。").font(.system(size: 14)).foregroundStyle(Palette.muted).lineSpacing(5)
            VStack(spacing: 0) { ForEach(shortcuts, id: \.0) { item in HStack { Text(item.0); Spacer(); Text(item.1).font(.system(size: 13, design: .monospaced)).foregroundStyle(Palette.mint) }.font(.system(size: 13)).padding(.vertical, 8).overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) } } }
            Text("触控板双指捏合可缩放；放大后拖动画面或双指滑动可移动。双击图片切换实际大小。").font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(4)
            HStack { Spacer(); Button("知道了") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 440)
    }
}
