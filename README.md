# VOID SIGNAL 3D

《VOID SIGNAL》的 Web 3D 版本：Vite + TypeScript + three.js。原 Godot 版（`void-signal` 分支）保持不变，本仓库是独立的新项目，玩法、数值与文本直接复用 Godot 版的数据（`src/data/` 下的 JSON 和 `strings.csv` 原样拷贝）。

竖屏无尽纵向卷轴战场 · 能量三角 / 超载 · 4 种武器 · 3 种武器协同 · 小行星带（爆炸矿石连锁、陨石）· 侦察机 / 拦截机 / 轰炸机（带护盾）· 7200m 撤离目标 · 模块化舰船编辑器（DOM 网格 + 3D 实时预览）· 中 / 英双语 · 键鼠 / 手柄 / 触屏双摇杆。

## 快速开始

```bash
npm install
npm run dev          # 开发服务器
npm run build        # tsc --noEmit && vite build -> dist/
npm run autotest     # 无头 Chromium(WebGL/SwiftShader) 自动测试，打印 PASS/FAIL
npm run shots        # 生成 docs/screenshots/ 下的截图（竖屏 540x1200 + 桌面 1280x800）
npm run models       # 用 Blender 4.2 无头脚本重新生成 public/models/*.glb
npm run fonts        # 重新子集化字体（Noto Sans SC / Orbitron，OFL）
```

URL 参数：`?autotest=1&god=1&timescale=6`（自动测试）、`quality=low|med|high`、`lang=zh|en`、`touch=on|off`、`seed=`、`goal=`、`endless`、`play`（跳过标题）。

## 操作

| 动作 | 键鼠 | 手柄 | 触屏 |
|---|---|---|---|
| 移动 | WASD / 方向键 | 左摇杆 | 左半屏浮动摇杆 |
| 瞄准 / 主武器 | 鼠标 / 左键 (J) | 右摇杆(推动即开火) / RT | 右半屏浮动摇杆（推动即开火） |
| 副武器 / 切换 | 右键 (K) / Q | LT / Y | SEC / SWAP |
| 冲刺 | Shift | A / LB | DASH |
| 超载 | 按住空格 | RB | OVL（切换） |
| 能量预设 | 1-4，Z/X/C 微调 | 十字键 | MODE（循环） |
| 暂停 / 编辑器 / 语言 | Esc / Tab / L | Start | 右上角按钮 |

## 目录

```
blender/build_models.py   Blender 无头建模脚本（全部原创几何体）-> public/models/*.glb + manifest.json
src/core/                 EventBus / GameManager / InputManager / AudioManager / SaveManager / Loc / ObjectPool / Rng
src/sim/                  纯逻辑（从 Godot 移植）：EnergyCore ShipModel Weapon Projectiles Enemy(+Director) Synergy Asteroids Player Battle
src/render/               three.js 渲染：Renderer(后处理+画质) Assets(GLB/Instancing) GameView ShipView Effects(粒子/星空/星云/护盾/引力井/拖尾)
src/ui/                   DOM 全息 HUD、菜单、触屏摇杆、舰船编辑器
src/test/Autotest.ts      浏览器内自动测试
tools/                    autotest.mjs / shots.mjs / serve.mjs / subset_fonts.py
android/                  Capacitor 6 Android 工程
docs/                     设计 / 架构 / 开发日志 / TODO / 截图
```

## Android

`npm run build && npx cap sync android && cd android && ./gradlew assembleDebug`（JDK 17，SDK 35）。调试 APK 发布在 GitHub prerelease `void-signal-3d-v0.1.0`。

## 许可

代码与模型为本项目原创。字体：Noto Sans SC、Orbitron，均为 SIL Open Font License 1.1，许可证见 `src/assets/fonts/LICENSE-*.txt`。
