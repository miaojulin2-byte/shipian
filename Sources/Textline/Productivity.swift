import AppKit
import Combine

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var completed = false
    var createdAt = Date()
}
enum SidebarSection: String, CaseIterable, Identifiable {
    case clips, tasks, focus
    var id: String { rawValue }
    var title: String { switch self { case .clips: return "收纳"; case .tasks: return "待办"; case .focus: return "专注" } }
}
enum FocusPhase: String, Codable { case focus, rest }
struct FocusSession: Codable, Equatable {
    var phase: FocusPhase
    var totalSeconds: Int
    var secondsLeft: Int
    var endsAt: Date?
    var finished = false
}
private struct DeletedTodo: Codable { let item: TodoItem; let index: Int }
private struct ProductivitySnapshot: Codable {
    var tasks: [TodoItem] = []
    var deleted: DeletedTodo?
    var session: FocusSession?
    var focusMinutes = 25
    var restMinutes = 5
    var completedFocus = 0
}

@MainActor final class ProductivityStore: ObservableObject {
    @Published var section: SidebarSection = .clips
    @Published private(set) var tasks: [TodoItem] = []
    @Published private(set) var session: FocusSession?
    @Published private(set) var focusMinutes = 25
    @Published private(set) var restMinutes = 5
    @Published private(set) var completedFocus = 0
    @Published private(set) var canUndoTask = false
    @Published private(set) var error: String?
    @Published private var now = Date()
    var onCompletion: ((FocusPhase) -> Void)?
    private var deleted: DeletedTodo?
    private let file: URL
    private let clock: () -> Date
    private var timer: Timer?

    init(file: URL? = nil, clock: @escaping () -> Date = Date.init) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Textline/productivity.json")
        self.clock = clock
        if let data = try? Data(contentsOf: self.file), let saved = try? JSONDecoder().decode(ProductivitySnapshot.self, from: data) { apply(saved) }
        now = clock(); tick(notify: false)
    }
    private var snapshot: ProductivitySnapshot {
        .init(tasks: tasks, deleted: deleted, session: session, focusMinutes: focusMinutes, restMinutes: restMinutes, completedFocus: completedFocus)
    }
    private func apply(_ value: ProductivitySnapshot) {
        tasks = value.tasks; deleted = value.deleted; session = value.session
        focusMinutes = min(90, max(1, value.focusMinutes)); restMinutes = min(30, max(1, value.restMinutes))
        completedFocus = value.completedFocus; canUndoTask = deleted != nil
    }
    @discardableResult private func change(_ action: () -> Void) -> Bool {
        let before = snapshot
        action(); canUndoTask = deleted != nil
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(snapshot).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            error = nil; return true
        } catch { apply(before); self.error = "暂未保存：\(error.localizedDescription)"; return false }
    }
    var orderedTasks: [TodoItem] { tasks.filter { !$0.completed } + tasks.filter { $0.completed } }
    var pendingCount: Int { tasks.filter { !$0.completed }.count }
    @discardableResult func saveTask(id: UUID? = nil, title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { error = "请填写待办内容"; return false }
        if let id, !tasks.contains(where: { $0.id == id }) { error = "这条待办已被删除"; return false }
        return change {
            if let id, let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].title = clean }
            else if id == nil { tasks.insert(TodoItem(title: clean), at: 0) }
        }
    }
    func toggleTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change { tasks[index].completed.toggle() }
    }
    func removeTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        change { deleted = DeletedTodo(item: tasks.remove(at: index), index: index) }
    }
    func undoTaskDeletion() {
        guard let entry = deleted else { return }
        change { tasks.insert(entry.item, at: min(entry.index, tasks.count)); deleted = nil }
    }
    func setDurations(focus: Int? = nil, rest: Int? = nil) {
        change {
            if let focus { focusMinutes = min(90, max(1, focus)) }
            if let rest { restMinutes = min(30, max(1, rest)) }
        }
    }
    var remainingSeconds: Int {
        guard let session else { return focusMinutes * 60 }
        if let end = session.endsAt { return max(0, Int(ceil(end.timeIntervalSince(clock())))) }
        return session.secondsLeft
    }
    var clockLabel: String { String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60) }
    var progress: Double { guard let session else { return 0 }; return min(1, max(0, 1 - Double(remainingSeconds) / Double(max(1, session.totalSeconds)))) }
    var phaseLabel: String {
        guard let session else { return "准备专注" }
        if session.finished { return session.phase == .focus ? "专注完成" : "休息结束" }
        if session.endsAt == nil { return "已暂停" }
        return session.phase == .focus ? "专注中" : "休息时间"
    }
    func startFocus() { start(.focus, minutes: focusMinutes) }
    func startRest() { start(.rest, minutes: restMinutes) }
    func openFocus() {
        section = .focus
        if session == nil || session?.finished == true { startFocus() }
    }
    private func start(_ phase: FocusPhase, minutes: Int) {
        let seconds = minutes * 60
        change { session = FocusSession(phase: phase, totalSeconds: seconds, secondsLeft: seconds, endsAt: clock().addingTimeInterval(Double(seconds))) }
        now = clock()
    }
    func pauseOrResume() {
        tick()
        guard var value = session, !value.finished else { return }
        if value.endsAt != nil { value.secondsLeft = remainingSeconds; value.endsAt = nil }
        else { value.endsAt = clock().addingTimeInterval(Double(value.secondsLeft)) }
        change { session = value }; now = clock()
    }
    func resetTimer() { change { session = nil } }
    func tick(notify: Bool = true) {
        guard var value = session, let end = value.endsAt, !value.finished else { return }
        let current = clock()
        if Int(current.timeIntervalSince1970) != Int(now.timeIntervalSince1970) { now = current }
        guard end <= current else { return }
        value.endsAt = nil; value.secondsLeft = 0; value.finished = true
        if change({ session = value; if value.phase == .focus { completedFocus += 1 } }), notify { onCompletion?(value.phase) }
    }
    func startTicker() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func stopTicker() { timer?.invalidate(); timer = nil }
}

@MainActor func productivitySelfTest(folder: URL) {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    let file = folder.appendingPathComponent("tools/productivity.json")
    let store = ProductivityStore(file: file, clock: { date })
    assert(!store.saveTask(title: "  "))
    assert(store.saveTask(title: "  写一段中文待办  "))
    let id = store.tasks[0].id
    assert(store.tasks[0].title == "写一段中文待办")
    store.toggleTask(id); assert(store.tasks[0].completed && store.pendingCount == 0)
    assert(store.saveTask(id: id, title: "已修改"))
    store.removeTask(id); assert(store.tasks.isEmpty && store.canUndoTask)
    store.undoTaskDeletion(); assert(store.tasks.count == 1 && store.tasks[0].completed && !store.canUndoTask)
    let restored = ProductivityStore(file: file, clock: { date }); assert(restored.tasks == store.tasks)
    store.setDurations(focus: 1, rest: 1); store.startFocus()
    assert(store.remainingSeconds == 60)
    date.addTimeInterval(20); store.tick(); assert(store.remainingSeconds == 40)
    store.pauseOrResume(); date.addTimeInterval(30); store.tick(); assert(store.remainingSeconds == 40 && store.session?.endsAt == nil)
    let paused = ProductivityStore(file: file, clock: { date }); assert(paused.remainingSeconds == 40 && paused.session?.endsAt == nil)
    store.pauseOrResume(); date.addTimeInterval(41); store.tick()
    assert(store.session?.finished == true && store.completedFocus == 1)
    store.tick(); assert(store.completedFocus == 1)
    let finished = ProductivityStore(file: file, clock: { date }); assert(finished.completedFocus == 1 && finished.session?.finished == true)
    store.startRest(); date.addTimeInterval(61); store.tick(); assert(store.session?.finished == true && store.completedFocus == 1)
    store.resetTimer(); assert(store.session == nil && store.clockLabel == "01:00")
    store.startFocus(); date.addTimeInterval(61)
    let offline = ProductivityStore(file: file, clock: { date }); assert(offline.session?.finished == true && offline.completedFocus == 2)
    print("PASS: todo create/edit/complete/delete/undo/persistence; focus pause/resume/expiry/rest/offline recovery")
}
