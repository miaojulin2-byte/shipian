import AppKit
import SwiftUI
import Combine
import CryptoKit
import CoreText

enum ReadingStyle {
    static let blue = Color(red: 0.08, green: 0.34, blue: 0.76)
    static func nativeFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "STKaiti", size: size) ?? NSFont(name: "Kai", size: size) ?? .systemFont(ofSize: size)
    }
    static func font(_ size: CGFloat) -> Font { Font(nativeFont(size)) }
    private static let titleFace: String = {
        if NSFont(name: "SourceHanSansSC-Regular", size: 13) != nil { return "SourceHanSansSC-Regular" }
        // The locally available collection contains Source Han Sans outlines.
        let compatibility = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles/Steamshare/drive_c/windows/Fonts/msyh.ttc")
        if FileManager.default.fileExists(atPath: compatibility.path) {
            CTFontManagerRegisterFontsForURL(compatibility as CFURL, .process, nil)
        }
        return "SourceHanSansSC-Regular"
    }()
    static func titleFont(_ size: CGFloat) -> Font {
        Font(NSFont(name: titleFace, size: size) ?? .systemFont(ofSize: size))
    }
}

enum SidebarLayout {
    static let width: CGFloat = 250
    static let header: CGFloat = 80
    static let toolbarHeight: CGFloat = 44
    static func shouldReveal(mouse: CGPoint, screen: CGRect, visible: CGRect) -> Bool {
        screen.contains(mouse) && mouse.x >= screen.maxX - 2 && mouse.y < visible.maxY && mouse.y > visible.minY
    }
}

struct GlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular.tint(.white.opacity(0.15)).interactive(), in: RoundedRectangle(cornerRadius: 14))
            } else {
                content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.09), radius: 5, x: 0, y: 2)
    }
}

struct Paper: View {
    let note: Note
    @ObservedObject var notes: Notes
    @State private var hovering = false
    var body: some View {
        ZStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let image = notes.thumbnail(note) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: 198, height: min(154, 198 * image.size.height / max(1, image.size.width)), alignment: .top)
                            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                    } else {
                        Text(note.text).font(ReadingStyle.font(15)).lineSpacing(4).lineLimit(7)
                            .foregroundStyle(.black)
                            .frame(width: 198, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            if note.hasAnnotation && notes.copied != note.id {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = note.title {
                        Text(title).font(ReadingStyle.titleFont(13)).foregroundStyle(ReadingStyle.blue).lineLimit(1)
                    } else if note.remark != nil {
                        Label("有备注", systemImage: "text.bubble").font(ReadingStyle.font(12))
                    }
                    if let tags = note.tags, !tags.isEmpty {
                        Text(tags.map { "#" + $0 }.joined(separator: "  "))
                            .font(ReadingStyle.titleFont(11)).foregroundStyle(ReadingStyle.blue.opacity(0.65)).lineLimit(1)
                    }
                }
                .foregroundStyle(.primary)
                .frame(width: 198, alignment: .leading)
                .allowsHitTesting(false)
            }
            if notes.copied == note.id {
                Text("✓ 已复制").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
                }
                .frame(width: 198, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .accessibilityLabel(note.imageFile == nil ? String(note.text.prefix(200)) : "图片")
                .accessibilityHint("拖到其他窗口使用，右键可编辑标注或复制")

        }
        .frame(width: 198, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .modifier(GlassSurface())
        .environment(\.colorScheme, .light)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onDrag { notes.dragProvider(note) }
        .overlay(alignment: .topLeading) {
            if hovering {
                Button { notes.remove(note) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.gray, .white)
                }.buttonStyle(.plain).offset(x: -6, y: -6).help("取下")
            }
        }
        .accessibilityElement(children: .contain)
        .onHover { hovering = $0 }
        .help(note.tooltip)
        .contextMenu {
            Button("编辑标注…") { AnnotationWindows.shared.show(note: note, notes: notes) }
            if note.hasAnnotation {
                Button("清除标注") { notes.annotate(note.id, title: "", remark: "", tags: "") }
            }
            Divider()
            Button(note.imageFile == nil ? "复制全文" : "复制图片") { notes.copy(note) }
            if note.imageFile != nil {
                Button("预览图片…") { notes.openImage(note) }
                Button("另存图片…") { notes.exportImage(note) }
            } else {
                Button("查看全文…") { showFullText(note) }
            }
            if notes.canUndo {
                Divider()
                Button("撤销上次删除") { RemovalFlight.cancelAll(); notes.undoDelete() }
            }
            Divider()
            Button("取下纸条") { notes.remove(note) }
        }
    }
    private func showFullText(_ note: Note) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 420), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "拾片 · 全文"
        let scroll = NSScrollView(frame: panel.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.isEditable = false; text.isSelectable = true; text.string = note.text
        text.font = ReadingStyle.nativeFont(17); text.textColor = .black; text.textContainerInset = NSSize(width: 20, height: 20)
        text.autoresizingMask = [.width]; text.isVerticallyResizable = true
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; panel.contentView = scroll
        panel.isReleasedWhenClosed = false
        FullTextWindows.shared.windows.append(panel)
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
@MainActor final class FullTextWindows {
    static let shared = FullTextWindows()
    var windows: [NSPanel] = []
}

struct ItemFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct Sidebar: View {
    @ObservedObject var notes: Notes
    @ObservedObject var tools: ProductivityStore
    private var canUndo: Bool { tools.section == .tasks ? tools.canUndoTask : (tools.section == .clips && notes.canUndo) }
    private func undoLatest() {
        if tools.section == .tasks { tools.undoTaskDeletion() }
        else { RemovalFlight.cancelAll(); notes.undoDelete() }
    }
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("拾片").font(ReadingStyle.titleFont(14)).foregroundStyle(ReadingStyle.blue)
                    Text(tools.section == .clips ? "拖到窗口使用" : tools.section.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if canUndo {
                        Button { undoLatest() } label: {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 13))
                        }.buttonStyle(.plain).help("撤销上次删除").accessibilityLabel("撤销上次删除")
                    }
                    Menu {
                        Button("新建待办…") { TodoWindows.shared.show(tools: tools) }
                        Button("番茄钟") { tools.openFocus() }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .medium)).frame(width: 18, height: 22)
                    }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("新建待办或开始番茄钟").accessibilityLabel("添加")
                }
                .foregroundStyle(.primary)
                .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 2)
                .padding(.horizontal, 26).frame(height: SidebarLayout.toolbarHeight)
                Picker("功能", selection: $tools.section) {
                    ForEach(SidebarSection.allCases) { section in Text(section.title).tag(section) }
                }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 14).frame(height: 36)
                switch tools.section {
                case .tasks: TodoPane(tools: tools)
                case .focus: FocusPane(tools: tools)
                case .clips:
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 1).id("start")
                            if notes.items.isEmpty {
                                Text("复制文字、图片或截图\n都会收在这里")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                                    .shadow(color: Color(nsColor: .windowBackgroundColor), radius: 2)
                                    .padding(.vertical, 20)
                            }
                            ForEach(Array(notes.items.enumerated()), id: \.element.id) { index, note in
                                Paper(note: note, notes: notes)
                                    .frame(height: notes.removed.contains(note.id) ? notes.itemFrames[note.id]?.height : nil, alignment: .top)
                                    .offset(x: notes.restoring.contains(note.id) ? SidebarLayout.width + 20 : 0)
                                    .animation(.easeOut(duration: 0.24), value: notes.restoring.contains(note.id))
                                    .background(GeometryReader { geometry in
                                        Color.clear.preference(key: ItemFramesKey.self, value: [note.id: geometry.frame(in: .named("sidebar"))])
                                    })
                                    .opacity(notes.removed.contains(note.id) ? 0 : 1)
                                    .allowsHitTesting(!notes.removed.contains(note.id) && !notes.restoring.contains(note.id))
                                    .padding(.vertical, 6)
                                    .transition(.identity)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.bottom, 12)
                        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: notes.items.map(\.id))
                    }
                    .scrollContentBackground(.hidden)
                    .onChange(of: notes.scrollGeneration) {
                        DispatchQueue.main.async { proxy.scrollTo("start", anchor: .top) }
                    }
                }
                }
            }
            .offset(x: notes.revealed ? 0 : (geo.size.width + 20))
            .animation(notes.revealed ? .spring(response: 0.35, dampingFraction: 0.9) : .easeOut(duration: 0.1), value: notes.revealed)
            .coordinateSpace(name: "sidebar")
            .onPreferenceChange(ItemFramesKey.self) { notes.itemFrames = $0 }
        }
    }
}

final class LinePanel: NSPanel {
    init(notes: Notes, tools: ProductivityStore) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: SidebarLayout.width, height: 900), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false; isMovable = false; becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        let host = NSHostingView(rootView: Sidebar(notes: notes, tools: tools))
        host.sizingOptions = []
        contentView = host
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    let notes: Notes = {
        if CommandLine.arguments.contains("--demo") {
            return Notes(board: .withUniqueName(), file: FileManager.default.temporaryDirectory.appendingPathComponent("Textline-preview-\(UUID().uuidString)/history.json"))
        }
        return Notes()
    }()
    let tools: ProductivityStore = {
        if CommandLine.arguments.contains("--demo") {
            return ProductivityStore(file: FileManager.default.temporaryDirectory.appendingPathComponent("Shipian-tools-preview-\(UUID().uuidString)/productivity.json"))
        }
        return ProductivityStore()
    }()
    var canUndoCurrent: Bool { tools.section == .tasks ? tools.canUndoTask : (tools.section == .clips && notes.canUndo) }
    var screenshots: ScreenshotInbox?
    var panel: LinePanel!
    var status: NSStatusItem!
    var timer: Timer?
    var lastMaintenance = Date.distantPast
    var menuOpen = false
    var manuallyHidden = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.textline.app").filter({ $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }).count > 0 { NSApp.terminate(nil); return }
        if !CommandLine.arguments.contains("--demo") {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.captureline.preview") { app.terminate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                guard NSRunningApplication.runningApplications(withBundleIdentifier: "local.captureline.preview").isEmpty else {
                    self.notes.storageError = "Picline 尚未退出，请退出后重新打开合并版"
                    return
                }
                self.notes.migratePicline()
                self.screenshots = ScreenshotInbox(notes: self.notes)
            }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuOpen = true }
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuOpen = false }
        }
        panel = LinePanel(notes: notes, tools: tools)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "拾片 侧边收纳")
        tools.onCompletion = { _ in NSSound(named: "Glass")?.play() }
        tools.startTicker()
        notes.onRemove = { [weak self] note in self?.animateRemoval(note) ?? false }
        notes.onNew = { [weak self] in
            guard let self, self.notes.revealed else { return }; self.show(seconds: 1)
        }
        rebuildMenu()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer!, forMode: .common)
        if CommandLine.arguments.contains("--demo") {
            notes.hang("灵感随手复制，\n就挂在这里。\n\n按住内容，拖到窗口使用。")
            notes.hang("https://example.com\n\n链接、代码、待办事项，\n都可以挂成小纸条。")
            let image = NSImage(size: NSSize(width: 400, height: 240))
            image.lockFocus()
            NSColor.systemTeal.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 400, height: 240)).fill()
            ("图片也能直接拖放" as NSString).draw(at: NSPoint(x: 54, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.white])
            image.unlockFocus()
            if let data = image.tiffRepresentation { _ = notes.hangImage(data) }
            notes.hang("今天的小计划\n\n☐ 整理思路\n☐ 写下第一版\n☑ 做一个侧边收纳栏")
            if let example = notes.items.first { notes.annotate(example.id, title: "今日待办", remark: "先完成第一版，再检查效果。", tags: "工作, 灵感") }
        }
        if CommandLine.arguments.contains("--demo") && CommandLine.arguments.contains("--scroll-test") {
            for index in 1...24 { notes.hang("滚动验证 \(index)\n这是一段紧凑排列的文字。") }
        }
        position()
        if CommandLine.arguments.contains("--demo") { show(seconds: 3600) }
        if CommandLine.arguments.contains("--demo") && CommandLine.arguments.contains("--undo-test") {
            let before = notes.items
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                notes.remove(notes.items.first(where: { $0.imageFile != nil })!)
                precondition(notes.canUndo)
                RemovalFlight.cancelAll(); notes.undoDelete()
                precondition(notes.items == before && !notes.canUndo && RemovalFlight.activeCount == 0 && !notes.restoring.isEmpty)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in notes.clear() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.88) { [self] in
                precondition(notes.canUndo)
                RemovalFlight.cancelAll(); notes.undoDelete()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [self] in
                precondition(notes.items == before && !notes.canUndo && RemovalFlight.activeCount == 0 && notes.restoring.isEmpty)
                print("PASS: undo slide-in starts and settles; undo during image animation; cancel pending clear operations")
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--demo") && CommandLine.arguments.contains("--animation-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                let text = notes.items.first(where: { $0.imageFile == nil })!
                notes.remove(text)
                precondition(RemovalFlight.activeCount == 1 && notes.removed.contains(text.id), "Text slide did not start")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                precondition(RemovalFlight.activeCount == 0, "Text slide did not finish")
                notes.settleRemovals()
                let image = notes.items.first(where: { $0.imageFile != nil })!
                notes.remove(image)
                precondition(RemovalFlight.activeCount == 1 && notes.removed.contains(image.id), "Image slide did not start")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [self] in
                precondition(RemovalFlight.activeCount == 0, "Image slide did not finish")
                notes.settleRemovals()
                precondition(notes.items.count == 2, "Removed items did not settle")
                print("PASS: text and image right-slide overlays start, finish, clean up and settle")
                NSApp.terminate(nil)
            }
        }
    }
    func animateRemoval(_ note: Note) -> Bool {
        guard notes.revealed, let frame = notes.itemFrames[note.id], let screen = panel.screen,
              frame.height > 0, frame.minY >= SidebarLayout.header, frame.minY < panel.frame.height else { return false }
        let renderer = ImageRenderer(content: Paper(note: note, notes: notes))
        renderer.scale = screen.backingScaleFactor
        renderer.proposedSize = .init(width: frame.width, height: frame.height)
        guard let image = renderer.cgImage else { return false }
        let card = CGRect(x: panel.frame.minX + frame.minX, y: panel.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
        RemovalFlight.slide(image: image, card: card, screen: screen, viewport: panel.frame)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in self?.notes.completeRemoval(note.id) }
        return true
    }
    func rebuildMenu() {
        let menu = NSMenu(); menu.delegate = self
        func add(_ title: String, _ action: Selector? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
        }
        add("拾片 · \(notes.items.count) 个图文片段")
        menu.addItem(.separator())
        add(notes.revealed ? "收起侧栏" : "展开侧栏", #selector(toggleLine))
        add(notes.paused ? "继续收集图文" : "暂停收集图文", #selector(togglePause))
        let undo = NSMenuItem(title: "撤销上次删除", action: #selector(undoDelete), keyEquivalent: "z")
        undo.target = self; undo.isEnabled = canUndoCurrent; menu.addItem(undo)
        add("新建待办…", #selector(addTodo))
        add("番茄钟", #selector(openFocus))
        add("取下全部图文", #selector(clear))
        add((screenshots?.enabled == true ? "✓ " : "") + "接管系统截图", #selector(toggleScreenshots))
        if let error = notes.storageError { add(error) }
        menu.addItem(.separator())
        add("鼠标碰屏幕右侧展开 · 拖放使用")
        add("收纳最多 100 条 · 本机保存")
        menu.addItem(.separator())
        add("退出拾片", #selector(quit))
        status.menu = menu
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(undoDelete) ? canUndoCurrent : true
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }
    func show(seconds: Double) {
        manuallyHidden = false
        position(); notes.revealed = true
    }
    func position() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main!
        let visible = screen.visibleFrame
        let height = max(300, visible.height - 16)
        let frame = NSRect(x: screen.frame.maxX - SidebarLayout.width, y: visible.minY + 8, width: SidebarLayout.width, height: height)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
    }
    func tick() {
        if Date().timeIntervalSince(lastMaintenance) >= 0.25 {
            notes.poll(); screenshots?.tick()
            let marker = tools.session?.finished == true ? "✓" : ""
            if status.button?.title != marker { status.button?.title = marker }
            if !menuOpen { rebuildMenu() }
            lastMaintenance = Date()
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
        let atRight = screen.map {
            SidebarLayout.shouldReveal(mouse: mouse, screen: $0.frame, visible: $0.visibleFrame)
        } ?? false
        if atRight {
            if !menuOpen && !manuallyHidden { show(seconds: 0.4) }
        } else { manuallyHidden = false }
        let inside = notes.revealed && panel.frame.contains(mouse)
        if !CommandLine.arguments.contains("--demo") && notes.revealed && !menuOpen && !inside && !atRight { notes.revealed = false }
        if !inside && !atRight && RemovalFlight.activeCount == 0 { notes.settleRemovals() }
        // The toolbar, section switcher and scroll viewport all receive input while open.
        panel.ignoresMouseEvents = !inside
    }
    @objc func toggleLine() {
        if notes.revealed { notes.revealed = false; manuallyHidden = true } else { show(seconds: 3) }
    }
    func applicationWillTerminate(_ notification: Notification) { tools.stopTicker(); screenshots?.restoreSettings() }
    @objc func toggleScreenshots() { screenshots?.toggle() }
    @objc func togglePause() { notes.paused.toggle() }
    @objc func clear() { tools.section = .clips; notes.clear() }
    @objc func addTodo() { TodoWindows.shared.show(tools: tools) }
    @objc func openFocus() { tools.openFocus(); show(seconds: 1) }
    @objc func undoDelete() {
        if tools.section == .tasks { tools.undoTaskDeletion() }
        else if tools.section == .clips { RemovalFlight.cancelAll(); notes.undoDelete() }
        show(seconds: 1)
    }
    @objc func quit() { NSApp.terminate(nil) }
}

@MainActor func selfTest() {
    let screenRect = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let visibleRect = CGRect(x: -1920, y: 30, width: 1920, height: 1026)
    assert(SidebarLayout.shouldReveal(mouse: CGPoint(x: -1, y: 500), screen: screenRect, visible: visibleRect))
    assert(!SidebarLayout.shouldReveal(mouse: CGPoint(x: -1000, y: 1070), screen: screenRect, visible: visibleRect))
    assert(!SidebarLayout.shouldReveal(mouse: CGPoint(x: -1, y: 1070), screen: screenRect, visible: visibleRect))
    assert(!SidebarLayout.shouldReveal(mouse: CGPoint(x: -10, y: 500), screen: screenRect, visible: visibleRect))
    assert(!SidebarLayout.shouldReveal(mouse: CGPoint(x: -1920, y: 500), screen: screenRect, visible: visibleRect))
    let board = NSPasteboard.withUniqueName()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let file = folder.appendingPathComponent("history.json")
    defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: folder) }
    productivitySelfTest(folder: folder)
    let notes = Notes(board: board, file: file)
    func put(_ text: String) { board.clearContents(); board.setString(text, forType: .string); notes.poll() }
    put("中文第一行\nSecond line 👋")
    assert(notes.items.count == 1 && notes.items[0].text == "中文第一行\nSecond line 👋")
    notes.copy(notes.items[0]); notes.poll(); assert(notes.items.count == 1)
    put("另一个片段"); put("中文第一行\nSecond line 👋"); assert(notes.items.count == 2)
    put("  \n"); assert(notes.items.count == 2)
    let secret = NSPasteboardItem(); secret.setString("secret", forType: .string); secret.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
    board.clearContents(); board.writeObjects([secret]); notes.poll(); assert(notes.items.count == 2)
    notes.paused = true; put("暂停时的文字"); assert(notes.items.count == 2); notes.paused = false
    let annotatedID = notes.items[0].id
    assert(notes.annotate(annotatedID, title: "  测试标题  ", remark: "备注\n第二行", tags: "#工作，灵感,工作;  "))
    assert(notes.items[0].title == "测试标题" && notes.items[0].tags == ["工作", "灵感"])
    notes.copy(notes.items[0]); assert(board.string(forType: .string) == notes.items[0].text)
    put("中文第一行\nSecond line 👋")
    assert(notes.items[0].id == annotatedID && notes.items[0].remark == "备注\n第二行")
    let textDrag = notes.dragProvider(notes.items[0])
    var draggedText: String?
    textDrag.loadObject(ofClass: NSString.self) { value, _ in
        DispatchQueue.main.async { draggedText = value as? String }
    }
    let textDeadline = Date().addingTimeInterval(3)
    while draggedText == nil && Date() < textDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    assert(draggedText == notes.items[0].text)
    let restored = Notes(board: board, file: file); assert(restored.items == notes.items)
    assert(restored.items[0].title == "测试标题")
    let recopy = Notes(board: board, file: folder.appendingPathComponent("undo-recopy/history.json"))
    recopy.hang("保留我的标注")
    let originalID = recopy.items[0].id
    recopy.annotate(originalID, title: "原始标题", remark: "", tags: "")
    recopy.remove(recopy.items[0]); recopy.hang("保留我的标注"); recopy.undoDelete()
    assert(recopy.items.count == 1 && recopy.items[0].id == originalID && recopy.items[0].title == "原始标题")
    let removalFile = folder.appendingPathComponent("removal/history.json")
    let removal = Notes(board: board, file: removalFile)
    removal.hang("drop me"); removal.hang("keep me")
    let dropping = removal.items.last!
    removal.onRemove = { _ in true }
    removal.remove(dropping)
    assert(removal.removed.contains(dropping.id) && removal.items.count == 2)
    assert(Notes(board: board, file: removalFile).items.map(\.text) == ["keep me"])
    removal.settleRemovals(); assert(removal.items.count == 1 && removal.removed.isEmpty)
    let image = NSImage(size: NSSize(width: 32, height: 24))
    image.lockFocus(); NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: 32, height: 24).fill(); image.unlockFocus()
    let imageData = image.tiffRepresentation!
    board.clearContents(); board.setData(imageData, forType: .tiff); notes.poll()
    assert(notes.items.count == 3 && notes.items[0].imageFile != nil)
    assert(notes.annotate(notes.items[0].id, title: "图片标注", remark: "原图保持不变", tags: "参考"))
    let picture = notes.items[0]; notes.copy(picture); notes.poll()
    assert(notes.items.count == 3 && board.data(forType: .png) != nil)
    assert(notes.items[0].title == "图片标注")
    let imageDrag = notes.dragProvider(picture)
    assert(imageDrag.hasRepresentationConforming(toTypeIdentifier: "public.png", fileOptions: []))
    var draggedPNG: Data?
    imageDrag.loadDataRepresentation(forTypeIdentifier: "public.png") { data, _ in
        DispatchQueue.main.async { draggedPNG = data }
    }
    let imageDeadline = Date().addingTimeInterval(3)
    while draggedPNG == nil && Date() < imageDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    assert(draggedPNG == board.data(forType: .png))
    assert(notes.annotate(picture.id, title: "", remark: "", tags: ""))
    assert(!notes.items[0].hasAnnotation)
    assert(notes.thumbnail(picture) != nil)
    assert(Notes(board: board, file: file).items == notes.items)
    assert(notes.hangImage(Data("invalid".utf8)) == false)
    let imageURL = notes.imageURL(picture)!
    notes.remove(picture); assert(FileManager.default.fileExists(atPath: imageURL.path))
    assert(notes.canUndo)
    let deletedRestored = Notes(board: board, file: file)
    assert(deletedRestored.canUndo)
    deletedRestored.undoDelete()
    assert(deletedRestored.items.contains(where: { $0.id == picture.id }) && deletedRestored.thumbnail(picture) != nil)
    assert(!deletedRestored.canUndo)
    notes.undoDelete(); assert(notes.items.contains(where: { $0.id == picture.id }))
    notes.remove(picture)
    notes.remove(notes.items[0]); assert(!FileManager.default.fileExists(atPath: imageURL.path))
    notes.undoDelete()
    let oldFile = folder.appendingPathComponent("old/history.json")
    try! FileManager.default.createDirectory(at: oldFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data("[{\"id\":\"00000000-0000-0000-0000-000000000001\",\"text\":\"旧纸条\",\"tilt\":1}]".utf8).write(to: oldFile)
    assert(Notes(board: board, file: oldFile).items.first?.text == "旧纸条")
    let inbox = folder.appendingPathComponent("watch")
    try! FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let watcher = ImageFolderWatcher(folders: [inbox])
    let shot = inbox.appendingPathComponent("test.png")
    try! imageData.write(to: shot)
    assert(watcher.newImages().isEmpty)
    let detected = watcher.newImages(); assert(detected.map { $0.standardizedFileURL.path } == [shot.standardizedFileURL.path])
    assert(watcher.newImages().isEmpty)
    let testDomain = "local.textline.test.\(UUID().uuidString)"
    let testSettings = UserDefaults(suiteName: testDomain + ".state")!
    let prefs = UserDefaults(suiteName: testDomain)!
    defer {
        prefs.removePersistentDomain(forName: testDomain)
        testSettings.removePersistentDomain(forName: testDomain + ".state")
    }
    prefs.set("/tmp/previous-capture-folder", forKey: "location")
    prefs.set(true, forKey: "show-thumbnail"); prefs.synchronize()
    let capture = ScreenshotInbox(notes: notes, domain: testDomain, settings: testSettings, folder: inbox)
    assert(capture.enabled)
    let newShot = inbox.appendingPathComponent("new-shot.png")
    try! imageData.write(to: newShot)
    capture.tick()
    Thread.sleep(forTimeInterval: 0.7)
    capture.tick()
    assert(notes.items.first?.imageFile != nil)
    assert(!FileManager.default.fileExists(atPath: newShot.path))
    prefs.synchronize()
    assert(prefs.string(forKey: "location") == inbox.path)
    capture.restoreSettings(); prefs.synchronize()
    assert(prefs.string(forKey: "location") == "/tmp/previous-capture-folder")
    assert(prefs.bool(forKey: "show-thumbnail"))
    assert(prefs.object(forKey: "location-screenshot") == nil)
    for i in 0..<105 { notes.hang("片段 \(i)") }; assert(notes.items.count == 100)
    let beforeClear = notes.items
    notes.clear(); assert(notes.items.isEmpty && notes.canUndo)
    notes.undoDelete(); assert(notes.items == beforeClear && !notes.canUndo)
    notes.undoDelete(); assert(notes.items == beforeClear)
    notes.clear(); assert(Notes(board: board, file: file).items.isEmpty)
    let clearRestored = Notes(board: board, file: file)
    clearRestored.undoDelete(); assert(clearRestored.items == beforeClear)
    print("PASS: one-step undo, clear-batch undo, image undo after restart, expired image cleanup, right-edge trigger and menu exclusion, native text/image drag payloads, annotation persistence/clearing, dedup preserves annotations, copy excludes annotations, image capture/copy/restore/removal, old-history migration, folder watcher, screenshot preference restoration, Unicode, copy-loop suppression, deduplication, empty/private filtering, pause, persistence, retention, continuous history, clear")
}
if CommandLine.arguments.contains("--quit-running") {
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "local.textline.app").filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    for running in runningApps { running.terminate() }
    let deadline = Date().addingTimeInterval(10)
    while runningApps.contains(where: { !$0.isTerminated }) && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    if runningApps.contains(where: { !$0.isTerminated }) {
        fputs("Textline has not finished quitting. Restart was cancelled.\n", stderr)
        exit(1)
    }
} else if CommandLine.arguments.contains("--self-test") {
    MainActor.assumeIsolated { selfTest() }
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
