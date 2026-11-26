import Foundation
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                NSLog("RightClickKit 通知授权失败：%@", error.localizedDescription)
            }
            if !granted {
                NSLog("RightClickKit 未获得通知授权，操作结果将只写入日志")
            }
        }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                NSLog("RightClickKit 发送通知失败：%@", error.localizedDescription)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // App 在前台时也显示横幅，否则用户会以为操作没有完成。
        completionHandler([.banner, .sound])
    }
}
