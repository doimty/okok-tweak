# 1.0.9 首页两处推广位实验包

## 基线与范围
- 基线 5e4b79b（1.0.8），隔离分支 feat/xiaocan-home-promotions-109。
- 不改现有开屏行为，不处理其他未触发弹窗/插屏，不访问订单、任务或领奖数据。
- 本次交付为构建包，不包含安装或重启设备。

## 已有证据与假设
- 小蚕 3.21.6/build3006：底部容器为 HomeBottomCenterBar；隐藏整容器后命中测试落到正常列表，可恢复。
- 中部 IndexPicCell 是 HomeCategoryOuterTableView 的 UITableView 行，HomeScene 提供 double 行高。临时针对当前推广行返回0.01后，下行同步上移约111.84点，撤销完全恢复。
- section0/row0只是当前样本，绝不可硬编码。不是所有 IndexPicCell 或该域名/目录资源都已确认是广告。
- 单图完整URL匹配已证明能在 UIImageView 双参 SDWebImage 入口清图并恢复；不是 NSURLSession 网络取消证据。
- 唯一精确素材规则来自刚复核的已确认组件：
  https://jpg.realtech-inc.com/silkworm_explore/xiaohongshu_jpg/17924017335172747c960f5953823e343bacaf070b148.gif
- 暂未完成持续规则在刷新/切页/冷启后的真机验收；素材更换时应放行未知素材，不能扩大目录规则。

## 最小实现
1. 新增独立 HomePromotions.xm，bundle/版本/运行时类与关键方法签名不符时禁用对应新路径。
2. 精确类隐藏底部容器，钳制 hidden/interaction 并在加入窗口时施加；不通配 Floating/Popup。
3. 图片入口只在 IndexPicCell 祖先链内命中完整素材URL时置空URL与占位；记录确认标记以便原sd_imageURL变nil后仍能识别。
4. 行高只作用于 HomeCategoryOuterTableView 内已确认的当前推广项；先按实时 cell/indexPath 标记，下一轮主队列安全更新行高。其他行必须执行原实现。
5. 无硬编码行号、无Swift字段偏移写入；复用、重新绑定正常图、reload及行/section增删移动时清理旧标记并恢复曾改变的hidden/interaction。注册状态使用弱cell引用并防止异步重排使用过期状态。
6. reflow合并去重，禁止在行高/布局回调内直接递归begin/endUpdates；无全局扫描、轮询或重复请求。

## 成功标准与独立失败信号
- 现有22项native-skip测试继续通过，开屏逻辑diff只允许版本日志变化。
- 新增纯C生产策略测试：精确URL正例及不同hash、查询参数、同目录、同host业务图、无容器/不兼容版本等负例。
- 新增Foundation-only生产注册表回归：标记、复用清理、迁移、替换、失效与弱引用释放；CI直接执行真实实现，不手写另一套策略。
- 源码检查无硬编码行号/整域封禁/Swift裸偏移；git diff --check、actionlint通过；云端策略/注册表测试及双架构编译通过。
- 安装包版本/依赖/filter/arm64+arm64e与新旧入口一致，SHA256落盘。
- 任何正常行被压缩、复用后误隐藏、更新触发循环、版本不符仍启用新组、缺签名仍hook、构建/回归失败，均不可称交付通过。
- 本地C测试及云编译不代替真机持续性与视觉验收，交付须明确剩余边界。
