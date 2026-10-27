import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Disambiguates the property wrapper from newer SDK State macros.
typealias ViewState<Value> = SwiftUI.State<Value>

struct ContentView: View {
    @ObservedObject var model: GalleryModel
    @ViewState private var isDropTargeted = false
    @ViewState private var newAlbumName = ""
    @ViewState private var readerHovered = false
    @FocusState private var searchFocused: Bool
    private var sidebarVisible: Bool { model.showSidebar && model.mode == .grid }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible { sidebar }
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(Palette.line).frame(height: 0.5)
                HStack(spacing: 0) {
                    if model.mode == .grid { gallery } else { reader }
                    if model.showInspector {
                        Rectangle().fill(Palette.line).frame(width: 0.5)
                        InspectorView(model: model).frame(width: 262)
                    }
                }
            }
        }
        .background(Palette.background).foregroundStyle(Palette.text).font(.system(size: 15))
        .tint(Palette.mint).preferredColorScheme(model.theme.colorScheme).ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Label(toast, systemImage: "checkmark.circle")
                    .font(.system(size: 14)).foregroundStyle(Palette.text)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line))
                    .padding(.bottom, 22).allowsHitTesting(false)
            }
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    Palette.background.opacity(0.96)
                    VStack(spacing: 14) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 44, weight: .ultraLight))
                        Text("松开以打开图片").font(.system(size: 20, weight: .medium))
                    }.foregroundStyle(Palette.mint)
                }.padding(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.mint, style: StrokeStyle(lineWidth: 1.5, dash: [6])).padding(12)).allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: openDrop)
        .sheet(isPresented: $model.showExport) { ExportSheet(model: model) }
        .sheet(isPresented: $model.showSettings) { SettingsSheet(model: model) }
        .sheet(isPresented: $model.showHelp) { HelpSheet() }
        .sheet(isPresented: $model.showNewAlbum) {
            VStack(alignment: .leading, spacing: 20) {
                Text("新建相册").font(.system(size: 22, weight: .medium))
                TextField("相册名称", text: $newAlbumName).textFieldStyle(.roundedBorder).onSubmit(createAlbum)
                HStack { Spacer(); Button("取消") { model.showNewAlbum = false }.keyboardShortcut(.cancelAction); Button("创建", action: createAlbum).keyboardShortcut(.defaultAction).disabled(newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(28).frame(width: 340)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusGallerySearch)) { _ in
            model.mode = .grid; searchFocused = true
        }
    }

    private func openDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                var directory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue {
                    if let first = try? GalleryFiles.images(in: url).first { model.open(first) }
                    else { model.notify("这个文件夹中没有图片") }
                } else { model.open(url) }
            }
        }
        return true
    }

    private func createAlbum() {
        guard !newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.createAlbum(name: newAlbumName); newAlbumName = ""; model.showNewAlbum = false
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("图库").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.muted)
                .padding(.leading, 12).padding(.top, 62).padding(.bottom, 14)
            navigationRow("全部图片", icon: "square.grid.2x2", id: "all")
            navigationRow("最近打开", icon: "clock", id: "recent")
            navigationRow("收藏", icon: "heart", id: "favorites")
            if !model.albums.isEmpty {
                Text("相册").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.muted).padding(.leading, 12).padding(.top, 26).padding(.bottom, 10)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(model.albums) { album in
                            navigationRow(album.name, icon: "rectangle.stack", id: "album:\(album.id)")
                                .contextMenu { Button("删除相册", role: .destructive) { model.removeAlbum(album) } }
                        }
                    }
                }.scrollIndicators(.hidden)
            }
            Spacer(minLength: 20)
            Button { model.showSettings = true } label: {
                Label("设置", systemImage: "gearshape").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.bottom, 15)
        }.padding(.horizontal, 12).frame(width: 174).background(Palette.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 0.5) }
    }

    private func navigationRow(_ title: String, icon: String, id: String) -> some View {
        Button { model.changeSection(id); model.showInspector = false } label: {
            Label(title, systemImage: icon).font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .foregroundStyle(model.section == id ? Palette.mint : Palette.text.opacity(0.78))
            .background(model.section == id ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if model.mode == .grid {
                IconButton(symbol: "sidebar.left", help: "显示或隐藏导航", active: false) { model.showSidebar.toggle() }
                Text(model.sectionTitle).font(.system(size: 16, weight: .semibold))
                Text("\(model.visiblePhotos.count) 张").font(.system(size: 13)).foregroundStyle(Palette.muted)
            } else {
                IconButton(symbol: "chevron.left", help: "返回图库（Esc）") { returnToGrid() }
                Text(model.selected?.name ?? "图片").font(.system(size: 14)).lineLimit(1)
                if model.hasUnsavedEdits { Circle().fill(Palette.mint).frame(width: 5, height: 5).help("编辑尚未导出") }
                Text(model.positionText).font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 15)
            if model.mode == .grid {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Palette.muted)
                    TextField("搜索", text: $model.query).font(.system(size: 13)).textFieldStyle(.plain).focused($searchFocused)
                    if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(Palette.muted) }
                }.padding(.horizontal, 10).frame(width: 175, height: 28)
                    .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 6))
                Button(action: model.openPanel) { Label("打开", systemImage: "plus").font(.system(size: 13)) }
                    .buttonStyle(.bordered).controlSize(.regular).help("打开一张图片并浏览同目录图片（⌘O）")
            } else {
                IconButton(symbol: model.isFavorite ? "heart.fill" : "heart", help: "收藏（F）", active: model.isFavorite) { model.toggleFavorite() }
                Button {
                    if model.showInspector && model.tool != .info { model.showInspector = false; model.tool = .info }
                    else { model.beginEditing(.adjust) }
                } label: { Text(model.showInspector && model.tool != .info ? "完成" : "编辑").font(.system(size: 13)) }
                    .buttonStyle(.bordered).controlSize(.regular).disabled(model.edit == nil)
            }
            moreMenu
        }
        .padding(.leading, sidebarVisible ? 20 : 86).padding(.trailing, 20).frame(height: 60)
        .background(Palette.background)
    }

    private var moreMenu: some View {
        Menu {
            if model.mode == .grid {
                Picker("排序", selection: $model.sort) { ForEach(GalleryModel.SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("格式", selection: $model.formatFilter) { ForEach(["全部格式", "JPG", "PNG", "其他"], id: \.self) { Text($0).tag($0) } }
                Divider()
                Button("播放幻灯片", action: model.toggleSlideshow).disabled(model.visiblePhotos.isEmpty)
                Button("新建相册…") { model.showNewAlbum = true }
            } else {
                Button("打开其他图片…", action: model.openPanel)
                Button("导出副本…") { model.requestExport() }
                Button("在 Finder 中显示", action: model.revealInFinder)
                Divider()
                Toggle("底部缩略图", isOn: $model.showFilmstrip)
                Button("全屏") { model.window?.toggleFullScreen(nil) }
            }
            Button(model.showInspector ? "隐藏图片信息" : "图片信息") { model.tool = .info; model.showInspector.toggle() }
            Divider()
            Button("设置…") { model.stopSlideshow(); model.showSettings = true }
        } label: { Image(systemName: "ellipsis").font(.system(size: 17)).foregroundStyle(Palette.muted).frame(width: 27, height: 28) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("更多选项").accessibilityLabel("更多选项")
    }

    private var gallery: some View {
        ScrollView {
            if model.visiblePhotos.isEmpty {
                ContentUnavailableView(model.query.isEmpty ? "还没有图片" : "未找到图片", systemImage: model.section == "favorites" ? "heart" : "photo", description: Text(model.query.isEmpty ? "打开一张图片，或将图片拖到这里。" : "试试其他名称或图片格式。"))
                    .padding(.top, 130).frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: model.gridSize, maximum: 520), spacing: 12)], spacing: 12) {
                    ForEach(model.visiblePhotos) { photo in
                        PhotoCard(photo: photo, selected: model.selected?.id == photo.id, favorite: model.favorites.contains(photo.id), showFilename: model.showFilenames, onSelect: { model.select(photo) }, onOpen: { model.select(photo, showViewer: true) }, onFavorite: { model.toggleFavorite(photo) })
                            .contextMenu {
                                Button("打开") { model.select(photo, showViewer: true) }
                                Button(model.favorites.contains(photo.id) ? "取消收藏" : "收藏") { model.toggleFavorite(photo) }
                                if !model.albums.isEmpty { Menu("添加到相册") { ForEach(model.albums) { album in Button(album.name) { model.addToAlbum(album.id, photo: photo) } } } }
                                Divider()
                                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([photo.url]) }
                            }
                    }
                }.padding(20)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay { if model.isLoading && model.photos.isEmpty { ProgressView().controlSize(.regular) } }
    }

    private func returnToGrid() { model.stopSlideshow(); model.mode = .grid; model.tool = .info; model.showInspector = false }

    private var reader: some View {
        VStack(spacing: 0) {
            ZStack {
                ImageCanvas(model: model)
                if readerHovered && model.visiblePhotos.count > 1 {
                    HStack {
                        readerArrow("chevron.left", help: "上一张（←）", disabled: model.selectedIndex == 0) { model.navigate(-1) }
                        Spacer()
                        readerArrow("chevron.right", help: "下一张（→）", disabled: model.selectedIndex == model.visiblePhotos.count - 1) { model.navigate(1) }
                    }.padding(.horizontal, 15)
                }
                if model.isLoading { ProgressView().padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9)) }
                if model.isComparing { Text("原图").font(.system(size: 13)).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(15) }
                if model.displayedImage == nil && !model.isLoading { ContentUnavailableView("打开一张图片", systemImage: "photo", description: Text("拖入图片，或按 ⌘O 打开。")) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).onHover { readerHovered = $0 }
            HStack(spacing: 5) {
                IconButton(symbol: "minus", help: "缩小（−）") { model.zoom(1 / 1.25) }
                Menu {
                    Button("适应窗口", action: model.fitImage)
                    Button("实际大小") { model.zoomScale = 1; model.panOffset = .zero }
                    Button("200%") { model.zoomScale = 2; model.panOffset = .zero }
                } label: { Text(model.zoomScale.map { "\(Int($0 * 100))%" } ?? "适应").font(.system(size: 12)).foregroundStyle(Palette.muted).frame(minWidth: 42) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                IconButton(symbol: "plus", help: "放大（+）") { model.zoom(1.25) }
                Spacer()
                if model.historyIndex > 0 {
                    Text("对比原图").font(.system(size: 12)).foregroundStyle(model.isComparing ? Palette.mint : Palette.muted).padding(.horizontal, 10).padding(.vertical, 8).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in model.isComparing = true }.onEnded { _ in model.isComparing = false })
                }
                IconButton(symbol: model.isPlaying ? "pause.fill" : "play", help: "幻灯片（空格）", active: model.isPlaying, action: model.toggleSlideshow)
            }.padding(.horizontal, 19).frame(height: 39).background(Palette.background)
            if model.showFilmstrip { filmstrip }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func readerArrow(_ symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Palette.text).frame(width: 32, height: 32).background(.regularMaterial, in: Circle()) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help).disabled(disabled).opacity(disabled ? 0.3 : 0.85)
    }

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(model.visiblePhotos) { photo in
                        ThumbnailView(url: photo.url).frame(width: 65, height: 43).clipped().clipShape(RoundedRectangle(cornerRadius: 4)).padding(3)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(model.selected?.id == photo.id ? Palette.mint : .clear, lineWidth: 1.5))
                            .opacity(model.selected?.id == photo.id ? 1 : 0.55).onTapGesture { model.select(photo, showViewer: true) }.help(photo.name).id(photo.id)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 8)
            }.scrollIndicators(.hidden).frame(height: 65).background(Palette.background)
                .onChange(of: model.selected?.id) { _, id in if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } } }
                .onAppear { if let id = model.selected?.id { proxy.scrollTo(id, anchor: .center) } }
        }
    }
}

struct ThumbnailView: View {
    let url: URL
    @ViewState private var image: NSImage?
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.card
                if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                else { Image(systemName: "photo").foregroundStyle(Palette.muted) }
            }
        }.task(id: url) { let result = await Task.detached(priority: .utility) { ThumbnailCache.shared.image(for: url) }.value; if !Task.isCancelled { image = result } }
    }
}

struct PhotoCard: View {
    let photo: PhotoItem
    let selected: Bool
    let favorite: Bool
    let showFilename: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onFavorite: () -> Void
    @ViewState private var hovered = false
    var body: some View {
        ThumbnailView(url: photo.url).aspectRatio(1.5, contentMode: .fit)
            .overlay(alignment: .bottomLeading) {
                if hovered || showFilename {
                    Text(photo.name).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 11).padding(.top, 20).padding(.bottom, 10)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(alignment: .topTrailing) {
                if favorite || hovered {
                    Button(action: onFavorite) {
                        Image(systemName: favorite ? "heart.fill" : "heart").font(.system(size: 14)).foregroundStyle(.white)
                            .frame(width: 25, height: 25).background(.black.opacity(0.25), in: Circle())
                    }.buttonStyle(.plain).help(favorite ? "取消收藏" : "收藏").padding(9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Palette.mint : .clear, lineWidth: 2))
            .padding(2).contentShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture(count: 2, perform: onOpen).onTapGesture(perform: onSelect).onHover { hovered = $0 }
            .accessibilityElement(children: .contain).accessibilityLabel(photo.name).accessibilityAddTraits(.isButton)
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(active ? Palette.mint : Palette.muted)
                .frame(width: 28, height: 28).background(active ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}

struct AccentButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).frame(height: 32).foregroundStyle(Palette.onAccent).background(Palette.mint, in: RoundedRectangle(cornerRadius: 6)) }.buttonStyle(.plain)
    }
}

extension Notification.Name { static let focusGallerySearch = Notification.Name("focusGallerySearch") }
