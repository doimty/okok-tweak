# alpha3：修复主包身份门控误拒绝

## 真机证据

用户安装alpha2后仍无入口。只读SSH确认已安装alpha2，当前微信PID11522实际映射275056B的WeChatKit.dylib。

短Frida只读采样确认：运行时NSBundle.infoDictionary的CFBundleShortVersionString是Default，真实主包Info.plist则为8.0.69 / 8.0.69.33。原纯C精确策略对磁盘字段返回true，WCKHostIsSupported却为false；所有模块状态为空，收纳仅有原3项。

根因：alpha2构造器先判版本，由可变展示元数据得到false并永久缓存，导致收纳注册、列表及右上按钮均未执行。尚未归因是谁改了展示版本，不猜某个插件。

原13例收纳原生测试把WCKHostIsSupported替换为true，因此遗漏了真实前置门控；测试通过不能抵消本次真机失败。

## 修复与验收

新增WCKHostIdentity：从实际mainBundle.bundleURL读取并解析包内Info.plist，校验文件URL、大小、字段类型、bundleIdentifier及可执行文件路径。仍调用原WCKHostMatches精确限制，不允许未知版本，不回退信任展示字段；读取失败不永久缓存false，稳定身份才缓存，NSLock保护。

新增Foundation测试直接链接生产Runtime、HostIdentity、EntryRegistry、Settings、Policy，不替换宿主门控。覆盖17场景（Default、错误build、错误包/可执行文件、损坏/丢失plist恢复、并发等），另3种编译成功的缺陷变异。待云端实际执行才记录PASS。

本地已实际双架构对象编译12源文件，合同检查通过；这不是云链接、安装或修复后真机入口显示证据。本轮只读attach未hook、未改内存/配置、未执行收纳注册或清未读。正式包仍须Xcode云编审包，安装与重启不自动执行。
