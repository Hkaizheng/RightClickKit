import Darwin
import Foundation

// 新建文件服务只运行在主 App（未开沙盒），扩展只发指令、不落盘。
// 所有文件操作放到串行队列，既避免阻塞菜单栏，也保证连续新建时序号不会撞车。
final class NewFileService {
    private let templates: [FileTemplate]
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(
        label: "com.hkz.RightClickKit.new-file",
        qos: .userInitiated
    )

    init(templates: [FileTemplate]) {
        self.templates = templates
    }

    func createFile(templateID: String, in directory: URL) {
        // 空数组通常表示启动时 templates.json 加载失败，单独提示，避免误报成“未知 id”。
        guard !templates.isEmpty else {
            notifyOnMain(
                title: "模板配置加载失败",
                body: "templates.json 未成功加载，无法新建文件。请查看日志后重试。"
            )
            return
        }

        guard let template = templates.first(where: { $0.id == templateID }) else {
            notifyOnMain(
                title: "找不到模板配置",
                body: "模板 id \(templateID) 不在 templates.json 中。"
            )
            return
        }

        queue.async { [weak self] in
            self?.performCreate(template: template, in: directory)
        }
    }

    private func performCreate(template: FileTemplate, in directory: URL) {
        let normalizedDirectory = directory.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: normalizedDirectory.path,
            isDirectory: &isDirectory
        ) else {
            notifyOnMain(
                title: "新建文件失败",
                body: "目标目录不存在：\(normalizedDirectory.path)"
            )
            return
        }

        guard isDirectory.boolValue else {
            notifyOnMain(
                title: "新建文件失败",
                body: "目标路径不是文件夹：\(normalizedDirectory.path)"
            )
            return
        }

        guard fileManager.isWritableFile(atPath: normalizedDirectory.path) else {
            notifyOnMain(
                title: "新建文件失败",
                body: "目标目录没有写权限：\(normalizedDirectory.path)"
            )
            return
        }

        let templateURL: URL?
        if let templateFileName = normalizedTemplateFileName(template.template) {
            templateURL = bundleTemplateURL(fileName: templateFileName)
            if templateURL == nil {
                NSLog("RightClickKit 找不到模板 %@", templateFileName)
                notifyOnMain(
                    title: "找不到模板",
                    body: "找不到模板 \(templateFileName)。"
                )
                return
            }
        } else {
            templateURL = nil
        }

        for index in 1...1000 {
            let fileName = candidateFileName(
                baseName: template.defaultName,
                ext: template.ext,
                index: index
            )
            let destination = normalizedDirectory.appendingPathComponent(
                fileName,
                isDirectory: false
            )

            if let templateURL = templateURL {
                // copyItem 在目标已存在时会抛错，正好用来保证“只创建不覆盖”。
                if fileManager.fileExists(atPath: destination.path) {
                    continue
                }

                do {
                    try fileManager.copyItem(at: templateURL, to: destination)
                    notifyOnMain(
                        title: "已新建文件",
                        body: "已创建 \(fileName)"
                    )
                    return
                } catch {
                    if isAlreadyExistsError(error) {
                        continue
                    }
                    notifyOnMain(
                        title: "新建文件失败",
                        body: "\(fileName)：\(error.localizedDescription)"
                    )
                    return
                }
            } else {
                // 不用 FileManager.createFile(atPath:contents:)，它会覆盖同名文件；
                // O_EXCL 让“检查不存在 + 创建”在内核里原子完成。
                let fileDescriptor = destination.path.withCString { pathPointer in
                    Darwin.open(
                        pathPointer,
                        O_WRONLY | O_CREAT | O_EXCL,
                        mode_t(0o644)
                    )
                }

                if fileDescriptor >= 0 {
                    _ = Darwin.close(fileDescriptor)
                    notifyOnMain(
                        title: "已新建文件",
                        body: "已创建 \(fileName)"
                    )
                    return
                }

                let errorCode = errno
                if errorCode == EEXIST {
                    continue
                }

                let reason: String
                if let message = strerror(errorCode) {
                    reason = String(cString: message)
                } else {
                    reason = "errno \(errorCode)"
                }
                notifyOnMain(
                    title: "新建文件失败",
                    body: "\(fileName)：\(reason)"
                )
                return
            }
        }

        notifyOnMain(
            title: "新建文件失败",
            body: "已尝试 1000 个文件名，目标目录中仍有重名。"
        )
    }

    private func normalizedTemplateFileName(_ name: String?) -> String? {
        guard let name = name else {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func candidateFileName(baseName: String, ext: String, index: Int) -> String {
        if index == 1 {
            return "\(baseName).\(ext)"
        }
        return "\(baseName) \(index).\(ext)"
    }

    private func bundleTemplateURL(fileName: String) -> URL? {
        let name = fileName as NSString
        let resourceName = name.deletingPathExtension
        let resourceExtension = name.pathExtension

        // 模板只打包在主 App 的 Resources/Templates 下，扩展 target 不需要这些资源。
        return Bundle.main.url(
            forResource: resourceName,
            withExtension: resourceExtension.isEmpty ? nil : resourceExtension,
            subdirectory: "Templates"
        )
    }

    private func isAlreadyExistsError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileWriteFileExists.rawValue {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(EEXIST) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isAlreadyExistsError(underlying)
        }
        return false
    }

    private func notifyOnMain(title: String, body: String) {
        // 通知统一回主线程发起，不在后台线程猜测 UNUserNotificationCenter 的线程要求。
        DispatchQueue.main.async {
            NotificationService.shared.notify(title: title, body: body)
        }
    }
}
