import AppKit
import SwiftUI

@main
enum PandaGalleryMain {
    @MainActor private static var retainedDelegate: AppDelegate?
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        // NSApplication.delegate is weak; application-lifetime storage owns it.
        retainedDelegate = delegate
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSUserInterfaceValidations {
    let model = GalleryModel.shared
    var mainWindow: NSWindow?
    private var keyboardMonitor: Any?
    private var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["PANDA_DIAGNOSTICS"] == "1" { fputs("PandaGallery: didFinishLaunching\n", stderr) }
        model.applyAppearance()
        if let icon = NSImage(contentsOf: GalleryModel.resourceURL.appendingPathComponent("PandaGallery.png")) { NSApp.applicationIconImage = icon }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1390, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "熊猫图库"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 900, height: 620)
        window.backgroundColor = NSColor(Palette.background)
        window.appearance = model.theme.appearance
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PandaGalleryMainWindow")
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        let host = NSHostingView(rootView: ContentView(model: model))
        window.contentView = host
        if !window.setFrameUsingName("PandaGalleryMainWindow") { window.center() }
        mainWindow = window; model.window = window
        createMenus()
        installKeyboardMonitor()
        window.makeKeyAndOrderFront(nil)
        if ProcessInfo.processInfo.environment["PANDA_DIAGNOSTICS"] == "1" { fputs("PandaGallery: windowVisible=\(window.isVisible) frame=\(window.frame)\n", stderr) }
        NSApp.activate(ignoringOtherApps: true)
        if let pendingURL { model.open(pendingURL) } else { model.start() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if mainWindow == nil { pendingURL = url }
        else { model.open(url); mainWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { application(sender, open: [URL(fileURLWithPath: first)]) }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.makeKeyAndOrderFront(nil); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.hasUnsavedEdits { model.confirmLeavingEdits { sender.performClose(nil) }; return false }
        model.stopSlideshow(); return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.hasUnsavedEdits else { return .terminateNow }
        model.confirmLeavingEdits(onCancel: { sender.reply(toApplicationShouldTerminate: false) }) { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    private func createMenus() {
        let main = NSMenu()
        let appMenu = NSMenu(title: "熊猫图库")
        append("关于熊猫图库", action: #selector(about), to: appMenu)
        appMenu.addItem(.separator())
        append("偏好设置…", action: #selector(settings), key: ",", to: appMenu)
        appMenu.addItem(.separator())
        let services = NSMenu(title: "服务"); let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: ""); servicesItem.submenu = services; appMenu.addItem(servicesItem); NSApp.servicesMenu = services
        appMenu.addItem(.separator())
        append("隐藏熊猫图库", action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp, to: appMenu)
        append("隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], target: NSApp, to: appMenu)
        append("全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp, to: appMenu)
        appMenu.addItem(.separator())
        append("退出熊猫图库", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp, to: appMenu)
        addMenu(appMenu, to: main)

        let file = NSMenu(title: "文件")
        append("打开图片…", action: #selector(openImage), key: "o", to: file)
        let recentItem = NSMenuItem(title: "打开最近使用", action: nil, keyEquivalent: "")
        let recent = NSMenu(title: "打开最近使用"); recent.delegate = self; recentItem.submenu = recent; file.addItem(recentItem)
        file.addItem(.separator())
        append("导出图片副本…", action: #selector(exportImage), key: "s", to: file)
        append("在 Finder 中显示", action: #selector(reveal), key: "r", modifiers: [.command, .shift], to: file)
        append("移至废纸篓…", action: #selector(trash), key: "\u{8}", to: file)
        file.addItem(.separator())
        append("关闭窗口", action: #selector(NSWindow.performClose(_:)), key: "w", target: nil, to: file)
        addMenu(file, to: main)

        let edit = NSMenu(title: "编辑")
        append("撤销图片编辑", action: #selector(undo), key: "z", to: edit)
        append("重做图片编辑", action: #selector(redo), key: "z", modifiers: [.command, .shift], to: edit)
        edit.addItem(.separator())
        append("剪切", action: #selector(NSText.cut(_:)), key: "x", target: nil, to: edit)
        append("复制", action: #selector(NSText.copy(_:)), key: "c", target: nil, to: edit)
        append("粘贴", action: #selector(NSText.paste(_:)), key: "v", target: nil, to: edit)
        append("全选", action: #selector(NSText.selectAll(_:)), key: "a", target: nil, to: edit)
        edit.addItem(.separator())
        append("搜索图片", action: #selector(search), key: "f", to: edit)
        addMenu(edit, to: main)

        let view = NSMenu(title: "显示")
        append("图库视图", action: #selector(showGrid), key: "2", to: view)
        append("阅读视图", action: #selector(showReader), key: "3", to: view)
        append("图片详情", action: #selector(toggleInspector), key: "i", to: view)
        view.addItem(.separator())
        append("适应窗口", action: #selector(fit), key: "0", to: view)
        append("实际大小", action: #selector(actual), key: "1", to: view)
        view.addItem(.separator())
        append("进入 / 退出全屏", action: #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control], target: nil, to: view)
        addMenu(view, to: main)

        let photo = NSMenu(title: "图片")
        append("上一张", action: #selector(previous), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), modifiers: [], to: photo)
        append("下一张", action: #selector(next), key: String(UnicodeScalar(NSRightArrowFunctionKey)!), modifiers: [], to: photo)
        append("播放 / 暂停幻灯片", action: #selector(slideshow), key: " ", modifiers: [], to: photo)
        photo.addItem(.separator())
        append("收藏 / 取消收藏", action: #selector(favorite), to: photo)
        append("向右旋转", action: #selector(rotate), to: photo)
        append("裁剪图片", action: #selector(crop), to: photo)
        addMenu(photo, to: main)

        let help = NSMenu(title: "帮助")
        append("使用帮助与快捷键", action: #selector(helpAction), key: "/", modifiers: [.command, .shift], to: help)
        append("打开示例图库", action: #selector(samples), to: help)
        addMenu(help, to: main); NSApp.helpMenu = help
        let window = NSMenu(title: "窗口")
        append("最小化", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", target: nil, to: window)
        append("缩放", action: #selector(NSWindow.performZoom(_:)), target: nil, to: window)
        addMenu(window, to: main); NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    private func append(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        // Standard responder-chain actions deliberately keep a nil target.
        let standard = [#selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSText.selectAll(_:)), #selector(NSWindow.performClose(_:)), #selector(NSWindow.toggleFullScreen(_:)), #selector(NSWindow.performMiniaturize(_:)), #selector(NSWindow.performZoom(_:))]
        item.target = target ?? (standard.contains(action) ? nil : self)
        item.keyEquivalentModifierMask = modifiers; menu.addItem(item)
    }
    private func addMenu(_ menu: NSMenu, to main: NSMenu) { let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: ""); item.submenu = menu; main.addItem(item) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "打开最近使用" else { return }
        menu.removeAllItems()
        for path in model.recentPaths.prefix(12) where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: ""); item.target = self; item.representedObject = url; item.toolTip = path; menu.addItem(item)
        }
        if menu.items.isEmpty { let item = NSMenuItem(title: "暂无最近打开的图片", action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        menu.addItem(.separator()); append("清除最近打开记录", action: #selector(clearRecent), to: menu)
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo) { return (mainWindow?.firstResponder as? NSTextView)?.undoManager?.canUndo ?? model.canUndo }
        if item.action == #selector(redo) { return (mainWindow?.firstResponder as? NSTextView)?.undoManager?.canRedo ?? model.canRedo }
        if [#selector(exportImage), #selector(rotate), #selector(crop), #selector(actual), #selector(fit)].contains(item.action) { return model.edit != nil && !model.isLoading }
        if item.action == #selector(previous) { return (model.selectedIndex ?? 0) > 0 }
        if item.action == #selector(next) { return (model.selectedIndex ?? -1) < model.visiblePhotos.count - 1 }
        if item.action == #selector(trash) { return model.selected != nil && !model.isDemo }
        return true
    }

    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard NSApp.keyWindow === self.mainWindow, self.mainWindow?.attachedSheet == nil,
                  !(self.mainWindow?.firstResponder is NSTextView), event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 123: self.model.navigate(-1)
            case 124: self.model.navigate(1)
            case 49: self.model.toggleSlideshow()
            case 53:
                self.model.stopSlideshow()
                if self.mainWindow?.styleMask.contains(.fullScreen) == true { self.mainWindow?.toggleFullScreen(nil) }
                else { self.model.mode = .grid; self.model.tool = .info; self.model.showInspector = false }
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "f": self.model.toggleFavorite()
                case "r": self.model.beginEditing(.adjust); self.model.transform(.right)
                case "c": self.model.beginEditing(.crop)
                case "+", "=": self.model.zoom(1.25)
                case "-": self.model.zoom(1 / 1.25)
                default: return event
                }
            }
            return nil
        }
    }

    @objc func openImage() { model.openPanel() }
    @objc func openRecent(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { model.open(url) } }
    @objc func clearRecent() { model.recentPaths = []; UserDefaults.standard.removeObject(forKey: "recentPaths"); UserDefaults.standard.removeObject(forKey: "lastImage"); NSDocumentController.shared.clearRecentDocuments(nil) }
    @objc func exportImage() { model.requestExport() }
    @objc func reveal() { model.revealInFinder() }
    @objc func trash() { model.trashSelected() }
    @objc func undo() { if let text = mainWindow?.firstResponder as? NSTextView { text.undoManager?.undo() } else { model.undo() } }
    @objc func redo() { if let text = mainWindow?.firstResponder as? NSTextView { text.undoManager?.redo() } else { model.redo() } }
    @objc func search() { NotificationCenter.default.post(name: .focusGallerySearch, object: nil) }
    @objc func showGrid() { model.mode = .grid; model.showInspector = false; model.tool = .info; model.stopSlideshow() }
    @objc func showReader() { if model.selected != nil { model.mode = .viewer } }
    @objc func toggleInspector() { model.tool = .info; model.showInspector.toggle() }
    @objc func fit() { model.fitImage() }
    @objc func actual() { model.zoomScale = 1; model.panOffset = .zero }
    @objc func previous() { model.navigate(-1) }
    @objc func next() { model.navigate(1) }
    @objc func slideshow() { model.toggleSlideshow() }
    @objc func favorite() { model.toggleFavorite() }
    @objc func rotate() { model.beginEditing(.adjust); model.transform(.right) }
    @objc func crop() { model.beginEditing(.crop) }
    @objc func settings() { model.stopSlideshow(); model.showSettings = true }
    @objc func helpAction() { model.showHelp = true }
    @objc func samples() { model.loadSamples() }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "熊猫图库", .applicationVersion: "1.1.1", .version: "3", .credits: NSAttributedString(string: "SwiftUI · AppKit · Core Image\n\n示例摄影：Unsplash\n完整来源见 Resources/PhotoCredits.md")])
    }
}
