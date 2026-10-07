# clipboard

独立的 iOS 15 / Dopamine RootHide 剪贴板历史插件。

包标识符：`com.moxuan1121.clipboard`。保存文字和图片，最多 500 条，无收藏功能。
通过 `prefs://root=clipboard_history` 或 Darwin 通知 `com.moxuan1121.clipboard.show` 呼出；设置页也可打开。已删除侧边按钮，点面板外侧收起。
面板底部上滑弹出，顶部仅显示「剪切板」。历史以双列圆角卡片显示：文字仅显示内容，图片仅显示缩略图。
点击条目写入系统剪贴板，收起面板后通过系统 Cmd+V 向当前输入框粘贴。没有输入框时保留在剪贴板；锁屏、关闭插件、重新打开面板、切换前台应用或剪贴板再次变化时取消延迟粘贴。
长按文字通过 `RSKAOpenTokens` 打开 RegionShot 分词；长按图片通过 `RSShowFloatingImage` 打开 RegionShot 图片浮窗。仅解析已加载的可选接口，不强制加载或注入 RegionShot；未安装或版本不支持时显示提示。

注入只允许 SpringBoard 和 druid，不注入 UIKit 或其他应用。系统键盘代理与部分应用/自定义键盘的粘贴兼容性需真机验证。
窗口优先级设为 10000000；其他插件仍可创建更高窗口，本插件不循环争抢优先级。
设置提供启用、180–900pt 面板高度和 iOS 15 粘贴提醒开关。
设置图标固定为 29pt，并提供 1x/2x/3x 资源。标准 Preferences 控制器负责导航。

历史存放 `jbroot(@"/var/mobile/Library/Clipboard/history.sqlite")`，仅本地存储。在你的环境下对应 `/var/mobile/Containers/Shared/AppGroup/.jbroot-14B33A65E675FD96/var/mobile/Library/Clipboard/history.sqlite`，随机 RootHide 根目录由系统 API 解析，不写死。
首次升级通过 SQLite backup 将旧 `/var/mobile/Library/Clipboard/history.sqlite` 迁到新位置；不覆盖已有新历史，不删除旧数据库。迁移失败停止本次数据库打开，之后重试，避免默默丢失原历史。
安装、升级、卸载均无维护脚本；由 dpkg 移除本包文件，保留用户历史。不触碰 ElleKit、PreferenceLoader 的程序文件或其他插件。
禁用时停止新捕获并隐藏面板。锁屏时隐藏面板并拒绝呼出。

构建：RootHide Theos + iPhoneOS16.5 SDK，执行 `python3 tools/icon.py` 后 `make package FINALPACKAGE=1`。
GitHub Actions 自动构建并检查包路径、包名、架构和维护脚本。
执行 `python3 tests/check.py` 检查 500 条限制、文字/图片存储、SQLite backup 原语、注入过滤与 UI 关键约束。macOS CI 还直接编译执行 `tests/url.m`，检查真实 URL 解析实现。

行为参考 Kayoko，源代码为独立实现，不包含 Kayoko 的收藏、分词、搜索或第三方分词依赖。
