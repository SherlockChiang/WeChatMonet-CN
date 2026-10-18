# CN 3200 / CN13 验证记录

日期：2026-10-18（Asia/Shanghai）

## 输入与渠道

- 当前小米 `e56b56ef`：微信 8.0.79 / 3200，targetSdk 34，单一 base APK。
- APK SHA256：`f2a725bc04302ad218a563533ae79356e66b64aa711b275bc919a8d432f7e15d`。与前一天从索尼提取的 CN 包完全一致。
- Manifest 构建标签：`Android_Wechat_RELEASE_WUKONG #8301`；构建分支 `dev/2026-t9/special_1001@git`。
- 作为对照，旧 3182 的标签为 `Android_Wechat_RELEASE_GP_AppBundle`，分支为 `dev/2026-t9/for_gp@git`，属于 Play 包。小米之前的 CN12 测试不能作为 CN 3200 验证。
- 资源比对基线：CN 8.0.77 / 3160，SHA256 `18714afe662d2ca58e8e9389ad727c9ff562ed8f3711a93c904819bb753215d2`。

## 构建与部署前验证

- 六个 3200 专用 APK 通过 zipalign 与 v3 签名校验。
- 内部资源 ID、配置数据、引用 ID 与对应源包一致；XML、图片和 Manifest 字节保持一致。
- 逐包在小米上创建 idmap，与 `3200.json` 的目标资源名集合比较；均完全相等。

| RRO | 目标条目 | 部署前 idmap |
|---|---:|---|
| MonetWeChat | 228 | 集合完全一致 |
| MonetWeChatBadge | 2 | 集合完全一致 |
| MonetWeChatChatBubble | 10 | 集合完全一致 |
| MonetWeChatMultiSceneCorners | 2 | 集合完全一致 |
| MonetWeChatSolidTab | 1 | 集合完全一致 |
| MonetWeChatBlurTab | 2 | 集合完全一致 |

- 二进制资源补丁回归测试 3 项通过。
- 五个 shell 脚本通过设备 `sh -n`。
- 设备 shell 行为验证通过：3182 识别为 Play、3200 识别为 CN，两者选择图片气泡；3182 / 3200 缺失版本包拒绝回退；缺少任一已选覆盖的资源包时不会局部替换基础包；资源完整时一起同步。
- 已保存手机和本地的未压缩 CN12 备份：`/data/local/tmp/wxmonet-cn13/module-cn12-backup.tar`、`Workspace/compat-3200/module-cn12-backup.tar`。
- 已同步 CN13-dev、五个已选 3200 静态覆盖与全部六个源包，保留手机配置（纯色底栏、圆角启用），并发起重启。

## 重启后验证

- 微信安装包 SHA256 仍等于审核输入，版本仍为 CN 3200。
- 系统启动完成后，基础、红点、气泡、圆角、纯色底栏五个已选 RRO 均为 `STATE_ENABLED`。
- 五个 `/system/priv-app` 实际挂载 APK 的 SHA256 分别与对应的 `files/*-3200.apk` 完全一致。
- 系统自动生成 idmap 的目标资源名集合逐包完全一致，数量分别为 228 / 2 / 10 / 2 / 1；未发生误命中私有资源。
- 纯色底栏、圆角启用等原配置保留。
- 用户手动查看后确认“正常的”。本轮没有另做明暗模式截图或逐页视觉检查；不把旧 Play 包截图视为 CN 3200 视觉证据。

## 范围限制

- 基础包有 50 个内部或未确认资源不匹配目标，含 6 个关于页字符串。
- `color/ajh` 只有颜色序列中的单条候选，缺少明确引用证据，转为私有资源；不把它猜测为 CN 3200 的同名用途。
- 预编译 SVG、红包及转账类型、未逐页检查的页面仍受项目原有限制。
- 尚未在索尼的挂载环境验证；原来的索尼 PackageManager 注册问题属于另一个设备环境。
- 初次验证直接同步 APK；用户确认正常后要求撤回旧 Release 并发布 CN 新版，随后打包发布 CN13。
