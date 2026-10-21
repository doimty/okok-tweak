# WeChatKit alpha1 · 云编译试验

## 本次授权

用户于2026-10-21要求「初版编译试试」，承接主会话说明的Xcode云构建。只在已有 doimty/okok-tweak 仓库的新分支提交首批自研源码与专用工作流，编译/打包/下载审包；不改默认分支、不创建Release/PR、不安装、不重启或清用户未读。

## 构建来源

独立工作树 `okok-tweak-wechatkit-alpha1`，基于远端main 9c0e147；新分支 `feat/wechatkit-alpha1-build-20261021`。已有 `okok-tweak` 工作树预存三处修改保持原样。

只从已交付的 `wechat-kit-alpha1-source.zip` 提取经SHA清单验证的28文件。源包SHA256 `5814eb1303ea15d4626065933ceb3102584d2fa7bceca46fbb711b22fd3180b7`。不上传evidence、微信头文件、原dylib或用户偏好。将独立工作流模板移到repo根 `.github/workflows/build-wechatkit.yml`，按子项目路径执行。

## 成功标准与独立失败信号

1. Actions真实执行C策略44断言、3个有效mutants、设置7组/功能9组源码合同。
2. Xcode工具链实际编译9生产源文件、链接arm64与arm64e dylib、签名并打RootHide deb。
3. 解包核实包ID/版本/架构/依赖、Filter仅com.tencent.xin、无脚本自动重启、可加载依赖、最小iOS15、arm64e PAC00、签名区和SHA256。
4. ABI/版本门控与功能默认全关不因构建被绕过。
5. 只有Actions success但无正确deb、错误架构/滤器/依赖、编译没包含生产文件均失败。
6. 任何链接/打包成功不等于微信功能已在真机生效，不执行用户微信消息修改以充当验证。

验证分层：本机预检 → 云端宿主/编译/链接/打包 → 下载静态审包。真机功能测试仍不在授权内。
