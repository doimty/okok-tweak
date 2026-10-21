# WeChatKit：三插件功能合并 —— 侦察与实施边界（2026-10-21）

目标：新建一个自研插件，包含 WCPulse / WCRefine / WeX 中列出的功能。
前提：三者均为闭源 dylib（WCPulse 10.9MB、WCRefine 45MB、WeX 40MB），
没有源码可搬，只能按 hook 逐项重写。

## 一、功能映射（配置线索，不等于已证明 hook）

| 功能 | 来源 | 开关 / 键 | 实现线索 | 难度 |
|---|---|---|---|---|
| 工具栏位 | WCPulse | `toolbarVerticalOffset`、`toolbarHorizontalOffset`、`toolbarItemSpacingOffset` | `WCPulseToolBarView` 的位置拖拽、居中/分页/双列/缩放 | 中 |
| 启用上滑展开键盘 | WCPulse | `enableKeyboardUpGesture` | 聊天页手势，需自建 pan 识别 | 中 |
| 群内好友添加时间榜 | WCPulse | `enableFriendAddTimeRank`、`groupMemberProfileHistoryPlacement` | 群资料页「好友添加时间榜」 | 中 |
| 一键已读 | WCRefine | 无常驻开关 | `WCRefineClearUnreadMsgHook`，`+load` 给 `NewMainFrameViewController` 加方法，长按底栏触发 | 低 |
| 界面净化 | WCRefine | `hide*` 约 60 个键（`hideSettingsXxx`、`hideMyPageXxx`、`hideContactsXxx`、`hideMainFrameXxx` 等） | 每个键对应一处隐藏/去入口，逐项 hook | 高 |
| 全局圆角 | WCRefine | `globalCornerRadius/Margin/Spacing/...` + 各模块 corner 键约 40 个（`mainFrameCornerEnabled`、`momentCorner*`、`topbarCorner*`、`chatBubbleCornerRadius`、`toolbarCorner*`、`systemPopupCorner*` 等） | 逐模块设置圆角/边框，逐项 hook | 高 |
| 朋友圈详细时间 | WCRefine | `momentsDetailedTimeEnabled`、`momentsDetailedTimeFormat` | 朋友圈时间标签格式化 | 低 |
| 强开聊天页半屏相册 | WCRefine | `abTestChatAlbumPageSheetMode`（整数） | 相册选择器 presentation 模式 | 低 |
| 禁止热更新 | WCRefine | `hotUpdateDisabled` | 热更新入口/检查 | 低 |
| 专属命名（顶部标签） | WCRefine | 原 `bottomTabNameCustomEnabled/customTabNames` 仅为底栏命名线索，不能作为本项映射 | 原字符串邻近微信首页、展开/折叠与分组文案，真实顶部标题/标签入口待定位 | 待核 |
| Svg 图标改色 | WCRefine | `svgColorEnabled`、`svgColorUseFixedColor`、`svgFixedColorLight/Dark`、`svgRandomPaletteHexes`、`svgColorIncludeIconNames`、`svgColorExcludeIconNames` | 图标渲染 tint | 中 |
| 消息复读标签 | WCRefine | `repeatEnhanceEnabled`、`repeatBattleMode`、`repeatTextContentSelf/Other`、`repeatButtonSize` 等 | 消息旁复读按钮/气泡标签 | 中 |
| 群聊标签 | WeX | 同时有 `chat.badgeStyle.group.v1`、`chat.groupBadge.position` 和 `sessionGroup.*` 两组不同线索 | 不擅自等同会话分组 Tab，需核对应 UI | 待核 |

## 二、规模边界（纠正早期推算）

- 早前的「净化约60键、圆角约40键」是整个偏好键的粗筛，不等于UI精确功能数，撤回把它当完整子项数量的表述。
- 用户要的两页「里面所有功能」仍是目标；目前尚无完整逐项目录与行为闭环，不声称完成。
- 原单点功能难度栏是初筛，不代表热更新、半屏、时间已有可安全调用的私有接口。

## 三、实际首批（0.1.0-alpha1，源码候选）

- **已写源码**：上滑键盘、SVG精确白名单改色、底栏微信长按一键已读。
- **支撑**：独立设置入口/偏好文件、默认关闭、微信8.0.69.33版本+ABI门控、未完成项禁用。
- **尚未实现**：其余10项，包含净化/圆角所有子项；不把原需求改成底栏命名或会话分组。
- **验证**：实际Apple SDK对象编译与宿主C策略测试；尚未链接deb、云构建或真机验收。

只构建一个自包含插件，不复用原三个dylib；后续源码增量迭代，不另装多份同名插件。

## 四、源码与授权现况

- 用户已明确没有源码，不再重复索取。
- 本轮仅本地开发，未commit/push/创建远端仓库/触发云构建/安装/更改微信数据。
- 完整进度见 `STATUS.md`，实施边界见 `PLAN.md`。
