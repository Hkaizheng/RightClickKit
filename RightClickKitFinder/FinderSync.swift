import Cocoa
import FinderSync
import OSLog

/// Finder Sync 扩展处于系统沙盒中，只负责菜单、剪贴板和 rckit URL 指令。
/// 所有用户文件的创建、复制、移动、删除都由非沙盒的主 App 完成。
final class FinderSync: FIFinderSync {
    private enum MenuTag {
        static let copy = 1
        static let cut = 2
        static let paste = 3
        static let pasteIntoFolder = 4

        // 新建文件子菜单使用“固定偏移 + 模板数组下标”作为 tag。
        // Finder Sync 的菜单跨进程代理，representedObject 在 action 里可能丢失，
        // 因此这里只依赖 tag，不依赖 representedObject 或 target 传值。
        static let newFileBase = 1000
        static let copyFolderBase = 2000
        static let moveFolderBase = 3000
    }

    private let transport: CommandTransport
    private let newFileLog = Logger(subsystem: "com.hkz.RightClickKit.Finder", category: "NewFile")
    private let templates: [FileTemplate]
    private let templateIcons: [NSImage]
    private let destinationIcons: [NSImage]
    private let templateLoadFailed: Bool
    private var disabledTemplateIDs: Set<String> = []

    override init() {
        // RightClickKit.app/Contents/PlugIns/RightClickKitFinder.appex
        let applicationURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        self.transport = URLSchemeCommandTransport(applicationURL: applicationURL)
        self.destinationIcons = FolderTransferDestination.allCases.map(Self.makeDestinationIcon)

        do {
            let templates = try TemplateCatalog.load()
            self.templates = templates
            self.templateIcons = templates.map(Self.makeTemplateIcon)
            self.templateLoadFailed = false
        } catch {
            NSLog(
                "RightClickKitFinder 无法加载 templates.json：%@",
                error.localizedDescription
            )
            self.templates = []
            self.templateIcons = []
            self.templateLoadFailed = true
        }

        super.init()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(reloadTemplateSelection(_:)),
            name: TemplateSelection.didChange,
            object: nil,
            suspensionBehavior: .coalesce
        )
        disabledTemplateIDs = TemplateSelection.load()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func reloadTemplateSelection(_ notification: Notification) {
        disabledTemplateIDs = TemplateSelection.load()
    }

    private var pasteboardHasFileURLs: Bool {
        NSPasteboard.general.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        switch menuKind {
        case .contextualMenuForContainer:
            return makeContainerMenu()

        case .contextualMenuForItems:
            return makeItemsMenu()

        default:
            return NSMenu(title: "")
        }
    }

    private func makeContainerMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        // Finder 跨进程菜单不依赖 responder chain 自动启用，手动控制启用状态。
        menu.autoenablesItems = false

        let newFileSubmenu = makeNewFileSubmenu()
        if newFileSubmenu.numberOfItems > 0 {
            let newFileItem = NSMenuItem(
                title: "新建文件",
                action: nil,
                keyEquivalent: ""
            )
            newFileItem.submenu = newFileSubmenu
            menu.addItem(newFileItem)
        }

        if pasteboardHasFileURLs {
            let pasteItem = NSMenuItem(
                title: "粘贴",
                action: #selector(pasteIntoContainer(_:)),
                keyEquivalent: ""
            )
            pasteItem.tag = MenuTag.paste
            menu.addItem(pasteItem)
        }

        return menu
    }

    private func makeNewFileSubmenu() -> NSMenu {
        let submenu = NSMenu(title: "新建文件")
        submenu.autoenablesItems = false

        if templateLoadFailed {
            let failureItem = NSMenuItem(
                title: "模板配置加载失败",
                action: nil,
                keyEquivalent: ""
            )
            failureItem.isEnabled = false
            submenu.addItem(failureItem)
            return submenu
        }

        for (index, template) in templates.enumerated() where !disabledTemplateIDs.contains(template.id) {
            let item = NSMenuItem(
                title: Self.menuTitle(for: template),
                action: #selector(createNewFile(_:)),
                keyEquivalent: ""
            )
            item.tag = MenuTag.newFileBase + index
            item.image = templateIcons[index]
            if #available(macOS 27.0, *) {
                item.preferredImageVisibility = .visible
            }
            submenu.addItem(item)
        }

        return submenu
    }

    private static func menuTitle(for template: FileTemplate) -> String {
        switch template.id {
        case "md": return "Markdown"
        case "py": return "Python"
        case "sh": return "Shell"
        default: return template.ext.uppercased()
        }
    }

    private static func makeTemplateIcon(for template: FileTemplate) -> NSImage {
        let appearance: (symbol: String, color: UInt32)
        switch template.id {
        case "txt": appearance = ("text.alignleft", 0x54677C)
        case "docx": appearance = ("text.justify.left", 0x2366CA)
        case "pptx": appearance = ("chart.pie.fill", 0xC34F35)
        case "xlsx": appearance = ("tablecells", 0x198257)
        case "md": appearance = ("arrow.down", 0x46759C)
        case "json": appearance = ("curlybraces", 0x9A5B00)
        case "html": appearance = ("chevron.left.forwardslash.chevron.right", 0x983B87)
        case "csv": appearance = ("list.bullet", 0x357852)
        case "py": appearance = ("chevron.left.forwardslash.chevron.right", 0x3467B1)
        case "sh": appearance = ("terminal", 0x6551AE)
        default: appearance = ("text.alignleft", 0x54677C)
        }

        let blue = CGFloat(appearance.color & 0xFF) / 255
        let green = CGFloat((appearance.color >> 8) & 0xFF) / 255
        let red = CGFloat(appearance.color >> 16) / 255
        let accent = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            .applying(.init(paletteColors: [.white]))
        let symbol = NSImage(
            systemSymbolName: appearance.symbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)

        return makeMenuIcon { _ in
            let sheet = NSBezierPath()
            sheet.move(to: NSPoint(x: 4, y: 1))
            sheet.line(to: NSPoint(x: 14, y: 1))
            sheet.curve(to: NSPoint(x: 16, y: 3), controlPoint1: NSPoint(x: 15.1, y: 1), controlPoint2: NSPoint(x: 16, y: 1.9))
            sheet.line(to: NSPoint(x: 16, y: 12))
            sheet.line(to: NSPoint(x: 11, y: 17))
            sheet.line(to: NSPoint(x: 4, y: 17))
            sheet.curve(to: NSPoint(x: 2, y: 15), controlPoint1: NSPoint(x: 2.9, y: 17), controlPoint2: NSPoint(x: 2, y: 16.1))
            sheet.line(to: NSPoint(x: 2, y: 3))
            sheet.curve(to: NSPoint(x: 4, y: 1), controlPoint1: NSPoint(x: 2, y: 1.9), controlPoint2: NSPoint(x: 2.9, y: 1))
            sheet.close()
            accent.setFill()
            sheet.fill()

            let fold = NSBezierPath()
            fold.move(to: NSPoint(x: 11, y: 17))
            fold.line(to: NSPoint(x: 16, y: 12))
            fold.line(to: NSPoint(x: 12, y: 12))
            fold.curve(
                to: NSPoint(x: 11, y: 13),
                controlPoint1: NSPoint(x: 11.45, y: 12),
                controlPoint2: NSPoint(x: 11, y: 12.45)
            )
            fold.close()
            NSColor.white.withAlphaComponent(0.42).setFill()
            fold.fill()

            if let symbol {
                let symbolSize = symbol.size
                let fit = min(10 / max(symbolSize.width, 1), 9 / max(symbolSize.height, 1))
                let width = symbolSize.width * fit
                let height = symbolSize.height * fit
                symbol.draw(in: NSRect(
                    x: 9 - width / 2,
                    y: 7 - height / 2,
                    width: width,
                    height: height
                ))
            }

        }
    }

    private func makeItemsMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false

        let copyItem = NSMenuItem(
            title: "复制",
            action: #selector(copySelection(_:)),
            keyEquivalent: ""
        )
        copyItem.tag = MenuTag.copy
        menu.addItem(copyItem)

        let cutItem = NSMenuItem(
            title: "剪切",
            action: #selector(cutSelection(_:)),
            keyEquivalent: ""
        )
        cutItem.tag = MenuTag.cut
        menu.addItem(cutItem)

        if selectedSingleFolderURL() != nil {
            if pasteboardHasFileURLs {
                let pasteItem = NSMenuItem(
                    title: "粘贴到此文件夹",
                    action: #selector(pasteIntoSelectedFolder(_:)),
                    keyEquivalent: ""
                )
                pasteItem.tag = MenuTag.pasteIntoFolder
                menu.addItem(pasteItem)
            }

            for (operation, base) in [
                (FolderTransferOperation.copy, MenuTag.copyFolderBase),
                (.move, MenuTag.moveFolderBase)
            ] {
                let title = operation.menuTitle
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: title)
                submenu.autoenablesItems = false
                for (index, destination) in FolderTransferDestination.allCases.enumerated() {
                    let destinationItem = NSMenuItem(
                        title: destination.menuTitle,
                        action: #selector(transferSelectedFolder(_:)),
                        keyEquivalent: ""
                    )
                    destinationItem.tag = base + index
                    destinationItem.image = destinationIcons[index]
                    if #available(macOS 27.0, *) {
                        destinationItem.preferredImageVisibility = .visible
                    }
                    submenu.addItem(destinationItem)
                }
                item.submenu = submenu
                menu.addItem(item)
            }
        }

        return menu
    }

    private static func makeDestinationIcon(for destination: FolderTransferDestination) -> NSImage {
        let original = destination.directoryURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(named: NSImage.folderName)
        return makeMenuIcon { bounds in
            original?.draw(in: bounds)
        }
    }

    private static func makeMenuIcon(draw: (NSRect) -> Void) -> NSImage {
        // 访达跨进程接收菜单，需要各显示倍率的实际像素和相同的逻辑尺寸。
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size)
        icon.isTemplate = false
        for scale in [2, 1, 3] {
            let side = Int(size.width) * scale
            guard let canvas = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            canvas.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: canvas, flipped: false)
            draw(NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            if let pixels = canvas.makeImage() {
                let bitmap = NSBitmapImageRep(cgImage: pixels)
                bitmap.size = size
                icon.addRepresentation(bitmap)
            }
        }
        return icon
    }

    @objc private func transferSelectedFolder(_ sender: Any?) {
        guard let item = sender as? NSMenuItem,
              let urls = FIFinderSyncController.default().selectedItemURLs(),
              urls.count == 1,
              let source = urls.first else {
            return
        }

        let operation: FolderTransferOperation
        let index: Int
        if (MenuTag.copyFolderBase..<MenuTag.moveFolderBase).contains(item.tag) {
            operation = .copy
            index = item.tag - MenuTag.copyFolderBase
        } else {
            operation = .move
            index = item.tag - MenuTag.moveFolderBase
        }
        guard FolderTransferDestination.allCases.indices.contains(index) else {
            return
        }
        transport.send(.transferFolder(
            source: source,
            operation: operation,
            destination: FolderTransferDestination.allCases[index]
        ))
    }

    private func selectedSingleFolderURL() -> URL? {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(),
              urls.count == 1,
              let url = urls.first else {
            return nil
        }

        do {
            // 此处需要我在沙盒下实测是否可用：
            // Finder Sync 扩展在沙盒中读取选中项的资源属性。
            // 只允许做这一次轻量查询；失败按“不是文件夹”处理。
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            return values.isDirectory == true ? url : nil
        } catch {
            return nil
        }
    }

    @objc private func createNewFile(_ sender: Any?) {
        guard let directory = FIFinderSyncController.default().targetedURL() else {
            newFileLog.error("Finder did not provide a target directory")
            return
        }
        guard let item = sender as? NSMenuItem,
              item.tag >= MenuTag.newFileBase else {
            newFileLog.error("Finder did not provide a valid template menu item")
            return
        }

        let index = item.tag - MenuTag.newFileBase
        guard templates.indices.contains(index),
              !disabledTemplateIDs.contains(templates[index].id) else {
            return
        }

        let template = templates[index]
        transport.send(.newFile(templateID: template.id, directory: directory))
    }

    @objc private func pasteIntoContainer(_ sender: Any?) {
        guard let directory = FIFinderSyncController.default().targetedURL() else {
            return
        }

        transport.send(.paste(directory: directory))
    }

    @objc private func pasteIntoSelectedFolder(_ sender: Any?) {
        guard FIFinderSyncController.default().targetedURL() != nil else {
            return
        }
        guard let urls = FIFinderSyncController.default().selectedItemURLs(),
              urls.count == 1,
              let directory = urls.first else {
            return
        }

        transport.send(.paste(directory: directory))
    }

    @objc private func copySelection(_ sender: Any?) {
        writeSelectionToPasteboard(markAsCut: false)
    }

    @objc private func cutSelection(_ sender: Any?) {
        writeSelectionToPasteboard(markAsCut: true)
    }

    private func writeSelectionToPasteboard(markAsCut: Bool) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(),
              !urls.isEmpty else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.writeObjects(urls as [NSURL]) else {
            NSLog("RightClickKitFinder: 写入剪贴板失败")
            return
        }

        if markAsCut {
            // 剪切必须在剪贴板写入成功后才通知主 App。
            // 主 App 收到 cut 时会记录当时 NSPasteboard.general.changeCount；
            // 如果先发 cut 再写剪贴板，记录到的 changeCount 会失效，粘贴会退化成复制。
            //
            // 复制不发送任何指令：主 App 发现 changeCount 已变化，就会把旧剪切状态视为失效。
            transport.send(.cut)
        }
    }
}
