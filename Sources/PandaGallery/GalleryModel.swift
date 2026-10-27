import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class GalleryModel: ObservableObject {
    static let shared = GalleryModel()
    @Published var photos: [PhotoItem] = []
    @Published var selected: PhotoItem?
    @Published var displayedImage: NSImage?
    @Published var originalImage: CGImage?
    @Published var mode: ViewMode = .grid
    @Published var section = "all"
    @Published var query = ""
    @Published var formatFilter = "全部格式"
    @Published var sort: SortOrder = .name
    @Published var showInspector = false
    @Published var showSidebar = true
    @Published var theme = GalleryTheme.restored(from: .standard) {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "appearanceMode"); applyAppearance() }
    }
    @Published var showFilenames = UserDefaults.standard.object(forKey: "showFilenames") as? Bool ?? false {
        didSet { UserDefaults.standard.set(showFilenames, forKey: "showFilenames") }
    }
    @Published var showFilmstrip = UserDefaults.standard.object(forKey: "showFilmstrip") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFilmstrip, forKey: "showFilmstrip") }
    }
    @Published var isLoading = false
    @Published var hasUnsavedEdits = false
    @Published var isRendering = false
    @Published var favorites: Set<String>
    @Published var recentPaths: [String]
    @Published var albums: [PhotoAlbum]
    @Published var edit: EditState?
    @Published var tool: EditorTool = .info
    @Published var cropRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @Published var cropAspect: CGFloat? = nil
    @Published var zoomScale: CGFloat? = nil
    @Published var canvasFitScale: CGFloat = 1
    @Published var panOffset = CGSize.zero
    @Published var isComparing = false
    @Published var historyIndex = 0
    @Published var historyCount = 0
    @Published var isPlaying = false
    @Published var toast: String?
    @Published var showExport = false
    @Published var showSettings = false
    @Published var showHelp = false
    @Published var showNewAlbum = false
    @Published var directoryName = "示例图库"
    @Published var isDemo = false
    @Published var thumbnailSize = ThumbnailSize.restored(from: .standard) {
        didSet { UserDefaults.standard.set(thumbnailSize.rawValue, forKey: "thumbnailSize") }
    }
    var gridSize: Double { thumbnailSize.minimumWidth }
    @Published var slideshowInterval = max(2, UserDefaults.standard.double(forKey: "slideshowInterval")) {
        didSet { UserDefaults.standard.set(slideshowInterval, forKey: "slideshowInterval"); if isPlaying { restartSlideshow() } }
    }
    @Published var loopPlayback = UserDefaults.standard.object(forKey: "loopPlayback") as? Bool ?? true {
        didSet { UserDefaults.standard.set(loopPlayback, forKey: "loopPlayback") }
    }
    weak var window: NSWindow?
    private var index: [String: PhotoItem] = [:]
    private var history: [EditState] = []
    private var timer: Timer?
    private var toastTask: Task<Void, Never>?
    private var openTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?
    private var generation = 0
    private var renderGeneration = 0
    private var renderedCGImage: CGImage?
    private var exportCompletion: (() -> Void)?
    private var exportCancellation: (() -> Void)?

    enum ViewMode { case grid, viewer }
    enum EditorTool: String, CaseIterable { case info = "详情", adjust = "调整", crop = "裁剪", filter = "滤镜" }
    enum SortOrder: String, CaseIterable { case name = "名称", date = "修改时间", size = "文件大小" }

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favoritePaths") ?? [])
        recentPaths = UserDefaults.standard.stringArray(forKey: "recentPaths") ?? []
        albums = (UserDefaults.standard.data(forKey: "albums").flatMap { try? JSONDecoder().decode([PhotoAlbum].self, from: $0) }) ?? []
        for path in Set(recentPaths).union(favorites).union(albums.flatMap(\.paths)) where FileManager.default.fileExists(atPath: path) {
            index[path] = PhotoItem(url: URL(fileURLWithPath: path))
        }
        UserDefaults.standard.set(thumbnailSize.rawValue, forKey: "thumbnailSize")
        UserDefaults.standard.removeObject(forKey: "gridSize")
    }

    func applyAppearance() {
        NSApp.appearance = theme.appearance
        window?.appearance = theme.appearance
        window?.backgroundColor = NSColor(Palette.background)
        window?.contentView?.needsDisplay = true
    }

    var visiblePhotos: [PhotoItem] {
        var items: [PhotoItem]
        if section == "favorites" { items = favorites.compactMap { index[$0] } }
        else if section == "recent" { items = recentPaths.compactMap { index[$0] } }
        else if section.hasPrefix("album:"), let album = albums.first(where: { "album:\($0.id)" == section }) { items = album.paths.compactMap { index[$0] } }
        else { items = photos }
        if !query.isEmpty { items = items.filter { $0.name.localizedCaseInsensitiveContains(query) } }
        if formatFilter != "全部格式" {
            items = items.filter {
                if formatFilter == "JPG" { return ["JPG", "JPEG"].contains($0.format) }
                if formatFilter == "其他" { return !["JPG", "JPEG", "PNG"].contains($0.format) }
                return $0.format == formatFilter
            }
        }
        return items.sorted {
            switch sort {
            case .name: return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            case .date: return $0.date == $1.date ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.date > $1.date
            case .size: return $0.bytes == $1.bytes ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.bytes > $1.bytes
            }
        }
    }
    var sectionTitle: String {
        if section == "favorites" { return "我的收藏" }
        if section == "recent" { return "最近打开" }
        if section.hasPrefix("album:") { return albums.first(where: { "album:\($0.id)" == section })?.name ?? "相册" }
        return "全部图片"
    }
    var selectedIndex: Int? { visiblePhotos.firstIndex(where: { $0.id == selected?.id }) }
    var positionText: String { guard let idx = selectedIndex else { return "\(visiblePhotos.count) 张图片" }; return "\(idx + 1) / \(visiblePhotos.count)" }
    var canUndo: Bool { historyIndex > 0 }
    var canRedo: Bool { historyIndex + 1 < history.count }
    var isFavorite: Bool { selected.map { favorites.contains($0.id) } ?? false }
    var effectiveImage: NSImage? {
        if isComparing, let originalImage { return NSImage(cgImage: originalImage, size: NSSize(width: originalImage.width, height: originalImage.height)) }
        return displayedImage
    }

    func start() {
        if let arg = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }), FileManager.default.fileExists(atPath: arg) {
            open(URL(fileURLWithPath: arg)); return
        }
        if let path = UserDefaults.standard.string(forKey: "lastImage"), FileManager.default.fileExists(atPath: path) {
            open(URL(fileURLWithPath: path), showViewer: false)
        } else { loadSamples() }
    }

    func openPanel() {
        stopSlideshow()
        let panel = NSOpenPanel()
        panel.title = "打开图片"
        panel.message = "只需选择一张图片，即可浏览同目录中的其他图片。"
        panel.prompt = "打开图片"
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.open(url) }
        }
    }

    func open(_ url: URL, showViewer: Bool = true) {
        guard GalleryFiles.isImage(url) else { showError("请选择图片文件。支持 JPEG、PNG、HEIC、GIF、TIFF、WebP 及系统支持的 RAW 格式。"); return }
        confirmLeavingEdits { [weak self] in self?.performOpen(url, showViewer: showViewer) }
    }

    private func performOpen(_ source: URL, showViewer: Bool) {
        let url = source.standardizedFileURL.resolvingSymlinksInPath()
        stopSlideshow()
        generation += 1
        let request = generation
        openTask?.cancel()
        renderTask?.cancel()
        isLoading = true
        query = ""; formatFilter = "全部格式"; section = "all"
        mode = showViewer ? .viewer : .grid
        tool = .info
        showInspector = false
        let demoRoot = Self.resourceURL.appendingPathComponent("Samples").standardizedFileURL.path
        isDemo = url.standardizedFileURL.path.hasPrefix(demoRoot + "/")
        directoryName = isDemo ? "示例图库" : url.deletingLastPathComponent().lastPathComponent
        let demo = isDemo
        openTask = Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) { () -> ([PhotoItem], CGImage, Bool) in
                    let cg = try ImageEngine.load(url)
                    let siblings = try? GalleryFiles.siblings(of: url)
                    var urls = siblings ?? [url]
                    if !urls.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) { urls.append(url) }
                    return (urls.map(PhotoItem.init), cg, siblings == nil)
                }.value
                guard request == generation, !Task.isCancelled else { return }
                photos = result.0
                for item in photos { index[item.id] = item }
                let photo = index[url.standardizedFileURL.path] ?? PhotoItem(url: url)
                acceptLoaded(photo, image: result.1)
                isLoading = false
                if !demo { remember(photo) }
                if result.2 { notify("目录访问受限，当前仅显示已打开的图片。请检查系统的文件访问权限。") }
            } catch {
                guard request == generation else { return }
                isLoading = false
                showError(error.localizedDescription)
            }
        }
    }

    func select(_ photo: PhotoItem, showViewer: Bool = false) {
        if selected?.id == photo.id { if showViewer { mode = .viewer }; return }
        confirmLeavingEdits { [weak self] in self?.loadSelection(photo, showViewer: showViewer) }
    }

    private func loadSelection(_ photo: PhotoItem, showViewer: Bool) {
        generation += 1
        let request = generation
        openTask?.cancel(); renderTask?.cancel()
        selected = photo
        isLoading = true
        if showViewer { mode = .viewer }
        openTask = Task {
            do {
                let image = try await Task.detached(priority: .userInitiated) { try ImageEngine.load(photo.url) }.value
                guard request == generation, !Task.isCancelled else { return }
                acceptLoaded(photo, image: image)
                isLoading = false
                if !isDemo { remember(photo) }
            } catch {
                guard request == generation else { return }
                isLoading = false
                displayedImage = nil; originalImage = nil; edit = nil; history = []; syncHistory()
                hasUnsavedEdits = false
                showError(error.localizedDescription)
            }
        }
    }

    private func acceptLoaded(_ photo: PhotoItem, image: CGImage) {
        renderGeneration += 1
        let demoPath = Self.resourceURL.appendingPathComponent("Samples").standardizedFileURL.resolvingSymlinksInPath().path
        isDemo = photo.url.path.hasPrefix(demoPath + "/")
        selected = photo
        originalImage = image
        edit = EditState(base: image)
        renderedCGImage = image
        displayedImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        history = [EditState(base: image)]; historyIndex = 0; syncHistory()
        hasUnsavedEdits = false; isRendering = false; isComparing = false
        zoomScale = nil; panOffset = .zero
        resetCrop()
        window?.subtitle = isDemo ? "示例图库" : photo.url.deletingLastPathComponent().path
        window?.representedURL = isDemo ? nil : photo.url
    }

    func navigate(_ offset: Int) {
        guard !isLoading, !visiblePhotos.isEmpty else { return }
        guard let current = selectedIndex else { select(visiblePhotos[0], showViewer: true); return }
        guard let next = GalleryFiles.neighbor(index: current, count: visiblePhotos.count, offset: offset, wrap: isPlaying && loopPlayback) else {
            if isPlaying { stopSlideshow() }
            notify(offset > 0 ? "已经是最后一张" : "已经是第一张"); return
        }
        select(visiblePhotos[next], showViewer: true)
    }

    func changeSection(_ value: String) {
        confirmLeavingEdits { [weak self] in
            guard let self else { return }
            self.stopSlideshow(); self.section = value; self.query = ""; self.formatFilter = "全部格式"; self.mode = .grid
            if let first = self.visiblePhotos.first, !self.visiblePhotos.contains(where: { $0.id == self.selected?.id }) { self.loadSelection(first, showViewer: false) }
        }
    }

    func toggleFavorite(_ photo: PhotoItem? = nil) {
        guard let photo = photo ?? selected else { return }
        index[photo.id] = photo
        if favorites.contains(photo.id) { favorites.remove(photo.id) } else { favorites.insert(photo.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "favoritePaths")
    }

    func createAlbum(name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        guard !albums.contains(where: { $0.name == clean }) else { notify("已存在同名相册"); return }
        albums.append(PhotoAlbum(name: clean)); persistAlbums(); notify("已创建相册「\(clean)」")
    }

    func addToAlbum(_ id: UUID, photo: PhotoItem? = nil) {
        guard let photo = photo ?? selected, let albumIndex = albums.firstIndex(where: { $0.id == id }) else { return }
        if !albums[albumIndex].paths.contains(photo.id) { albums[albumIndex].paths.append(photo.id); index[photo.id] = photo; persistAlbums(); notify("已添加到「\(albums[albumIndex].name)」") }
    }

    func removeAlbum(_ album: PhotoAlbum) {
        let alert = NSAlert(); alert.messageText = "删除相册「\(album.name)」？"; alert.informativeText = "只删除相册分组，图片文件会保留。"; alert.addButton(withTitle: "删除相册"); alert.addButton(withTitle: "取消")
        present(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.albums.removeAll { $0.id == album.id }; self.persistAlbums()
            if self.section == "album:\(album.id)" { self.section = "all" }
        }
    }

    private func persistAlbums() { UserDefaults.standard.set(try? JSONEncoder().encode(albums), forKey: "albums") }

    private func remember(_ photo: PhotoItem) {
        index[photo.id] = photo
        recentPaths.removeAll { $0 == photo.id }; recentPaths.insert(photo.id, at: 0)
        recentPaths = Array(recentPaths.prefix(40))
        UserDefaults.standard.set(recentPaths, forKey: "recentPaths")
        UserDefaults.standard.set(photo.id, forKey: "lastImage")
        NSDocumentController.shared.noteNewRecentDocumentURL(photo.url)
    }

    static var resourceURL: URL {
        if let url = Bundle.main.resourceURL, FileManager.default.fileExists(atPath: url.appendingPathComponent("Samples").path) { return url }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")
    }

    func loadSamples() {
        let directory = Self.resourceURL.appendingPathComponent("Samples")
        guard let first = try? GalleryFiles.images(in: directory).first else { return }
        open(first, showViewer: false)
    }

    func beginEditing(_ target: EditorTool) {
        guard selected != nil, edit != nil else { return }
        stopSlideshow(); mode = .viewer; showInspector = true; tool = target
        if target == .crop { zoomScale = nil; panOffset = .zero; resetCrop() }
    }

    func adjust(_ keyPath: WritableKeyPath<EditState, Double>, value: Double) {
        guard edit != nil else { return }
        stopSlideshow(); edit?[keyPath: keyPath] = value; hasUnsavedEdits = true; render()
    }

    func preset(_ preset: PhotoPreset) { edit?.preset = preset; commitEdit(); render() }

    func transform(_ orientation: CGImagePropertyOrientation) {
        guard let edit, let transformed = ImageEngine.transform(edit.base, orientation: orientation) else { return }
        stopSlideshow(); self.edit?.base = transformed; zoomScale = nil; panOffset = .zero; resetCrop(); commitEdit(); render()
    }

    func resetAdjustments() {
        edit?.brightness = 0; edit?.contrast = 1; edit?.saturation = 1; commitEdit(); render()
    }

    func resetCrop(aspect: CGFloat? = nil) {
        cropAspect = aspect
        guard let edit else { return }
        cropRect = CropGeometry.fittedRect(imageSize: CGSize(width: edit.base.width, height: edit.base.height), aspect: aspect)
    }

    func applyCrop() {
        guard let edit else { return }
        let rect = CropGeometry.pixelRect(normalized: cropRect, width: edit.base.width, height: edit.base.height, aspect: cropAspect)
        guard rect.width >= 2, rect.height >= 2, let cropped = edit.base.cropping(to: rect) else { notify("裁剪范围过小，请重新选择。"); return }
        self.edit?.base = cropped; zoomScale = nil; panOffset = .zero; resetCrop(aspect: cropAspect); commitEdit(); render(); tool = .adjust
        notify("裁剪已应用，可撤销或导出副本")
    }

    func commitEdit() {
        guard let edit else { return }
        if history.indices.contains(historyIndex), edit.matches(history[historyIndex]) { return }
        history = Array(history.prefix(historyIndex + 1)); history.append(edit)
        let pixelCount = max(1, edit.base.width * edit.base.height)
        let historyLimit = min(24, max(2, 128_000_000 / pixelCount))
        while history.count > historyLimit { history.removeFirst() }
        historyIndex = history.count - 1; syncHistory(); hasUnsavedEdits = true; stopSlideshow()
    }

    func undo() {
        commitEdit()
        guard canUndo else { return }
        historyIndex -= 1; edit = history[historyIndex]; syncHistory(); hasUnsavedEdits = true; resetCrop(); render()
    }

    func redo() {
        guard canRedo else { return }
        historyIndex += 1; edit = history[historyIndex]; syncHistory(); hasUnsavedEdits = true; resetCrop(); render()
    }

    func resetEdits() {
        guard let originalImage else { return }
        edit = EditState(base: originalImage); commitEdit(); render(); resetCrop(); notify("已恢复原始图片")
    }

    private func syncHistory() { historyCount = history.count }

    private func render() {
        guard let snapshot = edit else { return }
        renderGeneration += 1
        let request = renderGeneration
        renderTask?.cancel(); isRendering = true
        renderTask = Task {
            let result = await Task.detached(priority: .userInitiated) { ImageEngine.render(snapshot) }.value
            guard request == renderGeneration, !Task.isCancelled else { return }
            isRendering = false
            if let result {
                renderedCGImage = result
                displayedImage = NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
            } else { showError("无法完成图片调整，请撤销后重试。") }
        }
    }

    func fitImage() { zoomScale = nil; panOffset = .zero }
    func zoom(_ multiplier: CGFloat) {
        zoomScale = min(8, max(0.02, (zoomScale ?? canvasFitScale) * multiplier))
    }

    func toggleSlideshow() {
        if isPlaying { stopSlideshow(); return }
        guard !visiblePhotos.isEmpty else { notify("请先打开图片"); return }
        confirmLeavingEdits { [weak self] in
            guard let self else { return }
            self.hasUnsavedEdits = false; self.mode = .viewer; self.tool = .info; self.showInspector = false
            if self.selectedIndex == nil, let first = self.visiblePhotos.first { self.loadSelection(first, showViewer: true) }
            self.isPlaying = true; self.restartSlideshow()
        }
    }

    private func restartSlideshow() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: slideshowInterval, repeats: true) { [weak self] _ in Task { @MainActor in self?.navigate(1) } }
    }

    func stopSlideshow() { timer?.invalidate(); timer = nil; isPlaying = false }

    func requestExport(after completion: (() -> Void)? = nil, onCancel: (() -> Void)? = nil) {
        guard edit != nil, !isLoading else { return }
        commitEdit(); stopSlideshow(); exportCompletion = completion; exportCancellation = onCancel; showExport = true
    }

    func cancelExport() {
        showExport = false
        let cancellation = exportCancellation
        exportCancellation = nil; exportCompletion = nil
        cancellation?()
    }

    func export(format: ExportFormat, quality: Double) {
        guard let snapshot = edit, let selected else { return }
        showExport = false
        let panel = NSSavePanel()
        panel.title = "导出图片副本"; panel.prompt = "导出"
        panel.allowedContentTypes = [format.type]
        panel.nameFieldStringValue = selected.url.deletingPathExtension().lastPathComponent + "_已编辑." + format.ext
        panel.canCreateDirectories = true
        if !isDemo { panel.directoryURL = selected.url.deletingLastPathComponent() }
        panel.begin { [weak self] response in
            Task { @MainActor in
                guard let self else { return }
                guard response == .OK, let url = panel.url else { self.cancelExport(); return }
                if url.standardizedFileURL.resolvingSymlinksInPath() == selected.url.standardizedFileURL.resolvingSymlinksInPath() {
                    self.showError("为保护原始图片，请使用不同的文件名导出副本。"); self.cancelExport(); return
                }
                self.isRendering = true
                do {
                    try await Task.detached(priority: .userInitiated) {
                        guard let image = ImageEngine.render(snapshot) else { throw ImageError.exportFailed }
                        try ImageEngine.export(image, to: url, format: format, quality: quality)
                    }.value
                    self.isRendering = false; self.hasUnsavedEdits = false
                    self.notify("已导出：\(url.lastPathComponent)")
                    let completion = self.exportCompletion; self.exportCompletion = nil; self.exportCancellation = nil; completion?()
                } catch { self.isRendering = false; self.cancelExport(); self.showError(error.localizedDescription) }
            }
        }
    }

    func revealInFinder() { guard let selected else { return }; NSWorkspace.shared.activateFileViewerSelecting([selected.url]) }

    func trashSelected() {
        guard let selected else { return }
        guard !isDemo else { notify("内置示例用于体验，请先打开你自己的图片。"); return }
        stopSlideshow()
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "将「\(selected.name)」移至废纸篓？"
        alert.informativeText = "文件将从当前目录移除，之后可以从 macOS 废纸篓恢复。"; alert.addButton(withTitle: "移至废纸篓"); alert.addButton(withTitle: "取消")
        present(alert) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do {
                let previous = self.visiblePhotos; let idx = self.selectedIndex ?? 0
                try FileManager.default.trashItem(at: selected.url, resultingItemURL: nil)
                self.photos.removeAll { $0.id == selected.id }; self.index.removeValue(forKey: selected.id)
                self.favorites.remove(selected.id); self.recentPaths.removeAll { $0 == selected.id }
                UserDefaults.standard.set(Array(self.favorites), forKey: "favoritePaths"); UserDefaults.standard.set(self.recentPaths, forKey: "recentPaths")
                self.hasUnsavedEdits = false
                let remaining = previous.filter { $0.id != selected.id }
                if !remaining.isEmpty { self.loadSelection(remaining[min(idx, remaining.count - 1)], showViewer: self.mode == .viewer) }
                else { self.selected = nil; self.displayedImage = nil; self.originalImage = nil; self.edit = nil; self.mode = .grid }
                self.notify("图片已移至废纸篓")
            } catch { self.showError(error.localizedDescription) }
        }
    }

    func confirmLeavingEdits(onCancel: (() -> Void)? = nil, _ action: @escaping () -> Void) {
        guard hasUnsavedEdits else { action(); return }
        stopSlideshow()
        let alert = NSAlert(); alert.messageText = "是否保留当前图片的编辑？"; alert.informativeText = "你可以先导出副本。原始图片不会被修改。"
        alert.addButton(withTitle: "导出副本"); alert.addButton(withTitle: "放弃更改"); alert.addButton(withTitle: "取消")
        present(alert) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn { self.requestExport(after: action, onCancel: onCancel) }
            else if response == .alertSecondButtonReturn {
                self.renderTask?.cancel(); self.renderGeneration += 1; self.isRendering = false
                self.hasUnsavedEdits = false
                if let original = self.originalImage {
                    self.edit = EditState(base: original); self.renderedCGImage = original
                    self.displayedImage = NSImage(cgImage: original, size: NSSize(width: original.width, height: original.height))
                    self.history = [EditState(base: original)]; self.historyIndex = 0; self.syncHistory()
                }
                action()
            } else { onCancel?() }
        }
    }

    func notify(_ text: String) {
        toastTask?.cancel(); toast = text
        toastTask = Task { try? await Task.sleep(for: .seconds(3.5)); guard !Task.isCancelled else { return }; toast = nil }
    }
    func showError(_ text: String) {
        let alert = NSAlert(); alert.alertStyle = .warning; alert.messageText = "熊猫图库"; alert.informativeText = text; alert.addButton(withTitle: "好")
        present(alert) { _ in }
    }
    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window { alert.beginSheetModal(for: window, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }
}
