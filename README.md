# VOID SIGNAL（虚空信号）

原创像素风太空战斗 Roguelite，目标 **Godot 4.7.x**（已在 4.7.2 headless 验证，4.3 也可启动）+ GDScript。内部分辨率 480×270，整数缩放（默认窗口 1440×810）。

## 当前状态：Phase 2b（中英双语 + 竖屏无尽卷轴战场）

Phase 2b 新增：
- **中英双语**：所有 HUD/菜单/编辑器/协同/警告/浮字走 `tr()` 键（`data/i18n/strings.csv`，运行时解析成 Translation，无需导入缓存）。暂停菜单可切换 中文/English，保存在设置（存档 v4），默认按系统语言（zh* → 中文，否则英文）。
- **像素中文字体**：Fusion Pixel Font 12px 比例 简体中文（SIL OFL 1.1），无抗锯齿，作为默认主题字体。
- **竖屏**：内部 270×480，窗口 540×960 整数缩放，移动端竖屏方向。
- **无尽纵向战场**：镜头以 40px/s 自动上卷，飞到上方推进线可带动镜头加速；按区块（480px）种子生成小行星并在下方远处释放；敌人从上方与两侧刷出；星空纵向视差。
- **胜利条件**：抵达 7200m（基础速度下约 3 分钟，主动前推可更快）；`--endless` 为无尽模式。

## Phase 2（能量核心 / 模块舰船 / 4 武器 / 3 协同 / 小行星带）

Phase 2 新增：
- 动态能量核心 WEAPON/SHIELD/ENGINE（三角控件可拖拽，1-4 预设，Z/X/C 微调），实时影响伤害/射速/散热、护盾容量/回复、加速/极速/转向/冲刺冷却
- Shift 超载（140% 能量）→ 核心热量上升 → 过热随机瓦解一类模块 4 秒；HUD 警告 + 屏幕边缘像素失真（暂停菜单可开“REDUCE FLASH”改为静态边框）
- 模块化舰船（数据驱动网格：驾驶舱/核心/主推/侧推/武器挂点/护盾/装甲/散热器），连接点校验、属性推导、挂点射界、模块受击摧毁与冗余路径容错；Tab 打开调试编辑器（拖放、青色有效/红色无效预览、实时属性）
- 4 武器（JSON）：Pulse Cannon、Missile Swarm（追踪）、Gravity Bomb（引力井）、EMP Launcher（剥盾+眩晕）；敌人护盾
- 3 个协同（data/synergies.json）：GRAVITY LOCK、OVERCHARGE BREACH、ION VORTEX，触发时显示文字与特效
- 环境：小行星带（挡子弹、掉落 Scrap、爆炸矿石连锁、陨石 2 秒预警线）

Phase 1 内容：
- 惯性飞行（加速度/阻力）、鼠标/右摇杆瞄准、Space 冲刺（冷却、无敌帧）、尾焰
- Pulse Cannon（数据来自 `data/weapons/pulse_cannon.json`），对象池子弹、热量/过热
- EnemyDirector：种子随机、按 `data/waves.json` 在 3 分钟内递增波次；3 种敌人（侦察追击 / 拦截环绕 / 轰炸散射）
- 船体 + 延迟回复护盾、受击闪白、像素粒子爆炸、屏幕震动、伤害数字
- 三层视差星空；HUD（左下船体/护盾，右下武器/热量/冲刺，顶部计时/星区/击杀，受击方向指示）
- Esc 暂停菜单、3:00 胜利 / 死亡失败 + 重开；F3 性能面板
- 所有美术为代码程序化绘制，音效为程序合成方波/噪声，无第三方素材

## 操作
| 动作 | 键鼠 | 手柄 |
|---|---|---|
| 移动 | WASD | 左摇杆 |
| 瞄准 | 鼠标 | 右摇杆 |
| 主武器（Pulse + Missile） | 鼠标左键 | RT / R1 |
| 副武器（当前选中） | 鼠标右键 | LT |
| 切换副武器 | Q | Y |
| 冲刺 | Space | A |
| 超载 | Shift（按住） | LB（按住） |
| 能量预设 ASSAULT/DEFENSE/ESCAPE/BALANCED | 1 / 2 / 3 / 4 | 十字键 上/下/左/右 |
| 能量微调 武器/护盾/引擎 | Z / X / C | X / B / R3 |
| 能量三角拖拽 | 鼠标左键拖动 HUD 底部三角 | — |
| 舰船编辑器 | Tab | Back/Select |
| 语言切换 | Esc → 语言 | Start → 语言 |
| 暂停 | Esc | Start |
| 性能面板 | F3 | — |

## 运行
```bash
godot --path .                      # 正常游玩
godot --headless --path . --import  # 导入
# 自动测试：自动驾驶跑完整局，打印统计后退出
godot --headless --path . -- --autotest=32 --timescale=6 [--god] [--seed=123]
# 额外参数：--endless（无尽）、--lang=zh|en
# 输出 [AUTOTEST] CHECK ... 与 RESULT PASS/FAIL；FAIL 时退出码 1
```

文档：`GAME_DESIGN.md`（设计）、`ARCHITECTURE.md`（技术架构）、`TODO.md`（路线图与任务）、`DEVELOPMENT_LOG.md`（开发与验证日志）。

## 字体与许可
`assets/fonts/fusion-pixel/`：Fusion Pixel Font v2026.10.16（12px proportional, zh_hans, woff2），作者 TakWolf，**SIL Open Font License 1.1**（见同目录 `OFL.txt` 及 `LICENSES/` 中上游字体 Ark Pixel / Cubic 11 / Galmuri 的许可）。

## 导出注意
`strings.csv` 与字体使用 `importer="keep"`（原样导出、运行时读取）。导出预设需在“非资源文件”过滤中加入 `*.json, *.csv, *.woff2`。

## UI（复古未来像素界面）
- 风格规范见 `docs/UI_STYLE_GUIDE.md`，真实截图见 `docs/screenshots/`（title / hud_combat / overload / synergy_toast / energy_triangle / pause_zh / pause_en / builder / victory / gameover）。
- 启动进入标题画面：任意键开始，L 切换中/英。
- 重新生成截图（需要显示环境，例如 Xvfb）：
  `xvfb-run -a godot --rendering-driver opengl3 --resolution 540x960 --path . -- --shots=battle --autotest=999 --god --goal=2600 --timescale=2 --seed=3287`
  （另有 `--shots=title`、`--shots=gameover`）

## 安卓安装测试步骤
> 现状：调试 APK 已在 Linux 盒子上用 Godot 4.7.2 无头导出并通过 apksigner 校验，**尚未在真机上运行过**。

1. 拿到 `void-signal-debug.apk`（包名 `com.voidsignal.game`，arm64-v8a + armeabi-v7a，minSdk 24 / targetSdk 36，渲染器 Compatibility/OpenGL ES 3.0）。
2. 手机端允许安装未知来源应用：设置 → 安全/隐私 →“安装未知应用”，给用来打开 APK 的应用（文件管理器/浏览器）授权；或使用 adb。
3. adb 安装（推荐，便于看日志）：
   - 手机打开“开发者选项”（设置 → 关于手机 → 连点“版本号”7 次）→ 打开“USB 调试”。
   - 电脑：`adb devices` 确认设备，然后 `adb install -r void-signal-debug.apk`（`-r` 覆盖安装）。
   - 若提示签名冲突：`adb uninstall com.voidsignal.game` 后重装（调试签名为盒子上生成的 debug.keystore）。
4. 查看日志：`adb logcat -s godot`（脚本错误、[AUTOTEST]/print 输出都在这里）。
5. 触屏操作：左下半屏任意处按下=浮动移动摇杆；右侧按下=浮动瞄准摇杆，按住自动开火主武器；右侧竖排按钮：切换副武器 / 副武器(按住) / 超载(按住) / 冲刺；右上：舰船编辑器、暂停。能量三角可直接拖动，四个预设芯片可点按。暂停菜单“触屏操控”开关可开关触屏层（桌面默认隐藏，可用 `-- --touch` 强制显示）。

### 重新导出 APK（盒子环境）
- JDK 17：`/opt/dl/jdk`（Temurin 17.0.20.1）；Android SDK：`/opt/dl/sdk`（platform-tools、build-tools 35.0.1 + 36.0.0、platforms android-35/36）；导出模板 4.7.2.stable（官方 .tpz 中的 android_*）；调试密钥 `/opt/dl/debug.keystore`（androiddebugkey/android）。编辑器设置已写入 `~/.config/godot/editor_settings-4.7.tres`。
- `godot47 --headless --path . --import && godot47 --headless --path . --export-debug "Android" build/void-signal-debug.apk`
- 校验：`apksigner verify --verbose build/void-signal-debug.apk`、`aapt dump badging build/void-signal-debug.apk`
