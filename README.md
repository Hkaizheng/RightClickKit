# RightClickKit

RightClickKit 是一个 macOS 菜单栏应用，配合 Finder Sync 扩展提供新建文件、复制、剪切和粘贴操作。项目最低支持 macOS 13.0，使用 Swift 5 语言模式。

## 下载和安装

1. 下载最新版本的 DMG，支持 macOS 13 及以上版本、Apple 芯片和 Intel 芯片。[RightClickKit Releases](https://github.com/Hkaizheng/RightClickKit/releases/latest)
2. 打开 DMG，将 RightClickKit 拖入「应用程序」。若已有旧版，先退出旧版，再替换。
3. 从「应用程序」打开 RightClickKit。当前试用版使用临时签名，尚未通过 Apple 公证。如果 macOS 拦截，确认下载来源后，前往「系统设置 → 隐私与安全性」查看是否有「仍要打开」选项。[Apple 关于打开 App 的说明](https://support.apple.com/zh-cn/102445)
4. 在 RightClickKit 的菜单栏菜单中选择「打开 Finder 扩展设置」，启用扩展。然后在访达文件夹空白处右键，展开「新建文件」。

## 工程

| Target | Bundle ID | 沙盒 |
| --- | --- | --- |
| RightClickKit | `com.hkz.RightClickKit` | 关闭 |
| RightClickKitFinder | `com.hkz.RightClickKit.Finder` | 开启 |

## 签名和构建

1. 在 Xcode 中打开 `RightClickKit.xcodeproj`，选择项目的 `RightClickKit` 和 `RightClickKitFinder` 两个 target。
2. 分别在 `Signing & Capabilities` 中勾选 `Automatically manage signing`，并为两个 target 选择同一个个人 Team。如果列表中没有个人 Team，先在 `Xcode → Settings → Accounts` 登录 Apple 账号。
3. 选择 `RightClickKit` scheme 和 `My Mac`，执行 Build & Run。

也可以在工作区执行以下命令。此命令将构建结果放在工作区的 `build/Build/Products/Debug/RightClickKit.app`。

```bash
xcodebuild -list -project RightClickKit.xcodeproj
xcodebuild -project RightClickKit.xcodeproj -scheme RightClickKit -configuration Debug -derivedDataPath build build
```

工程将 Team 留空。Xcode 可以使用 `Sign to Run Locally` 生成本机临时签名的构建。如果当前环境要求选择 Team，可以在命令末尾加 `CODE_SIGNING_ALLOWED=NO` 检查编译。该选项生成未签名构建，运行验证需使用签名后的产物。

## Office 模板

工程已包含从本机 WPS 安装中复制的空白 Office 模板，分别位于以下位置。

```text
RightClickKit/Resources/Templates/blank.docx
RightClickKit/Resources/Templates/blank.xlsx
RightClickKit/Resources/Templates/blank.pptx
```

如需替换模板，可用 Office 或 `python-docx`、`openpyxl`、`python-pptx` 生成有效的空白文件并使用相同文件名，之后重新构建。缺少模板时，对应的新建操作会通知“找不到模板”，不会创建该文件。`Templates` 在工程中是仅归主 App 的文件夹引用，以保留 bundle 内的 `Contents/Resources/Templates/` 目录。`RightClickKit/Resources/templates.json` 和 `Shared/` 中的三个 Swift 文件属于两个 target。主 App 的 Swift 文件只属于主 App，`FinderSync.swift` 只属于扩展。

工程使用显式文件引用。旧版 Xcode 可通过 File Inspector 的 Target Membership 和各 target 的 Build Phases 检查归属。如果日后改用 Xcode 16 或更新版本的同步文件夹，请检查 Membership Exceptions 或将文件放进对应 target 的同步目录，同时保留 `Templates` 这一层文件夹。构建后可检查资源。

```bash
APP="build/Build/Products/Debug/RightClickKit.app"
APPEX="$APP/Contents/PlugIns/RightClickKitFinder.appex"
ls -l "$APP/Contents/Resources/templates.json"
ls -l "$APP/Contents/Resources/Templates/"
ls -l "$APPEX/Contents/Resources/templates.json"
```

构建后，还应检查 `"$APP/Contents/Resources/Templates/blank.docx"`、`blank.xlsx` 和 `blank.pptx` 均存在。

## 设置新建文件类型

双击 `/Applications/RightClickKit.app` 打开设置，或点击菜单栏图标并选择“设置…”。十种文件类型默认全部启用，可通过开关选择 Finder 右键菜单中显示的类型。更改会立即保存，下一次打开 Finder 右键菜单时生效。全部关闭时，“新建文件”子菜单将隐藏。点击“恢复默认”可重新启用全部类型。

开发时 Xcode 或命令行生成的 App 位于各自的构建目录，测试 Finder 扩展和 `rckit://` 时应确认只有准备测试的版本被系统注册和使用，避免安装版与开发版互相干扰。

## 启用 Finder 扩展

构建并运行已签名的主 App 后，使用以下命令启用并检查扩展。`killall Finder` 会重新启动 Finder，请在方便时手动执行。主 App 菜单栏也提供“打开 Finder 扩展设置”。

```bash
pluginkit -e use -i com.hkz.RightClickKit.Finder
pluginkit -m -p com.apple.FinderSync | grep com.hkz.RightClickKit.Finder
killall Finder
```

测试前检查 `RightClickKit.app` 的副本和已注册的扩展路径。下面的命令检查常见安装和构建位置。如果使用了其他输出目录，也检查该目录。命令行构建和 Xcode 默认构建分别使用 `build` 和 DerivedData。进行 URL 或 Finder 测试时，确认只有准备测试的 App 被注册和使用。

```bash
find /Applications "$HOME/Applications" "$HOME/Library/Developer/Xcode/DerivedData" build \
  -type d -name 'RightClickKit.app' -prune -print 2>/dev/null
pluginkit -m -v -p com.apple.FinderSync | grep -A 3 com.hkz.RightClickKit.Finder
```

## 手工测试清单

- 在含中文、空格、`#`、`&` 和 `+` 的路径下用 Finder 新建文件，检查文件名和位置。
- 在桌面新建文件，并观察首次访问桌面、文稿或下载目录时的系统隐私授权弹窗。根据需要允许访问。
- 在同一文件夹复制并粘贴文件，检查是否生成 `名称 2.ext`。在同一文件夹剪切并粘贴，检查文件保持原位且提示无需移动。
- 将文件夹粘贴到自身及其子目录，检查操作被拒绝。
- 在不同磁盘之间剪切并粘贴，检查目标文件存在且源文件已移除。
- 剪切文件后再复制其他内容，检查粘贴按当前剪贴板执行复制，原剪切文件仍在原处。
- 剪切并成功粘贴后再粘贴，检查剪贴板已清空，Finder 菜单不再显示粘贴项。
- 缺少 Office 模板时尝试新建对应文件，检查通知和安全返回。补齐模板后，分别新建并用 Office 或兼容软件打开三个文件。
- 在设置中关闭和重新启用文件类型，检查下一次打开 Finder 右键菜单时的显示情况。全部关闭时检查“新建文件”子菜单隐藏，恢复默认后检查十种类型重新显示。
- 检查通知横幅、Finder 菜单项的显示条件、菜单栏的扩展设置入口和开机启动开关。

开机启动使用 `SMAppService.mainApp`。从 DerivedData 运行的 App 可能注册失败，失败时会发通知。Finder、剪贴板、通知、跨磁盘操作及系统隐私授权均需要在实际环境中验证。

调试命令和资源检查见 [DEBUG.md](DEBUG.md)。
