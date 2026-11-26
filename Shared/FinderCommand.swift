import Foundation

enum FinderCommand: Equatable {
    case newFile(templateID: String, directory: URL)
    case cut
    case paste(directory: URL)
}

enum FinderCommandError: LocalizedError {
    case invalidURL
    case invalidScheme(String?)
    case missingHost
    case unsupportedHost(String)
    case missingQueryItem(String)
    case duplicateQueryItem(String)
    case emptyQueryItem(String)
    case invalidDirectoryPath(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无法组装 rckit URL"
        case let .invalidScheme(scheme):
            return "URL scheme 不是 rckit（实际为 \(scheme ?? "nil")）"
        case .missingHost:
            return "rckit URL 缺少指令名"
        case let .unsupportedHost(host):
            return "不支持的 rckit 指令：\(host)"
        case let .missingQueryItem(name):
            return "rckit URL 缺少参数：\(name)"
        case let .duplicateQueryItem(name):
            return "rckit URL 参数重复：\(name)"
        case let .emptyQueryItem(name):
            return "rckit URL 参数为空：\(name)"
        case let .invalidDirectoryPath(path):
            return "目录必须是绝对路径：\(path)"
        }
    }
}

enum FinderCommandURL {
    static let scheme = "rckit"

    static func makeURL(for command: FinderCommand) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme

        switch command {
        case let .newFile(templateID, directory):
            let id = templateID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw FinderCommandError.emptyQueryItem("type")
            }

            components.host = "new"
            components.queryItems = [
                URLQueryItem(name: "type", value: id),
                URLQueryItem(name: "dir", value: directory.standardizedFileURL.path)
            ]

        case .cut:
            components.host = "cut"

        case let .paste(directory):
            components.host = "paste"
            components.queryItems = [
                URLQueryItem(name: "dir", value: directory.standardizedFileURL.path)
            ]
        }

        guard let url = components.url else {
            throw FinderCommandError.invalidURL
        }
        return url
    }

    static func parse(_ url: URL) throws -> FinderCommand {
        guard url.scheme?.lowercased() == scheme else {
            throw FinderCommandError.invalidScheme(url.scheme)
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw FinderCommandError.invalidURL
        }

        guard let host = components.host?.lowercased(), !host.isEmpty else {
            throw FinderCommandError.missingHost
        }

        let queryItems = components.queryItems ?? []

        switch host {
        case "cut":
            return .cut

        case "new":
            let templateID = try singleValue(named: "type", in: queryItems)
            let rawDirectory = try singleValue(named: "dir", in: queryItems)
            let directory = try directoryURL(from: rawDirectory)
            return .newFile(templateID: templateID, directory: directory)

        case "paste":
            let rawDirectory = try singleValue(named: "dir", in: queryItems)
            let directory = try directoryURL(from: rawDirectory)
            return .paste(directory: directory)

        default:
            throw FinderCommandError.unsupportedHost(host)
        }
    }

    private static func singleValue(named name: String, in queryItems: [URLQueryItem]) throws -> String {
        let matches = queryItems.filter { $0.name == name }

        guard !matches.isEmpty else {
            throw FinderCommandError.missingQueryItem(name)
        }
        guard matches.count == 1 else {
            throw FinderCommandError.duplicateQueryItem(name)
        }
        guard let value = matches[0].value, !value.isEmpty else {
            throw FinderCommandError.emptyQueryItem(name)
        }

        return value
    }

    private static func directoryURL(from path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw FinderCommandError.invalidDirectoryPath(path)
        }

        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}

enum FinderCommandURLSelfTest {
    /// 阶段 4 会在 DEBUG 启动时调用；返回 false 表示 URL 编解码不能保持原路径。
    static func run() -> Bool {
        let paths = [
            "/Users/example/Documents/右键超人/新建 文件夹 #1&2+3",
            "/Users/example/Documents/右键超人/100% 完成 & #2+3",
            "/tmp/中文 空格 & # + % 都要保留",
            "/"
        ]

        for path in paths {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            let expectedPath = path

            if !roundTrip(
                .newFile(templateID: "txt", directory: directory),
                expectedPath: expectedPath
            ) {
                return false
            }

            if !roundTrip(
                .paste(directory: directory),
                expectedPath: expectedPath
            ) {
                return false
            }
        }

        return roundTrip(.cut, expectedPath: nil)
    }

    private static func roundTrip(_ command: FinderCommand, expectedPath: String?) -> Bool {
        do {
            let url = try FinderCommandURL.makeURL(for: command)
            let decoded = try FinderCommandURL.parse(url)

            switch (command, decoded) {
            case let (.newFile(lhsType, lhsDirectory), .newFile(rhsType, rhsDirectory)):
                let pathsMatch = lhsDirectory.standardizedFileURL.path
                    == rhsDirectory.standardizedFileURL.path
                let exactMatch = expectedPath == nil
                    || rhsDirectory.path == expectedPath
                return lhsType == rhsType && pathsMatch && exactMatch

            case let (.paste(lhsDirectory), .paste(rhsDirectory)):
                let pathsMatch = lhsDirectory.standardizedFileURL.path
                    == rhsDirectory.standardizedFileURL.path
                let exactMatch = expectedPath == nil
                    || rhsDirectory.path == expectedPath
                return pathsMatch && exactMatch

            case (.cut, .cut):
                return true

            default:
                print("FinderCommandURLSelfTest: 指令类型不一致，URL = \(url.absoluteString)")
                return false
            }
        } catch {
            print("FinderCommandURLSelfTest: \(error.localizedDescription)")
            return false
        }
    }
}
