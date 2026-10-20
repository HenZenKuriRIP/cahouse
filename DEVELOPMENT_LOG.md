# 开发日志

## 2026-10-20 Phase 1（UTC+8）
**环境**：box（Linux），Godot **v4.3.stable.official.77dcf97d8**（官方 GitHub release linux x86_64），headless 运行。

### 实现
见 TODO.md Phase 1 清单（全部完成）。美术为 `_draw()` 程序化像素掩码绘制；图标由 Python/PIL 生成；音效为运行时合成的 8-bit 方波/噪声。

### 遇到的问题
- `const MASK := PackedStringArray([...])` 在 4.3 报 "isn't a constant expression" → 改为 `var`。修复后导入零脚本错误。

### 真实验证结果
1. `godot --headless --path . --import`：无 SCRIPT ERROR / ERROR。
2. `-- --autotest=40 --timescale=6 --god`（seed 3287）：跑满 180s，输出
   `run WON at 180.0s kills=164`，`spawned=223`，峰值敌人 60（上限），活跃子弹 ~164、池共创建 194 个节点；headless 下 FPS 约 145、process 5.4ms、内存 19.7MB、节点 291；Draw Calls 显示 0（headless 无渲染，属正常）。
3. `-- --autotest=40 --timescale=6`（无敌关闭）：自动驾驶在 94.5s 被击毁，`run LOST at 94.5s kills=95`——失败流程正常。
4. 普通启动 `--quit-after 600`：无错误。
5. 种子复现：`--seed=42` 两次运行刷怪数一致（45/45），击杀数 41/42 有 ±1 差异——原因是可变帧 delta（非固定步长），刷怪序列本身确定。
6. 退出时有 `WARNING: ObjectDB instances leaked at exit`（autotest 中直接 quit 时出现，非错误，待查）。

### 未验证 / 未做
- 无显示器，**未进行人工手感、视觉、HUD 布局、鼠标/手柄实际输入测试**。
- 暂停菜单/重开按钮逻辑未在 headless 中自动点击测试（代码路径存在）。
- **Web 导出未做**（导出模板约 1GB，跳过）。
