import AppKit
import SwiftUI

@MainActor final class AnnotationWindows: NSObject, NSWindowDelegate {
    static let shared = AnnotationWindows()
    private var windows: [UUID: NSPanel] = [:]
    func show(note: Note, notes: Notes) {
        if let panel = windows[note.id] { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        guard let current = notes.items.first(where: { $0.id == note.id }), !notes.removed.contains(note.id) else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 370), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "拾片 · 编辑标注"
        panel.level = .init(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.isReleasedWhenClosed = false; panel.delegate = self
        let host = NSHostingView(rootView: AnnotationEditor(note: current, notes: notes, close: { [weak panel] in panel?.close() }))
        host.sizingOptions = []
        panel.contentView = host; windows[note.id] = panel
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== window }
    }
}

struct AnnotationEditor: View {
    let note: Note
    @ObservedObject var notes: Notes
    let close: () -> Void
    @State private var title: String
    @State private var remark: String
    @State private var tags: String
    @State private var error: String?
    @FocusState private var titleFocused: Bool
    init(note: Note, notes: Notes, close: @escaping () -> Void) {
        self.note = note; self.notes = notes; self.close = close
        _title = State(initialValue: note.title ?? "")
        _remark = State(initialValue: note.remark ?? "")
        _tags = State(initialValue: (note.tags ?? []).joined(separator: ", "))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("标题（可选）", text: $title).textFieldStyle(.roundedBorder)
                .accessibilityLabel("标题").focused($titleFocused)
            Text("备注").font(.system(size: 12, weight: .medium))
            TextEditor(text: $remark).font(.system(size: 13)).frame(minHeight: 120)
                .padding(4).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.secondary.opacity(0.3)))
                .accessibilityLabel("备注")
            TextField("标签，用逗号分隔（可选）", text: $tags).textFieldStyle(.roundedBorder)
                .accessibilityLabel("标签")
            Text("标注单独保存，复制时仍使用原文或原图。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button("保存") {
                    if notes.annotate(note.id, title: title, remark: remark, tags: tags) { close() }
                    else { error = notes.storageError ?? "保存失败，请重试" }
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 460, height: 370)
        .onAppear { titleFocused = true }
    }
}
