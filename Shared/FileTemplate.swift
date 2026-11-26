import Foundation

struct FileTemplate: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let ext: String
    let template: String?
    let defaultName: String

    /// template 为 null 或空字符串时，都表示新建空文件。
    var templateFileName: String? {
        guard let template, !template.isEmpty else {
            return nil
        }
        return template
    }
}

enum TemplateCatalogError: LocalizedError {
    case missingResource
    case unreadableResource(URL, Error)
    case invalidJSON(Error)
    case invalidEntry(index: Int, reason: String)
    case duplicateID(String)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "找不到 templates.json；请确认它同时加入了主 App 和 Finder 扩展的 Copy Bundle Resources。"
        case let .unreadableResource(url, error):
            return "读取 templates.json 失败（\(url.path)）：\(error.localizedDescription)"
        case let .invalidJSON(error):
            return "templates.json 解析失败：\(error.localizedDescription)"
        case let .invalidEntry(index, reason):
            return "templates.json 第 \(index + 1) 项无效：\(reason)"
        case let .duplicateID(id):
            return "templates.json 存在重复 id：\(id)"
        }
    }
}

enum TemplateCatalog {
    static func load(from bundle: Bundle = .main) throws -> [FileTemplate] {
        guard let url = templatesURL(in: bundle) else {
            throw TemplateCatalogError.missingResource
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TemplateCatalogError.unreadableResource(url, error)
        }

        let templates: [FileTemplate]
        do {
            templates = try JSONDecoder().decode([FileTemplate].self, from: data)
        } catch {
            throw TemplateCatalogError.invalidJSON(error)
        }

        try validate(templates)
        return templates
    }

    static func templatesURL(in bundle: Bundle) -> URL? {
        if let url = bundle.url(forResource: "templates", withExtension: "json") {
            return url
        }

        // Xcode 16 的同步文件夹可能保留 Resources 这一层，做一个兜底；
        // 阶段 1 的标准布局仍然应该是 Contents/Resources/templates.json。
        return bundle.url(forResource: "templates", withExtension: "json", subdirectory: "Resources")
    }

    private static func validate(_ templates: [FileTemplate]) throws {
        var seenIDs = Set<String>()

        for (index, item) in templates.enumerated() {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                throw TemplateCatalogError.invalidEntry(index: index, reason: "id 不能为空")
            }
            guard seenIDs.insert(id).inserted else {
                throw TemplateCatalogError.duplicateID(id)
            }
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TemplateCatalogError.invalidEntry(index: index, reason: "title 不能为空")
            }
            guard !item.ext.isEmpty,
                  !item.ext.hasPrefix("."),
                  !item.ext.contains("/"),
                  item.ext.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
                throw TemplateCatalogError.invalidEntry(
                    index: index,
                    reason: "ext 不能为空、不能带点、不能含斜杠或空白"
                )
            }
            guard !item.defaultName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !item.defaultName.contains("/") else {
                throw TemplateCatalogError.invalidEntry(
                    index: index,
                    reason: "defaultName 不能为空，且不能含斜杠"
                )
            }
            if let template = item.template, !template.isEmpty {
                guard !template.contains("/"), template != ".", template != ".." else {
                    throw TemplateCatalogError.invalidEntry(
                        index: index,
                        reason: "template 只能是 Templates 目录内的文件名"
                    )
                }
            }
        }
    }
}
