import AppKit
import SwiftUI

struct NewFileSettingsView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("新建文件")
                    .font(.system(size: 23, weight: .semibold))

                Text("选择在 Finder 右键菜单中显示的文件类型。更改会立即保存。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            if let settingsError = appDelegate.settingsError {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(settingsError)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .accessibilityElement(children: .combine)
            }

            if appDelegate.fileTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("无法加载文件类型")
                        .font(.headline)
                    Text("请检查模板配置后重新打开应用。")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(appDelegate.fileTemplates) { template in
                            Toggle(isOn: Binding(
                                get: { appDelegate.enabledTemplateIDs.contains(template.id) },
                                set: { appDelegate.setTemplateEnabled($0, for: template.id) }
                            )) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(template.title)
                                        .fontWeight(.medium)
                                    Text(".\(template.ext)")
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)

                            if template.id != appDelegate.fileTemplates.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))
                    }
                    .padding(24)
                }
            }

            Divider()

            HStack {
                Text("已启用 \(appDelegate.fileTemplates.filter { appDelegate.enabledTemplateIDs.contains($0.id) }.count) / \(appDelegate.fileTemplates.count) 项")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("恢复默认") {
                    appDelegate.resetTemplateSelection()
                }
                .disabled(appDelegate.fileTemplates.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 460, minHeight: 440)
    }
}
