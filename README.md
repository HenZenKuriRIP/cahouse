# VOID SIGNAL（虚空信号）

原创像素风太空战斗 Roguelite，Godot 4.3 + GDScript。内部分辨率 480×270，整数缩放（默认窗口 1440×810）。

## 当前状态：Phase 1（核心战斗原型）
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
| 开火 | 鼠标左键 | RT / R1 |
| 冲刺 | Space | A |
| 加速(预留) | Shift | RB |
| 暂停 | Esc | Start/Back |
| 性能面板 | F3 | — |

## 运行
```bash
godot --path .                      # 正常游玩
godot --headless --path . --import  # 导入
# 自动测试：自动驾驶跑完整局，打印统计后退出
godot --headless --path . -- --autotest=40 --timescale=6 [--god] [--seed=123]
```

文档：`GAME_DESIGN.md`（设计）、`ARCHITECTURE.md`（技术架构）、`TODO.md`（路线图与任务）、`DEVELOPMENT_LOG.md`（开发与验证日志）。
