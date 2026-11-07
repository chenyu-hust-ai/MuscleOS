# MuscleOS

一个原生 macOS 力量训练记录应用（SwiftUI），完全离线，数据只存在你自己的 Mac 上。
A native, offline-only strength-training log for macOS, built with SwiftUI.

## 功能

- **训练录入**：逐组下拉选择重量 / 次数 / RIR，带出上次数值，一键复制上次训练，改一组自动同步到后面的组
- **人体肌群图**：27 个肌群，正反两面；按恢复状态或本周组数着色，悬停查看恢复进度、最近记录、疼痛提醒
- **协同统计**：每个动作有固定协同系数（主练 1 / 主要协同 0.5 / 轻度参与 0.25）；「直接组数」与「含协同」分开显示
- **周报**：周一起算，组数缺失保留「—」不补 0；上周对比、训练负荷分、肌群分析（推拉平衡、肩三束、上下肢、被忽略的肌群）
- **进步曲线**：同一动作的重量或估算 1RM，疼痛记录标红
- **恢复签到**：睡眠、疲劳、疼痛部位与程度、肌肉酸痛全部点选；签到会修正人体图的恢复状态
- **数据安全**：每次保存前自动备份（保留 50 份），JSON 导出 / 导入（重复导入不会产生重复记录），最近删除可恢复
- **我的**：头像（可换）、昵称、基本信息、伤病与注意（录入相关动作时提醒）

## 系统要求

- macOS 14 Sonoma 或更新
- Apple 芯片或 Intel（`build.sh` 默认构建通用版）

## 下载使用

到 Releases 下载 `MuscleOS-*-macOS.zip`，解压后把 `MuscleOS.app` 拖到「应用程序」。

应用没有经过 Apple 公证，第一次打开会提示 Apple 无法验证。点「完成」（不要移到废纸篓），然后：

- 打开「系统设置 → 隐私与安全性」，在「安全性」里点 MuscleOS 旁边的 **仍要打开**，输入密码确认；或者
- 在终端运行 `xattr -dr com.apple.quarantine /Applications/MuscleOS.app`

只需要放行一次。

## 从源码构建

只需要 Command Line Tools，不需要完整 Xcode：

```bash
xcode-select --install   # 如果还没装
./build.sh               # 通用版，产物在 build/MuscleOS.app
./build.sh --native      # 只构建本机架构，更快
```

只装了 Command Line Tools 时，最新 SDK 可能缺少 SwiftUI 宏插件（`@State` 编译失败），`build.sh` 会自动改用 26.x SDK。

## 数据在哪里

`~/Library/Application Support/MuscleOS/workouts.json`，自动备份在同目录的 `Backups/`。
测试时可以用环境变量 `MUSCLEOS_DATA_DIR` 指向别的目录，避免碰到真实数据：

```bash
open -n --env MUSCLEOS_DATA_DIR=/tmp/muscleos-test build/MuscleOS.app
```

## 项目结构

| 文件 | 内容 |
|---|---|
| `Sources/Models.swift` | 记录、草稿、个人资料、动作库 |
| `Sources/Store.swift` | 读写、自动备份、最近删除 |
| `Sources/Muscles.swift` | 27 个肌群、旧名归位、协同系数、签到部位映射 |
| `Sources/Weekly.swift` / `Analysis.swift` | 周统计与肌群分析 |
| `Sources/Body.swift` | 人体图几何、恢复判断、详情面板 |
| `Sources/Views.swift` / `SetEditor.swift` | 主框架、训练详情、录入窗口 |
| `Sources/Recovery.swift` / `Today.swift` | 恢复签到、今日页 |
| `Sources/Importer.swift` / `DataPage.swift` | 导入导出、数据与备份页 |
| `tools/make_icon.swift` | 生成应用图标（白底、倾斜杠铃片、上升折线） |
| `docs/PROJECT_MEMORY.md` | 产品规则、设计约定、已做和待做（给后续开发和 AI 助手看） |

## 说明

规则（恢复间隔、协同系数、签到判断等）是产品设定，仅供参考，不是医学建议。

## 许可证

MIT，见 [LICENSE](LICENSE)。
