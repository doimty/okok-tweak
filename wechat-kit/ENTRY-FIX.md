# alpha2：插件入口修复

本次授权：补插件收纳、增加兜底，并参照其他插件。只推独立新分支云构建，不安装、不重启、不清未读。

## 已查证

- alpha1 已安装且 dylib 已映射，不是用户安装错误。源码未调用 WCPluginsMgr，且设置入口错误依赖两条 Hook 同时成功。
- BubbleBox 在 0x3658b4 调用 objc_msgSend(sharedInstance)，0x365900 调用 objc_msgSend(registerControllerWithTitle:version:controller:)；参数含 BubbleBox、1.0.7、BubbleBoxSettingsViewController 类名字符串。主会话从实际样本调用窗口、选择器槽及导入桩复核，不只依赖 strings。
- wcplugins 的 controller 是 NSString，打开时解析控制器类名。plugins getter 懒初始化数组。未声称完整还原 BubbleBox 注册调度时机，也未把旧 WCR/WCP 入口推断当成事实。

## 改动

1. 动态查找 WCPluginsMgr，逐方法检查 ABI，登记 WeChatKit / 0.1.0-alpha2 / WCKSettingsViewController。
2. 按 controller 类名查重，登记后回读确认，不改已有插件；主线程重入保护，晚加载可重试。入口不依赖总开关。
3. 微信设置页追加备用设置行，并保留右上 WCK；独立安装 viewDidLoad、willAppear、viewDidAppear:、reloadTableData，不再 AND 联动。
4. 在收纳 initData 前尝试登记；启动、激活及有界延迟重试处理加载顺序。
5. 保留宿主导航按钮、原 section、原 IMP；列表需实际 ABI 和 ivar 类型匹配，任一缺失则只保留其他独立入口。

## 验证层次

- 已有 C 策略44断言、3有效变异及设置/功能合同继续运行。
- 新增7组入口源码合同。11生产源文件双架构 Apple SDK 对象编译。
- 云端执行生产 Registry.m 的13个 Foundation 隔离用例，并运行3种可编译缺陷变异：漏登记、漏查重、Class误当类名字符串。不是微信/UIKit实机证据。
- 云构建成功后仍需核验 PAC00、包版本/过滤器、签名页哈希。
- 没有在用户微信里运行修复代码，不宣称入口已可见/可打开。原业务功能仍仅3项实验，其余10项未实现。
