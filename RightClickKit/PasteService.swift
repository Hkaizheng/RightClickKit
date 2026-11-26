import Darwin
import Foundation

// 粘贴服务只由主 App 在后台队列执行，扩展不读写任何文件。
// 剪切/复制判定由 AppDelegate 在主线程对剪贴板取快照后，以 move 参数传入；
// 本类不再访问 NSPasteboard，避免后台线程读到变化后的剪贴板状态。
final class PasteService {
    private enum PasteError: LocalizedError {
        case nameAttemptsExhausted
        case crossVolumeRemoveFailed(Error)

        var errorDescription: String? {
            switch self {
            case .nameAttemptsExhausted:
                return "目标目录中同名文件过多，已尝试 1000 个名称"
            case let .crossVolumeRemoveFailed(error):
                return "跨磁盘移动已复制到目标位置，但删除源文件失败：\(error.localizedDescription)"
            }
        }
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(
        label: "com.hkz.RightClickKit.paste",
        qos: .userInitiated
    )

    func paste(
        sourceURLs: [URL],
        to directory: URL,
        move: Bool,
        completion: @escaping (_ successCount: Int, _ failureCount: Int) -> Void
    ) {
        queue.async { [weak self] in
            self?.performPaste(
                sourceURLs: sourceURLs,
                to: directory,
                move: move,
                completion: completion
            )
        }
    }

    private func performPaste(
        sourceURLs: [URL],
        to directory: URL,
        move: Bool,
        completion: @escaping (Int, Int) -> Void
    ) {
        let target = directory.standardizedFileURL
        let resolvedTarget = target.resolvingSymlinksInPath()

        guard !sourceURLs.isEmpty else {
            finish(
                move: move,
                sourceCount: 0,
                successCount: 0,
                failureCount: 0,
                firstFailureReason: nil,
                completion: completion
            )
            return
        }

        var targetIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: target.path, isDirectory: &targetIsDirectory) else {
            finish(
                move: move,
                sourceCount: sourceURLs.count,
                successCount: 0,
                failureCount: sourceURLs.count,
                firstFailureReason: "目标目录不存在：\(target.path)",
                completion: completion
            )
            return
        }

        guard targetIsDirectory.boolValue else {
            finish(
                move: move,
                sourceCount: sourceURLs.count,
                successCount: 0,
                failureCount: sourceURLs.count,
                firstFailureReason: "目标路径不是文件夹：\(target.path)",
                completion: completion
            )
            return
        }

        guard fileManager.isWritableFile(atPath: target.path) else {
            finish(
                move: move,
                sourceCount: sourceURLs.count,
                successCount: 0,
                failureCount: sourceURLs.count,
                firstFailureReason: "目标目录没有写权限：\(target.path)",
                completion: completion
            )
            return
        }

        var successCount = 0
        var failureCount = 0
        var firstFailureReason: String?

        for sourceURL in sourceURLs {
            let source = sourceURL.standardizedFileURL
            let resolvedSource = source.resolvingSymlinksInPath()

            var sourceIsDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: source.path,
                isDirectory: &sourceIsDirectory
            ) else {
                failureCount += 1
                if firstFailureReason == nil {
                    firstFailureReason = "\(source.lastPathComponent)：源文件已不存在"
                }
                continue
            }

            let isDirectory = sourceIsDirectory.boolValue

            // 用 pathComponents 前缀比较而不是字符串 hasPrefix，
            // 否则 /a/b 会被误判成 /a/bc 的父目录。
            if isDirectory && isSameOrDescendant(resolvedTarget, of: resolvedSource) {
                failureCount += 1
                if firstFailureReason == nil {
                    firstFailureReason = "\(source.lastPathComponent)：不能把文件夹粘贴到它自己或它的子目录"
                }
                continue
            }

            let sourceParent = source.deletingLastPathComponent()
            let sameDirectory =
                sourceParent.pathComponents == target.pathComponents
                || sourceParent.resolvingSymlinksInPath().pathComponents == resolvedTarget.pathComponents

            // 同目录“移动”是 Finder 里常见的误操作，按无操作处理，不计成功也不计失败。
            if sameDirectory && move {
                continue
            }

            do {
                _ = try transfer(
                    source: source,
                    sourceIsDirectory: isDirectory,
                    targetDirectory: target,
                    move: move
                )
                successCount += 1
            } catch {
                failureCount += 1
                if firstFailureReason == nil {
                    firstFailureReason = "\(source.lastPathComponent)：\(error.localizedDescription)"
                }
            }
        }

        finish(
            move: move,
            sourceCount: sourceURLs.count,
            successCount: successCount,
            failureCount: failureCount,
            firstFailureReason: firstFailureReason,
            completion: completion
        )
    }

    private func transfer(
        source: URL,
        sourceIsDirectory: Bool,
        targetDirectory: URL,
        move: Bool
    ) throws -> URL {
        let sourceName = source.lastPathComponent
        let components = sourceIsDirectory
            ? (base: sourceName, ext: "")
            : splitFileName(sourceName)

        // 最多尝试 1000 个名字，避免目标目录异常时无限循环。
        for index in 1...1000 {
            let fileName = candidateName(
                base: components.base,
                ext: components.ext,
                index: index
            )
            let destination = targetDirectory.appendingPathComponent(
                fileName,
                isDirectory: sourceIsDirectory
            )

            if fileManager.fileExists(atPath: destination.path) {
                continue
            }

            do {
                if move {
                    try moveItem(from: source, to: destination)
                } else {
                    try fileManager.copyItem(at: source, to: destination)
                }
                return destination
            } catch {
                if isAlreadyExistsError(error) {
                    continue
                }
                throw error
            }
        }

        throw PasteError.nameAttemptsExhausted
    }

    private func moveItem(from source: URL, to destination: URL) throws {
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            // 跨磁盘时 moveItem 可能返回 EXDEV，退化为“复制 + 删除源文件”。
            guard isCrossDeviceError(error) else {
                throw error
            }

            try fileManager.copyItem(at: source, to: destination)

            do {
                try fileManager.removeItem(at: source)
            } catch {
                throw PasteError.crossVolumeRemoveFailed(error)
            }
        }
    }

    private func splitFileName(_ name: String) -> (base: String, ext: String) {
        // .gitignore 这类以点开头的隐藏文件整体当作文件名，避免生成 “. 2.gitignore”。
        if name.first == "." {
            let rest = name.dropFirst()
            if !rest.contains(".") {
                return (name, "")
            }
        }

        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else {
            return (name, "")
        }

        let extensionStart = name.index(after: dotIndex)
        let fileExtension = String(name[extensionStart...])
        guard !fileExtension.isEmpty else {
            return (name, "")
        }

        let base = String(name[..<dotIndex])
        guard !base.isEmpty else {
            return (name, "")
        }

        return (base, "." + fileExtension)
    }

    private func candidateName(base: String, ext: String, index: Int) -> String {
        if index == 1 {
            return base + ext
        }
        return "\(base) \(index)\(ext)"
    }

    private func isSameOrDescendant(_ child: URL, of parent: URL) -> Bool {
        let childComponents = child.standardizedFileURL
            .resolvingSymlinksInPath()
            .pathComponents
        let parentComponents = parent.standardizedFileURL
            .resolvingSymlinksInPath()
            .pathComponents

        guard childComponents.count >= parentComponents.count else {
            return false
        }

        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
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

    private func isCrossDeviceError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(EXDEV) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isCrossDeviceError(underlying)
        }
        return false
    }

    private func finish(
        move: Bool,
        sourceCount: Int,
        successCount: Int,
        failureCount: Int,
        firstFailureReason: String?,
        completion: @escaping (Int, Int) -> Void
    ) {
        let body: String
        if sourceCount == 0 {
            body = "没有可粘贴的文件。"
        } else {
            let verb = move ? "移动" : "复制"
            var lines = ["已\(verb) \(successCount) 项，失败 \(failureCount) 项。"]
            if move && successCount == 0 && failureCount == 0 {
                lines.append("所选项目已经在目标文件夹中，无需移动。")
            }
            if let firstFailureReason = firstFailureReason {
                lines.append("第一个失败原因：\(firstFailureReason)")
            }
            body = lines.joined(separator: "\n")
        }

        // 通知和 completion 都回主线程：主线程据此决定是否清空剪切状态。
        DispatchQueue.main.async {
            NotificationService.shared.notify(title: "粘贴完成", body: body)
            completion(successCount, failureCount)
        }
    }
}
