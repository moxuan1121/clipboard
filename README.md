# clipboard

独立的 iOS 15 / Dopamine RootHide 剪贴板历史插件。

包标识符：`com.moxuan1121.clipboard`。保存文字和图片，最多 500 条，无收藏功能。
点击屏幕右侧「剪贴板」或设置页「打开历史记录」查看；点面板外侧收起。
点击条目写入系统剪贴板，并向可用输入目标发送系统 `paste:` 操作，支持的输入框自动粘贴；没有目标时保留在剪贴板。

注入只允许 SpringBoard 和 druid，不注入 UIKit 或其他应用。系统键盘代理与部分应用/自定义键盘的粘贴兼容性需真机验证。
窗口优先级设为 10000000；其他插件仍可创建更高窗口，本插件不循环争抢优先级。
设置提供启用、侧边按钮、180–900pt 面板高度和 iOS 15 粘贴提醒开关。
设置图标固定为 29pt，并提供 1x/2x/3x 资源。标准 Preferences 控制器负责导航。

历史存放 `/var/mobile/Library/Clipboard/history.sqlite`，仅本地存储。安装、升级、卸载均无维护脚本；由 dpkg 移除本包文件，保留用户历史。
禁用时停止新捕获并隐藏面板。锁屏时隐藏面板和入口。

构建：RootHide Theos + iPhoneOS16.5 SDK，执行 `python3 tools/icon.py` 后 `make package FINALPACKAGE=1`。
GitHub Actions 自动构建并检查包路径、包名、架构和维护脚本。
执行 `python3 tests/check.py` 验证 500 条限制、文字/图片存储及注入过滤。

行为参考 Kayoko，源代码为独立实现，不包含 Kayoko 的收藏、分词、搜索或第三方分词依赖。
