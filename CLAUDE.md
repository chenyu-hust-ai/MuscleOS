# MuscleOS

先读 docs/PROJECT_MEMORY.md：里面是统计口径、数据规则、界面约定和待做事项。改动前确认不破坏那些规则。

- 构建：`./build.sh`（`--native` 只编本机架构）。只用 Command Line Tools，没有 Xcode 工程。
- 测试一律用 `MUSCLEOS_DATA_DIR=<临时目录>`，不要碰 `~/Library/Application Support/MuscleOS`。
- 界面检查：把 View 用 `ImageRenderer` 渲染成 PNG 看（ScrollView 和系统控件渲染不出，会显示黄色占位）。
- 用户界面全中文；缺失值显示「—」；0 kg 是有效记录；组数缺失不能补成 0。
