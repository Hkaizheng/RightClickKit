import Foundation

enum TemplateSelection {
    static let didChange = Notification.Name("com.hkz.RightClickKit.templateSelectionDidChange")

    private static let domain = "com.hkz.RightClickKit" as CFString
    private static let key = "DisabledNewFileTemplateIDs" as CFString

    static func load() -> Set<String> {
        CFPreferencesAppSynchronize(domain)
        let disabledIDs = CFPreferencesCopyAppValue(key, domain) as? [String] ?? []
        return Set(disabledIDs)
    }

    static func save(disabledIDs: Set<String>) -> Bool {
        CFPreferencesSetAppValue(key, disabledIDs.sorted() as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else {
            return false
        }

        DistributedNotificationCenter.default().postNotificationName(
            didChange,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
}
