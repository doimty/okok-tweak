# Hook 安装器加固候选

基线：`8ea157c5fee6d0a3b331400a36e4cbbbec2f8a9b`。
范围：生产安装器、对应回归/变异测试、现有云端构建流程。没有安装 deb，没有重启或操作目标设备，没有清理微信未读/消息数据。

## 先校正两条旧审计结论

1. 原代码先写入 `fallback`，再让 Hook 后端写 `original`；后端能够将它覆盖成 NULL，所以“那处判空永远为假”不成立。真正的问题是：**后端没有填写输出时，预填值仍非空，无法用它证明安装成功**；后端空写回还可能瞬间影响回调使用的 original。
2. `MSHookMessageEx` 返回 void，并给出用于继承/多插件调用链的 next-implementation stub。简单地用 `class_replaceMethod` 回写安装前 snapshot 不是通用回滚，会覆盖其他插件或绕过未来的父类 Hook。也不能把 Method IMP 未等于 replacement 一律解释为“没有安装”：它可能是另一层 Hook 或后端 trampoline。

依据：[Substrate API 合同](<https://www.cydiasubstrate.com/api/c/MSHookMessageEx/>)；[固定提交的 ElleKit 实现](<https://github.com/tealbathingsuit/ellekit/blob/1017a0d09606ea49ba8bc4d6cccc530d372e640e/ellekit/Languages/Objective-C.swift#L9-L30>)。

另一个证据校正：基线分支已有 [成功的手动 CI run 40188871738](<https://github.com/doimty/okok-tweak/actions/runs/40188871738>)，不能从 push 分支过滤器推断“从未云端构建”。这仍不代表目标设备效果验证。

## 本次实现

### 类型检查，不是版本白名单

[生产安装器](<src/WCKRuntime.m>)继续使用 `class_getInstanceMethod`，传入元类时检查类方法。使用 `method_getNumberOfArguments` 与分别复制的返回/参数类型，避免比较包含字节偏移的整段 encoding。

复用 [现有类型比较策略](<src/WCKPolicy.c>)：允许 actual 的限定符、带类注释的对象类型；不把 block `@?` 当普通对象，不把 `q/Q`、`d/f`、不同结构体字段等同。类型字符串始终释放。按 `actualCount - 2` 比较显式参数数，避免 `count + 2` 溢出。

没有恢复微信版本/build 白名单；`WCKEnabled` 仍只读取总开关和模块开关。目标的方法存在/编码匹配也不能证明私有参数的业务语义正确。

### 原实现与后端输出分离

- 调用 Hook 前，回调实际使用的 original 存储预填为非空、非自身的安装前 IMP，防止安装过程中回调调用 NULL。
- 后端写入独立、由进程内注册记录持有的零初始化输出存储；空输出、未写输出与递归输出都不能冒充成功。
- 有效后端 original 原样保留，可能是 trampoline，而不是强制替换为安装前 IMP。
- arm64e 指针认证只在比较时剥离签名；保存与调用时保留原来的可调用指针，不调用剥离后的地址。

### 去重与未知结果隔离

注册表按 Class/SEL 区分（元类本身与实例类不同），记录 replacement、后端原链、安装中/确认/未知状态；调用外部后端前预留记录，防止重入或并发重复 Hook。后端调用发生在注册表锁之外，允许其同步等待另一线程查询同一目标；完成后再加锁定稿。捕获 fallback 时重新检查同一个新 Method，缩小查找期间发生目标变化的窗口，但本锁无法阻止其他 Hook 引擎并发修改。

每个实际回调使用的 output 存储必须独立对应一个 target/replacement；不能把另一个目标正在使用的 original 存储借给当前安装请求。注册表与 output 只属于本进程，不声称在调用方违反该约定时仍保证调用链正确。

- 同一目标、相同 replacement、已确认：幂等 YES；返回保存的后端原链，允许复制到新的 output 存储，不调用后端第二次。
- 同一目标、不同 replacement：跳过冲突，不改现有 Hook 或任何 output。
- 尚在安装中：拒绝重入；外层调用结束后决定最终状态。
- 已调用后端但结果未知：保留该记录，后续同 owner 返回 NO，不重复调用后端。
- 类/selector/API 缺失等调用后端之前的失败不占安装记录，后续外部调度仍可再次尝试。

已确认后若第三方再加一层 Hook，同 owner 的幂等查询不会用新顶层 IMP 替换原链，也不会强行重新插入我们自己的 replacement。

### 核验与诊断边界

只有“有有效后端 original + 新查找的 Method IMP 正向匹配 replacement”才确认直接方法替换并返回 YES。Hook API没有通用事务或查询接口，因此其余已调用后端的结果标为 `attempted_unverified.*`，不是“已安全撤销”。

[运行时状态表](<src/WCKRuntime.h>)增加每目标键：

```text
hook.instance/<ClassName>/<selector>
hook.class/<ClassName>/<selector>
```

| 值 | 含义 |
|---|---|
| `installed` | 直接替换和有效原链已核验；并非功能真机验收 |
| `target_missing` | 类或 selector 不存在，未调用后端 |
| `hook_api_missing` | 没找到 Hook API，未调用后端 |
| `install_failed.invalid_argument` | replacement/output 为空，未调用后端 |
| `install_failed.signature_mismatch` | 类型或参数数量不符，未调用后端 |
| `install_failed.original_imp_missing` | 安装前 IMP 为空，未调用后端 |
| `conflict_skipped` | 不同 replacement 已登记，或未知来源已装入同一 replacement |
| `conflict_skipped.install_in_progress` | 外层安装未结束，跳过重入 |
| `attempted_unverified.original_imp_null` | 后端没提供非空原链，保留 fallback，隔离该目标 |
| `attempted_unverified.original_imp_recursive` | 后端把 replacement 当 original，保留 fallback，隔离该目标 |
| `attempted_unverified.hook_exception` | 后端抛出 ObjC 异常，结果未知，隔离该目标 |
| `attempted_unverified.postcondition_failed` | 顶层读回不能确认直接替换，原链保留，隔离该目标 |

返回 NO **不等于** replacement 不会执行：后端可能已经发布它。fallback 只能提供紧急的既有调用，不保证继承与其他插件链等价，也不能验证任意地址是否真可调用。该最小补丁不是完整事务回滚、安全模式或任意 Hook 后端的崩溃防护。

## 验证方式

[新增 Foundation 夹具](<tests/WCKRuntimeInstallerRegression.m>)通过受控假后端运行实际生产安装器。仅编译生产运行时这一 translation unit 时重命名 `dlsym`，不替换 Foundation 全进程的动态链接行为，不给生产包导出测试开关或 reset 接口。

```bash
python3 tests/run_runtime_installer_native.py
```

[测试 runner](<tests/run_runtime_installer_native.py>)在 macOS 原生执行；非 macOS 返回 77（SKIP，不计为通过）。每个场景独立进程隔离注册表。定向变异体必须成功编译，并由指定场景明确失败；编译失败、超时或无关崩溃不计为“杀死变异体”。证据输出包含源 SHA 与边界标签：

```text
Foundation model / not real WeChat / not device validation
```

[现有 CI](<../.github/workflows/build-wechatkit.yml>)在同一候选 commit 上跑源码合同、生产安装器模型/变异、既有功能模型，并由 Apple SDK 编译 arm64/arm64e、链接/签名/打包，上传新安装器测试 JSON 与 deb。

## 不在本轮完成范围

- 目标微信进程中的注入链、真实 selector 参数语义、页面效果、稳定性。
- 模块晚加载调度、键盘 A/B 选择、已读代理方法语义的全面加固。
- 圆角全局 UIView Hook/BFS 的范围收敛、SVG 的设备 UI 效果。
- 完整 kill switch、启动崩溃循环检测、安全模式、进程外设置控制面。
- rootless/rootful 的新包矩阵；本次沿用已存在的 RootHide 候选流程。
