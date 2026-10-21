# TODO / 路线图

## Phase 1 任务清单（核心战斗原型）
- [x] 项目配置：480×270、canvas_items、整数缩放、1440×810、输入映射（键鼠+手柄）
- [x] Autoload：EventBus / GameManager / InputManager / AudioManager / SaveManager / ObjectPool
- [x] 玩家：加速度/惯性/阻力、鼠标与右摇杆瞄准、冲刺+冷却+无敌帧、尾焰
- [x] Pulse Cannon（JSON 数据）+ 池化子弹 + 热量/过热
- [x] EnemyDirector：种子 RNG、3 分钟波次（JSON）
- [x] 敌人 3 种：scout 追击 / interceptor 环绕射击 / bomber 散射（数据驱动）
- [x] 伤害、受击闪白、死亡、爆炸粒子、屏幕震动、伤害数字
- [x] 船体 + 延迟回复护盾
- [x] 视差星空
- [x] HUD：左下船体/护盾、右下武器/热量/冲刺、顶部计时/星区/击杀、受击方向指示
- [x] 暂停菜单、3:00 胜利、失败、重开
- [x] F3 性能面板
- [x] 程序化像素美术与音效
- [x] headless 自动测试（--autotest）

## Phase 1 验收标准与测试方法
| # | 标准 | 测试方法 |
|---|---|---|
| 1 | 导入与启动无脚本错误 | `godot --headless --path . --import`，输出无 `SCRIPT ERROR` |
| 2 | 完整一局可跑到 3:00 并判定胜利 | `-- --autotest=40 --timescale=6 --god`，输出 `run WON at 180.0s` |
| 3 | 玩家可死亡并判定失败 | `-- --autotest=40 --timescale=6`（无 god），输出 `run LOST` 或 WON |
| 4 | 子弹对象池复用 | autotest 日志中 `pool_created` 远小于累计发射数 |
| 5 | 种子可复现 | 同 `--seed=N` 两次运行 spawned/kills 一致 |
| 6 | 60 FPS（目标机）且敌人 60 上限 | F3 面板 / autotest 日志 fps |
| 7 | 操作手感：惯性、冲刺、瞄准、暂停、重开 | 人工游玩检查（需有显示器） |
| 8 | HUD 元素位置正确、受击方向指示 | 人工目视 |

## Phase 2 任务清单
- [x] 移除全局 class_name，统一 preload 常量引用（Godot 4.7 无缓存启动修复）
- [x] EnergyCore：三系统份额、预设 1-4、Z/X/C 微调、手柄十字键/按键、三角 HUD 可拖拽
- [x] 实时效果：伤害/射速/散热、护盾容量/回复、加速/极速/转向/冲刺冷却
- [x] 超载（Shift/LB）、核心热量、过热禁用模块、警告文字、边缘像素失真、REDUCE FLASH 开关（存档 v3）
- [x] 数据驱动模块 + 默认舰船；连接点校验（核心/驾驶舱/推力/能量/连通/尾焰）
- [x] 由模块推导质量/速度/转向/护盾/能量/散热/船体；挂点射界
- [x] 模块受击摧毁、核心/驾驶舱保护、冗余路径容错、HUD 模块小地图、由模块绘制舰船
- [x] Tab 调试编辑器：拖放、移动、右键删除、青/红预览、实时属性与错误、APPLY/RESET/CLOSE
- [x] 4 武器 JSON + 右键副武器 + Q 切换；敌人护盾
- [x] 3 协同（数据驱动）+ 触发文字/特效/横幅
- [x] 小行星带：挡弹、Scrap、爆炸矿石连锁、陨石预警
- [x] autotest 覆盖以上全部，30 项检查

## Phase 2 验收标准与测试方法
| # | 标准 | 测试方法 |
|---|---|---|
| 1 | 删除 `.godot` 后直接启动零解析错误 | `rm -rf .godot && godot --headless --path . --quit-after 600` 无 `SCRIPT ERROR` |
| 2 | 全部自动检查通过 | `-- --autotest=32 --timescale=6 --god` 输出 `RESULT PASS (30/30)`，退出码 0 |
| 3 | 4 个预设产生不同乘数 | 日志 `[AUTOTEST] PRESET ...` 四行数值不同 |
| 4 | 超载→过热→禁用模块 | `CHECK energy.overheat_disables_module OK disabled=...` |
| 5 | 4 武器均开火 | `COUNTERS weapons_fired` 四项 >0 |
| 6 | 3 协同均触发 | `COUNTERS synergies` 三项 >0 |
| 7 | 舰船校验：无核心/断连/尾焰遮挡/无推力/能量不足判为无效；容错；核心保护 | `CHECK ship.*` 全 OK |
| 8 | 编辑器拖放预览与应用 | `CHECK builder.*` 全 OK；人工：Tab 打开，拖动模块观察青/红 |
| 9 | 小行星挡弹/摧毁/连锁/陨石 | `CHECK asteroids.*` 全 OK |
| 10 | 非无敌模式可死亡、模块可被打掉 | 无 `--god` 运行：`run LOST`，日志 `module destroyed: ...` |
| 11 | 手感/可读性/趣味 | 人工试玩，填写 GAME_DESIGN.md §18 清单 |

## Phase 2b 任务清单
- [x] CSV → 运行时 Translation（无缓存可用），全部 UI 文本 tr() 化
- [x] 暂停菜单语言切换，设置 v4 迁移，默认跟随系统语言
- [x] Fusion Pixel 12px 简中字体（OFL）+ 许可文件，设为默认主题字体
- [x] 竖屏 270×480 / 540×960，handheld orientation=portrait
- [x] 自动上卷 + 前推加速；水平带软墙；镜头独立于玩家
- [x] 区块化种子生成/释放小行星；敌人上方/两侧刷出并回收；星空纵向视差
- [x] HUD、菜单、编辑器、性能面板竖屏重排
- [x] 距离目标 7200m 胜利；`--endless` 无尽
- [x] autotest 新增：双语加载/切换、缺失键扫描、区块生成/释放、节点数有界、卷轴推进、前推

## Phase 2b 验收标准与测试方法
| # | 标准 | 测试方法 |
|---|---|---|
| 1 | 无缓存启动零错误 | `rm -rf .godot && godot --headless --path . --quit-after 600` |
| 2 | 中英文加载、切换后文本不同 | `CHECK i18n.en_loaded / zh_loaded / switch_changes_text` |
| 3 | 代码使用的键在两种语言都存在 | `CHECK i18n.no_missing_keys`（扫描 scripts/ autoload 中的 tr 字面量 + 数据驱动动态键） |
| 4 | 中文字体可用 | `CHECK i18n.font_loaded`（含“信”字形） |
| 5 | 区块生成与释放、活跃区块 ≤5 | `CHECK chunks.*` |
| 6 | 长时间运行节点数有界 | `-- --autotest=60 --timescale=8 --god --endless`：480s 游戏时间节点数在敌人封顶后稳定于 ~600 |
| 7 | 卷轴推进 / 前推 | `CHECK scroll.progresses / scroll.push_ahead` |
| 8 | 7200m 胜利 | `--god` 运行输出 `run WON ... distance=7200m` |
| 9 | 竖屏布局可读、中文清晰、编辑器可操作 | 人工：540×960 窗口检查 HUD、菜单、Tab 编辑器、切换语言 |

## 已知缺口 / 后续
- [ ] 人工手感测试（box 无显示器，仅 headless 验证）
- [ ] Web 导出（未下载导出模板）
- [ ] 主菜单 / SceneManager
- [ ] 手柄菜单导航细调；设置菜单 UI
- [ ] 编辑器手柄操作（目前仅鼠标）
- [ ] 编辑器内修改的设计不持久化（重开回默认舰船）
- [ ] 协同 emp_crit 在非无敌短局中触发次数少（0–8 次），seed 3287 非无敌运行为 0 → 该检查偶发 FAIL，需调参（如 EMP 不致死、标记时间更长）
- [ ] 竖屏布局仅通过代码坐标设计，未实机目视；12px 字体下英文长文本可能拥挤
- [ ] 无尽模式下 HUD 距离单位“m”未本地化
- [ ] Phase 3–6 见 GAME_DESIGN.md §16

## UI 重做后的缺口
- 屏幕抖动无菜单开关（存档项 `screen_shake` 已存在）。
- 无独立 UI 缩放滑杆，仅窗口整数缩放。
- 编辑器为鼠标操作，尚未支持手柄光标；菜单已支持键盘/手柄焦点。
- 评级 S/A/B/C 公式为暂定值。
