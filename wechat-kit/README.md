# WeChatKit · independent experimental source

按用户选定功能独立编写的微信插件工程，不包含 WCPulse/WCRefine/WeX 二进制、授权逻辑、网络服务、图标或私有转储。

**alpha5 移除右上 WCK；扩大 SVG 工厂及变换后覆盖，补键盘/已读布局绑定，新增朋友圈列表详细时间和聊天半屏相册两项实验功能。** 当前共5项业务候选，其余8项仍未实现；WCR随机色板/透明度/历史未实现。用户反馈 alpha4 部分改色可见但覆盖不全、其余功能未生效，本轮真机采样失败，不以对象/模型/云编译代替装机效果。见 [FEATURE-PATHS-ALPHA5.md](FEATURE-PATHS-ALPHA5.md)。


## 当前源码行为（2026-10-25 门控调整）
按用户要求，已移除运行时宿主/build/方法编码就绪门控：`WCKEnabled` 只看总开关与功能开关；`WCKMethodMatches` 仅确认 class/selector 存在，不比对返回值、参数类型或数量；功能开关与参数可在 Hook 状态未确认时编辑；相册实验不再按微信版本拦截。缺 class/selector 或 Substrate Hook API 时仍跳过安装。未实现的功能仍是占位，不会因取消门控而自动出现。

这是用户明确要求的宽松运行模式，不等同兼容或真机验收；错误方法签名可能造成崩溃或异常行为。这里只做源码、合同/交叉编译和云回归；未经另行授权不安装设备。


- 目标：微信8.0.69 / 8.0.69.33；iOS15+；RootHide。
- 设置：插件收纳中的 WeChatKit；微信设置列表「WeChatKit 设置（备用入口）」。已删除右上 WCK，入口不依赖总开关，功能默认关闭。私有列表接口不符时不改宿主数据。
- 模块：输入栏上滑键盘、全局SVG浅深固定色（可选限制/排除）、首页底栏长按一键已读、朋友圈列表详细时间、聊天半屏相册。必须由用户开启总开关和对应子项才执行；不会自动替用户启用或清未读。
- 保护：Theos 注入过滤仍限定 `com.tencent.xin`；运行时不校验微信 build 或方法 ABI，Hook 状态仅提示；未完成功能仍无实现；不写原插件配置、不采集账号聊天、不自动清消息、不自动重启。

## 本地可执行测试

```sh
python3 tests/run_policy.py
python3 tests/test_settings_contract.py
python3 tests/test_features_contract.py
python3 tests/test_entry_contract.py
# macOS Foundation, production registry + fake manager; not UIKit/device:
python3 tests/run_entry_native.py
# macOS: actual production host gate + registry, including Default display version:
python3 tests/run_host_identity_native.py
python3 tests/test_host_identity_contract.py
python3 tests/test_svg_contract.py
# macOS: actual selection logic; production SVG with Foundation-backed UI model, not pixels:
python3 tests/run_svg_selection_native.py
python3 tests/run_svg_model_native.py
# macOS production keyboard/moments/album and unread fake-service models (not UIKit):
python3 tests/run_behavior_native.py
python3 tests/run_readall_native.py
# Apple SDK object compilation only, not link/run:
python3 tests/cross_compile.py --sdk /path/to/actual/iPhoneOS.sdk --arch arm64
python3 tests/cross_compile.py --sdk /path/to/actual/iPhoneOS.sdk --arch arm64e
```

`tests/WCKSettingsRegression.m` 需要隔离Apple/UIKit测试宿主；当前只有源码与对象编译，尚未原生执行。

## 后续获准后的 Xcode / Theos 构建

```sh
export THEOS=/path/to/roothide/theos
make package THEOS_PACKAGE_SCHEME=roothide
```

repo级云流程为 `../.github/workflows/build-wechatkit.yml`，只响应入口修复的新分支；不会自动安装或重启。正式arm64e仍需Xcode/PAC00审包；不能把Linux对象编译当可运行插件。历史 alpha1 云构建已成功，但遗漏收纳注册与入口真机验收，详见 ENTRY-FIX.md。

## 工程内容与许可边界

本目录为新写源码；不宣称重建原插件全部行为或有其源代码。未附本工程许可证或赋予任何第三方样本再分发权。`evidence/`保留在本机不进源码归档/远端，原始微信头文件与Mach-O均不随包分发。
