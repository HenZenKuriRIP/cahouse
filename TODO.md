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

## 已知缺口 / 后续
- [ ] 人工手感测试（box 无显示器，仅 headless 验证）
- [ ] Web 导出（未下载导出模板）
- [ ] 主菜单 / SceneManager
- [ ] 手柄菜单导航细调；设置菜单 UI
- [ ] Phase 2–6 见 GAME_DESIGN.md §16
