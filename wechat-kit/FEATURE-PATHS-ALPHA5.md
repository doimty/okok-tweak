# alpha5 功能路径与覆盖增量

## 范围
- 移除宿主设置页右上 WCK 的创建和追加逻辑；不重写其它插件导航按钮。保留收纳登记、设置列表备用入口。
- SVG：5→12 个实际 WCSVGImage 图像工厂，逐个 ABI 门控；新增四种 UIImage 拉伸/渲染模式/对齐变换后的来源传播。无来源普通图片直接原方法，照片/头像不被通用着色。仍只有浅/深固定色，随机色板、透明度、历史未实现。
- 键盘：32 层有界实际子树归属、排除 UIControl；只对输入框自己的滚动 pan 允许同时识别。输入栏 layout 和 didMoveToWindow 独立补绑，不改录音/附件/表情按钮，不改私有 inputMode。响应返回结果固定字符串记入独立诊断状态，ready 仍只表示安装。
- 已读：MMTabBar 布局和移窗独立绑定；真实 tabBarItemViews 首项替换时撤离旧项并重新绑定；UI 关闭/隐藏/取消停止后续批次。用户名快照逐项验证、复制与去重；每批16、最多5000、账号服务身份与清后回读保护保留。测试仅调用假服务。
- 新增朋友圈列表详细时间：WCTimeLineCellView 的 m_dataItem/m_timeLabel、WCDataItem.createtime（uint32）及 updateWithDataItem:actionAreaVM:/adjustTimeLabelLine 精确 ABI；调用宿主布局，复用和关闭恢复。默认 yyyy-MM-dd HH:mm:ss，可编辑。未宣称覆盖朋友圈详情/所有时间文本。
- 新增聊天半屏相册：ExptService -getExpt:withBoolDef:，只对 clicfg_chat_album_pagesheet_mode 且用户开关开启时返回 YES；其余键/关闭/未知 ABI 完全透传。不要据此修改 NewABTestMgr 或所有实验。

## 本轮证据与已纠正前提
- 先前口头判断“键盘只走一层”和“已读用错 m_nsUsrName”不成立：alpha4 本就循环祖先，GetUserNamesOnSessionList 返回 NSString 用户名，宿主内部读 m_nsUserName 再 safeAddObject:。已明确纠正，未保留字段型伪修复。此版不宣称已经找到真机全部失效根因。
- 原相册注册：参考镜像 VA 0x8e5868..0x8e5894，类 ExptService、方法 getExpt:withBoolDef:；replacement 0x8eac30 内 0x8ebf8c..0x8ec068 精确键和1/2语义。只读入口 0x8ec460 未证实同相册语义，不盲目扩大。
- 时间：参考 formatter 0x561414 接 uint32，宿主实际 WCDataItem.createtime 是 I16@0:8；本实现只操作已证列表标签，不拦通用 NSDateFormatter。
- 用户已装 alpha4。新增只读探针依次遭遇消息协议不匹配、CGRect bridge 类型异常、transport timeout，未得到有效新快照。错误后停止，不冷启/重启/清未读，不计真机成功。

## 验证分层
- Linux C 策略运行和源码合同；Apple SDK16.4 arm64/arm64e 实际对象编译。
- macOS Foundation 执行生产源：SVG模型、键盘/时间/相册模型、已读服务模型。包括关闭、复用、异常 ABI、账号切换/取消与可编译缺陷变异。模型不是 UIKit、像素或真机服务。
- 云 Xcode 链接/签名/RootHide 打包及签名页审包结果以本轮 BUILD-REPORT 为准；源码提交时不提前声称成功。
- 不自动安装或重启。没有实际清用户未读、发消息、修改原插件配置。其余8项仍未实现，不能把灰色项目称生效。
