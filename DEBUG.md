# RightClickKit 调试

先检查 `RightClickKit.app` 的副本，尤其检查 DerivedData、工作区 `build` 和 `/Applications`，确认只有准备测试的版本被系统注册和使用。多个已注册副本可能导致 URL 或 Finder 扩展使用不同版本。下面的 `APP` 查找 Xcode 默认 DerivedData 中的 Debug 构建。

```bash
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/RightClickKit-*/Build/Products/Debug/RightClickKit.app | head -1)
APPEX="$APP/Contents/PlugIns/RightClickKitFinder.appex"

pluginkit -m -p com.apple.FinderSync
pluginkit -e use -i com.hkz.RightClickKit.Finder
pluginkit -e ignore -i com.hkz.RightClickKit.Finder

killall Finder

log stream --predicate 'process == "RightClickKit"' --level debug
log stream --predicate 'process == "RightClickKitFinder"' --level debug
log show --last 5m --predicate 'process == "RightClickKit"'

codesign -d --entitlements :- "$APP" 2>&1
codesign -d --entitlements :- "$APPEX" 2>&1
codesign --verify --deep --strict --verbose=2 "$APP"
```

上面的启用和停用命令分别执行，`killall Finder` 会重新启动 Finder。也可以在 Console.app 按进程名 `RightClickKit` 或 `RightClickKitFinder` 过滤日志。修改扩展代码后重新 Build & Run，必要时手动执行 `killall Finder`。

如果使用 README 中指定 `-derivedDataPath build` 的构建命令，请用工作区内的产物路径检查。

```bash
APP="build/Build/Products/Debug/RightClickKit.app"
APPEX="$APP/Contents/PlugIns/RightClickKitFinder.appex"
ls -l "$APP/Contents/Resources/templates.json"
ls -l "$APP/Contents/Resources/Templates/"
ls -l "$APPEX/Contents/Resources/templates.json"
/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :NSExtension' "$APPEX/Contents/Info.plist"
codesign -d --entitlements :- "$APP" 2>&1
codesign -d --entitlements :- "$APPEX" 2>&1
```

检查安装版时使用 `/Applications` 下的路径。安装版使用本机签名。

```bash
APP="/Applications/RightClickKit.app"
APPEX="$APP/Contents/PlugIns/RightClickKitFinder.appex"
codesign -d --entitlements :- "$APP" 2>&1
codesign -d --entitlements :- "$APPEX" 2>&1
codesign --verify --deep --strict --verbose=2 "$APP"
pluginkit -m -v -p com.apple.FinderSync | grep -A 3 com.hkz.RightClickKit.Finder
```

主 App 的 `LSUIElement` 应为 true，URL scheme 应包含 `rckit`，沙盒 entitlement 应为 false 或不存在。扩展应包含 Finder Sync 的 `NSExtension` 配置，沙盒 entitlement 应为 true，且不声明 `CFBundleURLTypes`。签名检查需要已签名的构建。

如果 `rckit://` 打开了旧副本，先检查应用副本和扩展注册路径，确认正在测试的版本，再用 LaunchServices 重新注册当前应用并启动一次。执行前将 `APP` 设为要测试的版本路径。

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
open "$APP"
```

## 不依赖 Finder 的新建测试

使用已运行的签名构建，在 `/tmp` 创建独立的测试目录。打开同一条 URL 三次，应得到三个空白文件 `未命名.txt`、`未命名 2.txt`、`未命名 3.txt`。

```bash
TEST_DIR=$(mktemp -d /tmp/rckit-test.XXXXXX)
open "rckit://new?type=txt&dir=$TEST_DIR"
open "rckit://new?type=txt&dir=$TEST_DIR"
open "rckit://new?type=txt&dir=$TEST_DIR"
ls -l "$TEST_DIR"
```

对已有的 `/tmp/rckit 中文 目录 #1&2+3` 执行下列命令，应得到 `未命名.md`。如目录尚未创建，可先运行 `mkdir -p '/tmp/rckit 中文 目录 #1&2+3'`。如果文件列表暂未更新，稍后再检查一次。

```bash
open 'rckit://new?type=md&dir=/tmp/rckit%20%E4%B8%AD%E6%96%87%20%E7%9B%AE%E5%BD%95%20%231%262+3'
ls -l '/tmp/rckit 中文 目录 #1&2+3'
```

工程中的 Office 模板从本机 WPS 安装中复制，位于 `RightClickKit/Resources/Templates/`。构建后检查它们是否保留在 `Contents/Resources/Templates/`。旧版 Xcode 可在 File Inspector 的 Target Membership 和 Build Phases 中检查资源归属。Xcode 16 或更新版本如果使用同步文件夹，请检查 Membership Exceptions 或 target 对应的同步目录。

## 检查文件类型设置

双击 `/Applications/RightClickKit.app` 或从菜单栏图标选择“设置…”。十种类型默认全部启用，开关变更会立即保存，并在下一次打开 Finder 右键菜单时生效。全部关闭时，“新建文件”子菜单应隐藏。可用“恢复默认”重新启用全部类型。
