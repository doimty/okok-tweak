# WeChatKit · independent experimental source

按用户选定功能独立编写的微信插件工程，不包含 WCPulse/WCRefine/WeX 二进制、授权逻辑、网络服务、图标或私有转储。

**当前只有首批3项实验源码，未打包安装，未真机验收。** 其余10项明确未实现。详见 [STATUS.md](STATUS.md) / [FEATURES.md](FEATURES.md)。

- 目标：微信8.0.69 / 8.0.69.33；iOS15+；RootHide。
- 设置：微信设置页右上角 WCK（实现候选，待真机验收）。总开关与各功能默认关闭。
- 模块：输入栏上滑键盘、SVG精确名单改色、首页底栏长按一键已读。
- 保护：精确bundle+build+ABI检查、未完成禁用、不写原插件配置、不采集账号聊天、不自动清消息、不自动重启。

## 本地可执行测试

```sh
python3 tests/run_policy.py
python3 tests/test_settings_contract.py
python3 tests/test_features_contract.py
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

手动 GitHub Actions 流程已备于 `.github/workflows/build.yml`，本轮没有推送或触发。正式arm64e需Xcode/PAC00验证；不能把Linux clang对象文件当可用插件。

## 工程内容与许可边界

本目录为新写源码；不宣称重建原插件全部行为或有其源代码。未附本工程许可证或赋予任何第三方样本再分发权。`evidence/`保留在本机不进源码归档/远端，原始微信头文件与Mach-O均不随包分发。
