import AppKit
import Combine
import CoreServices
import FinderSync
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginStatusDescription = "未开启"
    @Published private(set) var fileTemplates: [FileTemplate] = []
    @Published private(set) var enabledTemplateIDs: Set<String> = []
    @Published private(set) var settingsError: String?

    private var settingsWindow: NSWindow?
    private var templateLoadFailed = false
    private var templateLoadErrorMessage: String?
    private var newFileService: NewFileService?
    private var pasteService: PasteService?
    private var cutChangeCount = -1

    func applicationWillFinishLaunching(_ notification: Notification) {
        NotificationService.shared.configure()
        refreshLaunchAtLoginStatus()
        loadTemplates()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if !FinderCommandURLSelfTest.run() {
            NSLog("FinderCommandURLSelfTest 失败：rckit URL 编解码不能保持原路径")
            assertionFailure("FinderCommandURLSelfTest failed")
        }
        #endif

        if templateLoadFailed {
            let body = templateLoadErrorMessage
                ?? "无法读取 templates.json，新建文件功能不可用。"
            NotificationService.shared.notify(
                title: "模板配置加载失败",
                body: body
            )
        }

        // 菜单栏应用不会收到 applicationOpenUntitledFile。用启动事件区分显式打开和后台指令。
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventClass == AEEventClass(kCoreEventClass),
           event.eventID == AEEventID(kAEOpenApplication),
           event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) == nil,
           event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsServiceItem)) == nil {
            DispatchQueue.main.async { [weak self] in
                self?.showNewFileSettings()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        // 所有 rckit URL 都只在这里进入；不使用 SwiftUI 的 onOpenURL。
        // 再切一次主线程，确保剪贴板与 cutChangeCount 的读写都在主线程发生。
        DispatchQueue.main.async { [weak self] in
            self?.handleIncomingURLs(urls)
        }
    }

    func applicationShouldHandleReopen(_ application: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showNewFileSettings()
        return false
    }

    func showNewFileSettings() {
        NSApp.setActivationPolicy(.regular)
        if let settingsWindow {
            settingsWindow.deminiaturize(nil)
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "RightClickKit 设置"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: NewFileSettingsView(appDelegate: self))
        window.contentMinSize = NSSize(width: 460, height: 440)
        window.setContentSize(NSSize(width: 540, height: 600))
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func setTemplateEnabled(_ enabled: Bool, for id: String) {
        guard fileTemplates.contains(where: { $0.id == id }) else { return }

        var selection = enabledTemplateIDs
        if enabled {
            selection.insert(id)
        } else {
            selection.remove(id)
        }
        saveTemplateSelection(selection)
    }

    func resetTemplateSelection() {
        saveTemplateSelection(Set(fileTemplates.map(\.id)))
    }

    private func saveTemplateSelection(_ enabledIDs: Set<String>) {
        let allIDs = Set(fileTemplates.map(\.id))
        guard TemplateSelection.save(disabledIDs: allIDs.subtracting(enabledIDs)) else {
            settingsError = "无法保存文件类型设置。请再试一次。"
            return
        }

        enabledTemplateIDs = enabledIDs
        settingsError = nil
    }

    func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = (status == .enabled)
        launchAtLoginStatusDescription = description(for: status)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            refreshLaunchAtLoginStatus()

            if enabled && SMAppService.mainApp.status == .requiresApproval {
                NotificationService.shared.notify(
                    title: "开机启动待批准",
                    body: "请到系统设置的登录项中允许 RightClickKit。"
                )
            }
        } catch {
            refreshLaunchAtLoginStatus()
            NotificationService.shared.notify(
                title: "开机启动设置失败",
                body: error.localizedDescription
            )
        }
    }

    func openFinderExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    private func description(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled:
            return "已开启"
        case .requiresApproval:
            return "等待系统批准"
        case .notRegistered:
            return "未开启"
        case .notFound:
            return "不可用"
        @unknown default:
            return "未知"
        }
    }

    private func loadTemplates() {
        do {
            let loadedTemplates = try TemplateCatalog.load()
            templateLoadFailed = false
            templateLoadErrorMessage = nil
            fileTemplates = loadedTemplates
            enabledTemplateIDs = Set(loadedTemplates.map(\.id)).subtracting(TemplateSelection.load())
            newFileService = NewFileService(templates: loadedTemplates)
        } catch {
            NSLog(
                "RightClickKit 无法加载 templates.json：%@",
                error.localizedDescription
            )
            templateLoadFailed = true
            templateLoadErrorMessage = error.localizedDescription
            newFileService = nil
        }

        // 即使模板加载失败，粘贴仍然可用；粘贴服务不依赖模板。
        pasteService = PasteService()
    }

    private func handleIncomingURLs(_ urls: [URL]) {
        dispatchPrecondition(condition: .onQueue(.main))

        for url in urls {
            do {
                let command = try FinderCommandURL.parse(url)
                handle(command)
            } catch {
                NSLog(
                    "RightClickKit 忽略无法解析的 URL %@：%@",
                    url.absoluteString,
                    error.localizedDescription
                )
            }
        }
    }

    private func handle(_ command: FinderCommand) {
        dispatchPrecondition(condition: .onQueue(.main))

        switch command {
        case let .newFile(templateID, directory):
            handleNewFile(templateID: templateID, directory: directory)

        case .cut:
            // 只记录当时的 changeCount；之后剪贴板只要变化，这个剪切状态就自动失效。
            cutChangeCount = NSPasteboard.general.changeCount

        case let .paste(directory):
            handlePaste(directory: directory)
        }
    }

    private func handleNewFile(templateID: String, directory: URL) {
        guard !templateLoadFailed else {
            NotificationService.shared.notify(
                title: "模板配置加载失败",
                body: "无法新建文件：templates.json 未能加载。"
            )
            return
        }

        guard let newFileService = newFileService else {
            NotificationService.shared.notify(
                title: "新建文件失败",
                body: "新建文件服务尚未就绪。"
            )
            return
        }

        newFileService.createFile(templateID: templateID, in: directory)
    }

    private func handlePaste(directory: URL) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let pasteService = pasteService else {
            NotificationService.shared.notify(
                title: "粘贴失败",
                body: "粘贴服务尚未就绪。"
            )
            return
        }

        let pasteboard = NSPasteboard.general
        let sourceURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] ?? []).map { $0 as URL }

        guard !sourceURLs.isEmpty else {
            NotificationService.shared.notify(
                title: "没有可粘贴的文件",
                body: "剪贴板中没有文件。"
            )
            return
        }

        // 在主线程一次性取快照：
        // 1. 剪贴板里的文件 URL 列表
        // 2. 当前 changeCount 是否仍等于剪切时记录的 changeCount
        // 后台只处理这份快照，绝不再访问 NSPasteboard。
        let shouldMove = pasteboard.changeCount == cutChangeCount

        pasteService.paste(
            sourceURLs: sourceURLs,
            to: directory,
            move: shouldMove
        ) { [weak self] successCount, failureCount in
            // 即使 PasteService 已经切回主线程，这里再切一次，保证剪贴板状态操作
            // 和 cutChangeCount 一定在主线程执行。
            DispatchQueue.main.async {
                self?.finishPaste(
                    shouldMove: shouldMove,
                    successCount: successCount,
                    failureCount: failureCount
                )
            }
        }
    }

    private func finishPaste(
        shouldMove: Bool,
        successCount: Int,
        failureCount: Int
    ) {
        dispatchPrecondition(condition: .onQueue(.main))

        // 只有整批移动没有失败，且确实至少移动了一项时，才清空剪贴板。
        // 同目录移动是无操作，不计成功；如果全部都是无操作，也不清空。
        if shouldMove && failureCount == 0 && successCount > 0 {
            NSPasteboard.general.clearContents()
            cutChangeCount = -1
        }
    }
}
