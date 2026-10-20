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
