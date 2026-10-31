import AppKit
import SwiftUI

struct TodoPane: View {
    @ObservedObject var tools: ProductivityStore
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
                Text("待办 \(tools.pendingCount) · 已完成 \(tools.tasks.count - tools.pendingCount)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                if tools.tasks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checklist").font(.system(size: 24)).foregroundStyle(ReadingStyle.blue)
                        Text("把想做的事写下来").font(ReadingStyle.font(15)).foregroundStyle(.black)
                        Button("新建待办") { TodoWindows.shared.show(tools: tools) }.controlSize(.small)
                    }.frame(width: 198).padding(12).modifier(GlassSurface())
                }
                ForEach(tools.orderedTasks) { task in TodoCard(task: task, tools: tools).transition(.move(edge: .trailing)) }
                if let error = tools.error { Text(error).font(.system(size: 11)).foregroundStyle(.red).padding(.horizontal, 16) }
            }.frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 14)
                .animation(.easeOut(duration: 0.22), value: tools.orderedTasks)
        }.scrollContentBackground(.hidden)
    }
}
struct TodoCard: View {
    let task: TodoItem
    @ObservedObject var tools: ProductivityStore
    @State private var hovered = false
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button { tools.toggleTask(task.id) } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18)).foregroundStyle(ReadingStyle.blue)
            }.buttonStyle(.plain).accessibilityLabel(task.completed ? "恢复未完成" : "标记完成")
            Text(task.title).font(ReadingStyle.titleFont(14))
                .foregroundStyle(task.completed ? Color.secondary : ReadingStyle.blue)
                .strikethrough(task.completed).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 198, alignment: .leading).padding(12).modifier(GlassSurface())
        .environment(\.colorScheme, .light)
        .overlay(alignment: .topLeading) {
            if hovered {
                Button { tools.removeTask(task.id) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.gray, .white) }
                    .buttonStyle(.plain).offset(x: -6, y: -6).help("删除待办")
            }
        }
        .onHover { hovered = $0 }
        .contextMenu {
            Button("编辑待办…") { TodoWindows.shared.show(tools: tools, task: task) }
            Button(task.completed ? "恢复未完成" : "标记完成") { tools.toggleTask(task.id) }
            Divider()
            Button("删除待办") { tools.removeTask(task.id) }
            if tools.canUndoTask { Button("撤销上次删除") { tools.undoTaskDeletion() } }
        }
    }
}
private struct FocusPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(ReadingStyle.blue.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct FocusPane: View {
    @ObservedObject var tools: ProductivityStore
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
                VStack(spacing: 15) {
                    Text(tools.phaseLabel).font(ReadingStyle.titleFont(14)).foregroundStyle(ReadingStyle.blue)
                    ZStack {
                        Circle().stroke(ReadingStyle.blue.opacity(0.12), lineWidth: 4)
                        Circle().trim(from: 0, to: tools.progress)
                            .stroke(ReadingStyle.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(tools.clockLabel).font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(ReadingStyle.blue)
                    }.frame(width: 156, height: 156).padding(.vertical, 2)
                    HStack(spacing: 10) {
                        Button(primaryTitle) { primaryAction() }.buttonStyle(FocusPrimaryButtonStyle())
                        if tools.session != nil { Button("重置") { tools.resetTimer() }.buttonStyle(.bordered) }
                    }.controlSize(.small)
                    Text("已完成 \(tools.completedFocus) 轮专注").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(width: 198).padding(12).modifier(GlassSurface())
                DisclosureGroup("计时设置") {
                    VStack(spacing: 12) {
                        Stepper("专注 \(tools.focusMinutes) 分钟", value: Binding(get: { tools.focusMinutes }, set: { tools.setDurations(focus: $0) }), in: 1...90)
                        Stepper("休息 \(tools.restMinutes) 分钟", value: Binding(get: { tools.restMinutes }, set: { tools.setDurations(rest: $0) }), in: 1...30)
                    }.font(.system(size: 12)).padding(.top, 10).disabled(tools.session != nil && tools.session?.finished != true)
                }.font(ReadingStyle.titleFont(12)).frame(width: 198).padding(12).modifier(GlassSurface())
                if let error = tools.error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            }.frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 14)
                .environment(\.colorScheme, .light)
        }.scrollContentBackground(.hidden)
    }
    private var primaryTitle: String {
        guard let session = tools.session else { return "开始专注" }
        if session.finished { return session.phase == .focus ? "开始休息" : "再专注一轮" }
        return session.endsAt == nil ? "继续" : "暂停"
    }
    private func primaryAction() {
        guard let session = tools.session else { tools.startFocus(); return }
        if session.finished { if session.phase == .focus { tools.startRest() } else { tools.startFocus() } }
        else { tools.pauseOrResume() }
    }
}

@MainActor final class TodoWindows: NSObject, NSWindowDelegate {
    static let shared = TodoWindows()
    private var windows: [String: NSPanel] = [:]
    func show(tools: ProductivityStore, task: TodoItem? = nil) {
        let key = task?.id.uuidString ?? "new"
        if let panel = windows[key] { panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 172), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = task == nil ? "拾片 · 新建待办" : "拾片 · 编辑待办"
        panel.level = .init(rawValue: NSWindow.Level.floating.rawValue + 2); panel.isReleasedWhenClosed = false; panel.delegate = self
        let host = NSHostingView(rootView: TodoEditor(tools: tools, task: task, close: { [weak panel] in panel?.close() }))
        host.sizingOptions = []; panel.contentView = host
        windows[key] = panel; tools.section = .tasks
        panel.center(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow { windows = windows.filter { $0.value !== window } }
    }
}
private struct TodoEditor: View {
    @ObservedObject var tools: ProductivityStore
    let task: TodoItem?
    let close: () -> Void
    @State private var title: String
    @FocusState private var focused: Bool
    init(tools: ProductivityStore, task: TodoItem?, close: @escaping () -> Void) {
        self.tools = tools; self.task = task; self.close = close; _title = State(initialValue: task?.title ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("想做什么？", text: $title).textFieldStyle(.roundedBorder).font(ReadingStyle.titleFont(14))
                .foregroundStyle(ReadingStyle.blue).focused($focused).accessibilityLabel("待办内容")
            if let error = tools.error { Text(error).font(.system(size: 11)).foregroundStyle(.red) }
            HStack {
                Spacer(); Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button("保存") { if tools.saveTask(id: task?.id, title: title) { close() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 420, height: 172).onAppear { focused = true }
    }
}
