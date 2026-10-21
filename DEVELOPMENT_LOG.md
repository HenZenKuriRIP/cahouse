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

## 2026-10-20 Phase 1 修复：Godot 4.7 解析错误（UTC+8）
**问题**：用户在 macOS + Godot 4.7.2 上 `godot --path .` 直接运行，battle.gd 报 `Could not find type "Player"/"EnemyDirector"/"Enemy"/"Projectile"`、`Identifier "Pixel" not declared`。
**根因**：依赖全局 `class_name`，而未经编辑器导入时 `.godot/global_script_class_cache.cfg` 缺失/过期。
**复现**：box 上下载官方 Godot **v4.7.2.stable.official.ed1daf0bf**（GitHub release linux x86_64），对旧提交删除 `.godot` 后启动，得到完全相同的 4 条 Parse Error —— 根因确认。
**修复**：所有脚本删除 `class_name`，改用 `const PixelLib/PlayerScript/EnemyScript/ProjectileScript/WeaponScript/EnemyDirectorScript = preload(...)`；`.godot/` 在 `.gitignore` 中且未入库。另修复退出时 AudioStreamPlayback 泄漏警告（结束前暂停树并 stop_all）。
**验证（4.7.2，删除 .godot，无预先 --import）**：`--quit-after 600` 零错误；autotest god → `run WON at 180.0s`；无 god → `run LOST`。

## 2026-10-20 Phase 2（UTC+8）
目标引擎 Godot 4.7.x（`config/features` = 4.7）。所有跨脚本引用均为 preload 常量。

### 遇到的问题
- 4.7 对 `:=` 推断更严格：从无类型对象（RefCounted 变量）调用的返回值不能推断类型（5 处）→ 改为显式类型。
- 默认舰船初版能量不足（核心供能 12 < 消耗 18）→ 核心供能调为 24（剩余 +6）。
- 容错测试初版选错受击模块（打击方向得分逻辑选中最外侧挂点）→ 拆成“受击摧毁”与“冗余路径”两个检查。
- 爆炸矿石连锁在随机场中不一定自然发生 → autotest 增加固定夹具（远离玩家的 3 块相邻矿石，点燃其一）。
- headless 退出时仍有音频 playback 泄漏 → 结束时先暂停树再停音，等待 0.3s 后退出，警告消失。

### 真实验证结果（Godot v4.7.2.stable.official.ed1daf0bf，headless，每次运行前 `rm -rf .godot`）
1. `--quit-after 600`：仅输出引擎横幅与 `run start`，零 SCRIPT ERROR/WARNING。（附带：Godot 4.3 下同样零错误启动。）
2. `-- --autotest=32 --timescale=6 --god`（seed 3287）：`run WON at 180.0s kills=346`，`RESULT PASS (30/30 checks passed)`，退出码 0，无警告。
   - weapons_fired: pulse 791 / missile 186 / gravity 28 / emp 26
   - synergies: gravity_missile 170 / emp_crit 30 / ion_vortex 19
   - energy: presets 6, nudges 3, overload 3.0s, overheats 1（禁用 shield_gen）
   - asteroid_field: destroyed 51, ore_explosions 7, ore_chain 2, scrap 72, meteors 13, shots_blocked 284
   - 预设乘数：ASSAULT dmg 1.45 rate 1.53；DEFENSE shield_cap 1.45 regen 1.70；ESCAPE accel 1.53 speed 1.40；BALANCED 全 1.00
   - 性能（headless）：FPS 144，process 4.2ms，内存 29.4MB，节点 339，活跃子弹 177（池创建 220）
3. 无 god，seed 3287 / 11 / 22：分别在 83.5s / 90.2s / 111.4s `run LOST`，均 `RESULT PASS (30/30)`；日志出现 `module destroyed: radiator at t=78.5`（模块被打掉路径生效）。
   - 注意：非 god 短局中 emp_crit 只触发 1–3 次，早期一次运行（帧时间不同）为 0 次导致 FAIL —— 该检查在短局中**存在偶发失败**（帧时间非固定步长导致不完全确定）。

### 未验证
- 无显示器：三角控件拖拽、编辑器鼠标拖放、边缘失真视觉效果、手柄输入均**只经代码路径/API 测试，未人工操作**。
- Web 导出未做。

## 2026-10-21 Phase 2b：双语 + 竖屏无尽战场（UTC+8）
### 决策
- **本地化不走 CSV 导入**：Godot 的 CSV 翻译导入依赖 `.godot` 缓存，删除缓存直接运行会失效；改为 `Loc` autoload 运行时解析 CSV 生成 `Translation`。`strings.csv.import` 设为 `importer="keep"`，避免编辑器把它转成 .translation 并保证原样导出。
- **字体**：Fusion Pixel Font（TakWolf）v2026.10.16，12px proportional zh_hans（woff2，约 680KB），**SIL OFL 1.1**，许可文件随附。Zpix 许可非 OFL（个人免费/商用需授权），故未选用。以 FontFile 字节加载、关闭抗锯齿/hinting/子像素，12px 为原生像素尺寸。
- **胜利条件**：改为抵达 7200m（= 40px/s × 180s），保留 3 分钟节奏，同时奖励前压。
- **滚动模型**：初版玩家速度为世界系，前推几乎无效（终端速度 ~68px/s，扣除 40px/s 卷轴后余量太小，autotest `scroll.push_ahead` FAIL）；改为屏幕系（卷轴带着玩家走），前推生效。

### 真实验证（Godot v4.7.2.stable.official.ed1daf0bf，headless，每次 `rm -rf .godot`）
1. `--quit-after 600`：仅横幅 + `run start seed=... goal=7200m endless=false lang=en`，零错误/警告。
2. `-- --autotest=32 --timescale=6 --god`：`run WON at 177.3s distance=7200m kills=356`，`RESULT PASS (40/40)`。
   - i18n：`en HULL/RESUME`、`zh 船体/继续`，`used=100 csv=100 missing=[]`，字体含“信”字形。
   - chunks generated=17 freed=13 active=4；nodes max=318；distance 7200 ≥ 6949；push_time 33.2s 使距离超出纯基础值（7091）。
3. `-- --autotest=60 --timescale=8 --god --endless --lang=zh`：480s 游戏时间，distance 19660m，chunks generated=43 freed=39 active=4；节点数在 ~200s 敌人达到上限 60 后稳定于 596–619，`RESULT PASS (40/40)`。
4. 非无敌：seed 11 → LOST 87.6s，PASS 40/40；seed 22 → LOST 90.2s，PASS 40/40（emp_crit=1）；**seed 3287 → LOST 79.4s，FAIL 39/40（synergy.emp_crit=0）**。该检查在非无敌短局中仍不稳定。

### 未验证
- 无显示器：竖屏 HUD/编辑器/菜单的实际视觉、中文字体在 2× 缩放下的清晰度、鼠标拖放、语言切换按钮点击均**未人工目视**（语言切换经 API 测试）。

## 2026-10-21 UI/UX 全面重做（UTC+8）
- 新增 `docs/UI_STYLE_GUIDE.md`（色板/网格/字号/9-slice 切角面板/图标/按钮状态/动效/HUD 层级/无障碍）。
- 新 UI 套件 `scripts/ui/`：ui_kit（绘制原语、21 个 7×7 像素图标、分段条、环形冷却、切角面板）、ui_theme（程序生成 9-slice StyleBoxTexture + Theme）、pixel_button（图标按钮/开关/手柄焦点支架）、holo_overlay（扫描线+暗角+闪烁 shader，减少闪烁时关闭闪烁）、shot_director（截图导演）。
- 重做：HUD、能量三角、暂停菜单、舰船编辑器、胜利/失败结算（数值滚动+评级）、浮动文字；新增标题画面 `scenes/title.tscn`（现为主场景；autotest 直接跳入战斗）。
- 截图：Godot 4.7.2 + Xvfb + opengl3(llvmpipe) 真机渲染，`--shots=title|battle|gameover`，输出 540×960（2× 最近邻）到 `docs/screenshots/`。做了 3 轮检查修正：
  1. 发现 CanvasLayer 阻断根窗口 Theme 传递 → 按钮使用默认样式/16px 字体、溢出面板；改为在菜单节点上直接设置 `Loc.ui_theme`。
  2. 协同提示卡过宽且位于屏幕中部 → 按文字宽度自适应、移到顶栏下；能量三角底板加深加边；编辑器卡片文字压边 → 网格缩至 18px、卡片 26px 高并整体下移。
  3. 面板展开动画首帧切角多边形退化报 "triangulation failed" → 小尺寸时退化为矩形；结算距离单位本地化（米/m）；"武"顶点标签与预设名重叠 → 移到右侧。
- 测试（真实结果）：`.godot` 删除后 headless 启动无报错；god autotest seed 3287 PASS 40/40，0 error/warning；非 god `--lang=en` seed 3287 本次也 PASS 40/40（此前已知 emp_crit 检查在非 god 下偶发失败，仍视为不稳定）。截图运行中仅有 Xvfb 环境下的 ALSA 无音频设备、vsync 提示两条环境错误。

## 2026-10-21 安卓：触屏操控 + 调试 APK 导出（UTC+8）
- 新增 `scripts/ui/touch_controls.gd`：浮动双摇杆（左移动、右瞄准+按住开火）、冲刺/超载(按住)/副武器(按住)/切换/编辑器/暂停按钮，多指同时操作；能量三角：手指 0 走 Godot 的触摸→鼠标模拟，其余手指由触屏层转发（拖动与预设芯片点按）。自动启用条件：`is_touchscreen_available()` 或 Android/iOS；存档项 `touch_controls`（auto/on/off），暂停菜单开关；`-- --touch` 强制开启。读取 `get_display_safe_area()` 换算到逻辑坐标作为边距。布局避开顶栏(0–40)与底部 HUD 卡片(404+)。
- 标题页触屏显示“轻触开始”，点按语言行切换语言。启用 `input_devices/pointing/emulate_mouse_from_touch`，菜单与编辑器拖放通过模拟鼠标工作。
- autotest 新增 7 项触屏检查（直接调用 `TouchControls.handle()` 注入 InputEventScreenTouch/Drag，两指同时按住双摇杆 + 第三指按钮 + 第三/四指能量三角）：47/47 通过。
- Xvfb 截图 `docs/screenshots/touch_hud.png` 走真实输入路径：`Input.parse_input_event` 以窗口像素坐标注入 3 个手指，日志确认换算到逻辑坐标正确（move=(0.545,-0.727)，aim 激活，超载按住）。
- 导出：Temurin JDK 17、Android cmdline-tools（platform-tools、build-tools 35.0.1/36.0.0、android-35/36）、官方 4.7.2 导出模板；开启 ETC2/ASTC 导入（导出强制要求）；`export_presets.cfg` Android 预设；自适应图标 432px 前景/背景 + 192px 主图标。APK 58,384,529 字节，apksigner v2/v3 校验通过。
- 未在真机运行；安全区仅作用于触屏层（HUD 顶栏本身未下移）。
