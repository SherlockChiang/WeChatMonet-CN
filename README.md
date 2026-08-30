# WeChat Monet CN · 微信莫奈取色（大陆版适配）

基于上游 WeChat Monet Pro 26S4（作者：枯れ木, 1e93d, HSSkyBoy，MT 论坛发布）的微信大陆版 KernelSU/Magisk 模块适配。通过 Android Runtime Resource Overlay（RRO）为微信提供 Material You / Monet 动态取色，**不修改微信 DEX，无 Xposed 依赖**。

- 当前版本：**26S4-CN6**（versionCode 260819）
- 支持微信：**大陆版 8.0.76 / 8.0.77**（versionCode `3140` / `3141` / `3160`，均已核对资源表）
- 系统要求：Android 14+，KernelSU 或 Magisk
- 大陆版聊天气泡样式暂不可移植（见[已知限制](#已知限制)）

## 安装

1. 在 KernelSU / Magisk 管理器中刷入 [最新 Release 的 zip](https://github.com/SherlockChiang/WeChatMonet-CN/releases/latest)。
2. 安装向导（音量键操作）中**建议选择「清除并禁用微信热更新缓存」**——大陆版热更新会让覆盖失效。
3. 重启系统（静态 RRO 需要开机扫描后生效），打开微信确认取色。

## 在管理器中更新

`module.prop` 已内置 `updateJson`，KernelSU / Magisk 管理器会在模块页面提示新版本并可直接更新：

- 更新清单：[update.json](update.json)
- 更新日志：[CHANGELOG.md](CHANGELOG.md)

也可订阅本仓库的 Release 通知（Watch → Custom → Releases）。

## 功能与兼容性

| 功能 | 大陆版 8.0.76 / 8.0.77 | 说明 |
|---|---|---|
| Monet 动态取色主体（234 色，日/夜） | ✅ | 顶栏 / 输入栏 / 开关 / 对话框 / 按钮等框架色，保留 `@android:color/system_*` 引用，跟随壁纸 |
| 纯色底栏（SolidTab） | ✅ | |
| 模糊底栏（BlurTab，预签名 RRO） | ✅ | `color/df` 与主底栏 `color/bb` 直接引用系统 Monet 亮/暗表面，重启后仍可注册 |
| 聊天气泡基础换肤 | ✅ 部分 | `c2c_*` 消息节点背景等入口随基础包生效 |
| 多场景圆角（输入栏 / 支付键盘） | ✅ | 消息引用表面色暂缺 |
| 关于页文案注入 | ✅ | 已适配为大陆版信息 |
| 红点与红色强调槽位（预签名 RRO） | ✅ 部分 | `color/ac`、`Red_100` 引用系统 Monet 主色，覆盖使用这两个槽位的资源型红点和少量共用红色控件；预编译 SVG 红点及使用其他槽位的底栏选中项仍保留微信原色 |
| 聊天气泡样式（现代圆角 / Pro / 经典） | ❌ | 大陆版为 9-patch 图片气泡架构，Play 的 shape 气泡资源不存在 |
| 红包 / 转账 / 链接气泡变色 | ❌ | 蒙版资源在大陆版无对应，保持微信原色 |
| 主文字色取色 | ❌（有意为之） | 文字槽位与 Play 语义不同，强行覆盖会导致文字染色；文字保持微信原生黑/白 |
| 桌面主题图标（Themed Icon） | ❌ | 大陆版无 `icon_fg` / `icon_themed` 资源 |

### 版本核对记录

| 微信版本 | versionCode | 核对方式 | 结论 |
|---|---|---|---|
| 8.0.76 | 3140 | 真机适配 + lookup 全量验证 | ✅ 基准版本 |
| 8.0.76 热修 | 3141 | 与 3140 对比：2160 颜色值、13843 资源文件逐字节零差异 | ✅ 无需改动 |
| 8.0.77 | 3160 | 资源名洗牌（删 480/增 1172），本模块条目零丢失；逐值 diff 仅 10 处夜间深灰微调 | ✅ 无需改动 |

## 常用命令

```bash
# 查看 overlay 状态
adb shell cmd overlay list | grep monet

# 查看实际映射
adb shell cmd overlay dump monet.com.tencent.mm

# 验证某个槽位当前取值（如主文字色）
adb shell cmd overlay lookup com.tencent.mm com.tencent.mm:color/BW_0_Alpha_0_9

# 回滚：停用模块，或执行
adb shell cmd overlay disable --user 0 monet.com.tencent.mm monet.multiscenecorners.com.tencent.mm monet.solidtab.com.tencent.mm monet.blurtab.com.tencent.mm monet.badge.com.tencent.mm monet.bubblepro.com.tencent.mm monet.classicbubble.com.tencent.mm
```

适配工作区根目录的 `rerun_pipeline.sh` 会先生成并校验 patched APK，再签名（脚本不随模块 ZIP 发布）；签名器若找不到 `zipalign`，请传入 `--zipalign PATH`。只有确认可以接受未对齐 APK 时才使用 `--skip-zipalign`，流水线不会自动静默降级。

## 工作原理

模块把若干静态 RRO overlay APK 放入 `system/priv-app`（KernelSU/Magisk 挂载），开机由 `idmap2` 按「资源类型 + 名字」映射到 `com.tencent.mm`。因此适配的本质是**资源名映射**：微信每个版本会重新洗牌混淆资源名（`a71`、`bb` 这类），本项目用 Play 8.0.72 与大陆版双包比对（文件字节哈希 / 颜色值对 / 锚点引用图投影）生成映射表后重建 overlay。微信大版本更新后需要重新映射（历史版本对照见 CHANGELOG）。

## 已知限制

- 大陆版聊天气泡是图片（9-patch）架构，气泡样式与红包/转账/链接气泡变色不可移植，除非腾讯上线与 Play 一致的 shape 气泡资源。
- 约 28 个颜色为 `?attr` 主题属性引用，无法从 shell 取值，保持微信原色。
- 文字类槽位不取色（避免文字染色），整体是「背景彩、文字不彩」的半 Monet 观感。
- 微信 8.0.77 默认启用预编译 SVG（`SVGBuildConfig.WxSVGCode=true`）。这类红点由 `com.tencent.mm.boot.svg.code.drawable.*` 直接绘制并含硬编码颜色，RRO 无法覆盖；本模块通过 `color/ac` 与 `Red_100` 稳定覆盖资源型红点及少量共用红色控件。使用其他颜色槽位的底栏选中项不会因此变色。全量动态红点需要修改微信 DEX 或使用运行时 Hook，本模块不做这两类改动。
- 本模块仅针对上述 versionCode 验证；微信更新到未适配版本后，开机会自动停用旧覆盖，避免资源名洗牌造成错误取色，请等待新版本发布。

## 致谢与声明

- 原模块 WeChat Monet Pro（26S4）由 **枯れ木、1e93d、HSSkyBoy** 开发，本仓库仅做大陆版资源名重映射与兼容性维护，原作者版权保留。
- `files/aapt2` 来自 Android Open Source Project（Apache-2.0）。
- 本项目与腾讯微信无关，仅供学习研究，请于下载后 24 小时内自行斟酌保留必要性。
