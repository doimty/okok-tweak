# WeChatKit · independent experimental source

按用户选定功能独立编写的微信插件工程，不包含 WCPulse/WCRefine/WeX 二进制、授权逻辑、网络服务、图标或私有转储。

**alpha4 改为全局 SVG 固定浅深色，并明确总开关关闭状态，补图标刷新/关闭恢复和本页导航布局。** 用户已确认alpha3入口可打开；本轮采样时主开关为false，三个子开关为true，空名单另使旧SVG不改色。见 [GLOBAL-SVG-FIX.md](GLOBAL-SVG-FIX.md)。仍只有首批3项，另外10项及WCR随机色板/透明度/历史未实现，不声称全量照搬。

alpha3的真实主包Info.plist身份读取与精确版本/ABI限制继续保留；详见 [HOST-IDENTITY-FIX.md](HOST-IDENTITY-FIX.md)。

- 目标：微信8.0.69 / 8.0.69.33；iOS15+；RootHide。
- 设置：插件收纳中的 WeChatKit；微信设置列表「WeChatKit 设置（备用入口）」与右上 WCK 独立兜底。入口不依赖总开关，功能默认关闭。私有列表接口不符时不改宿主数据。
- 模块：输入栏上滑键盘、全局SVG浅深固定色（可选限制/排除）、首页底栏长按一键已读。必须由用户开启总开关和对应子项才执行；不会自动替用户启用或清未读。
- 保护：精确bundle+build+ABI检查、未完成禁用、不写原插件配置、不采集账号聊天、不自动清消息、不自动重启。

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
