import AppKit
import Foundation

protocol CommandTransport {
    func send(
        _ command: FinderCommand,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

final class URLSchemeCommandTransport: CommandTransport {
    private let workspace: NSWorkspace
    private let applicationURL: URL

    init(applicationURL: URL, workspace: NSWorkspace = .shared) {
        self.applicationURL = applicationURL
        self.workspace = workspace
    }

    func send(
        _ command: FinderCommand,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let url: URL
        do {
            url = try FinderCommandURL.makeURL(for: command)
        } catch {
            completion(.failure(error))
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.allowsRunningApplicationSubstitution = false

        // 只交给承载此扩展的主 App，避免命令被另一个构建的调试进程接收。
        workspace.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
}

extension CommandTransport {
    /// 菜单 action 用的便捷方法；失败只写日志，不阻塞 Finder 菜单。
    func send(_ command: FinderCommand) {
        send(command) { result in
            if case let .failure(error) = result {
                NSLog("rckit 指令发送失败：%@", error.localizedDescription)
            }
        }
    }
}
