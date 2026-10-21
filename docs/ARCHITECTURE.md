# 架构

## 总体原则
- **逻辑与渲染解耦**：`src/sim/` 不依赖 three.js，全部在 2D 平面上运算（x 向右，y 向下，前进方向为 -y），与 Godot 版完全同构。`src/render/` 只读取模拟状态并映射到 three.js：`(x, y) -> (x, 0, y)`，2D 朝向 θ -> `rotation.y = -θ`。
- **固定步长**：`main.ts` 以 1/60s 的固定步长推进模拟，`timescale` 只改变每帧执行的步数（上限防止螺旋），渲染按真实帧率进行。
- **数据驱动**：武器、敌人、能量、波次、模块、协同、环境全部来自 `src/data/*.json`（从 Godot 原样拷贝），平衡与 Godot 版一致。
- **事件总线**：`EventBus` 带类型的事件（enemy_killed、synergy_triggered、core_overheated、explosion、emp_blast……）把模拟、渲染特效、HUD、音效解耦。

## 模块映射（Godot -> Web）
| Godot | Web |
|---|---|
| autoload EventBus / GameManager / InputManager / AudioManager / SaveManager | `src/core/*` |
| energy_core.gd | `sim/EnergyCore.ts`（min_share 归一化、mult=(e0+e1·share·total·3)/(e0+e1)、超载 34/s 升温，过热随机瘫痪一个类别 4s） |
| ship_model.gd | `sim/ShipModel.ts`（连接器 BFS、7 种错误、质量/推力派生属性、方向性模块损毁） |
| weapon.gd / projectile.gd | `sim/Weapon.ts` / `sim/Projectiles.ts`（对象池，导弹每 0.25s 重新索敌） |
| enemy.gd / enemy_director.gd | `sim/Enemy.ts`（chase / strafe / bomber，护盾、EMP、眩晕、引力井减速） |
| synergy_system.gd / gravity_well.gd | `sim/Synergy.ts` |
| asteroid_field.gd | `sim/Asteroids.ts`（480 高的区块按种子生成，向下剔除，矿石连锁，陨石预警） |
| player.gd / battle.gd | `sim/Player.ts` / `sim/Battle.ts`（同样的阻尼积分、冲刺、射界、推屏线、软边界） |

## 渲染
- `Renderer`：WebGLRenderer + EffectComposer（RenderPass → UnrealBloomPass(阈值 0.92，只让 HDR 自发光部件泛光) → OutputPass(ACES + sRGB) → FXAA），高画质用 MSAA×4 的 HalfFloat 渲染目标。DPR 上限 2。
- 画质预设：low（无泛光、DPR1、600 粒子、无动态点光）/ med（半分辨率泛光、DPR1.5、FXAA）/ high（全分辨率泛光、DPR2、MSAA4、4 盏爆炸点光）。auto：软件渲染(SwiftShader/llvmpipe) → low，移动端 → med，桌面 → high。
- `InstancedModel`：每个 GLB 的每个子网格一个 `InstancedMesh`，敌人、小行星、导弹、炸弹全部实例化；子弹是单个实例化网格 + instanceColor。一帧约 60–90 次 draw call。
- 特效：单 draw call 的加色点粒子（环形缓冲）、着色器星云平面、三层星空（顶点着色器内环绕 + 视差）、菲涅尔护盾（4 个受击涟漪）、引力井/离子漩涡着色器、冲击环、时间限长的引擎拖尾带、陨石预警条、地面战术网格与边界墙。
- 相机：透视 42°，俯仰 60°，距离根据宽高比自动计算以完整容纳 236 宽的战斗带；敌人出生有 0.35s 的"跃迁"缩放以掩盖出现。
- 视觉尺寸与碰撞尺寸分离（`SHIP_VIS` / `ENEMY_VIS`），手机上轮廓更易读但不改变平衡。

## UI
纯 DOM/CSS（`ui/`），与画布叠放；CSS 变量 `--u` 随视口缩放，`env(safe-area-inset-*)` 适配刘海。字体为子集化 WOFF2（Noto Sans SC 124KB + Orbitron 12KB）。
- `Hud`：船体/护盾/冲刺条、距离进度、SVG 能量三角、武器热量、协同标签、横幅、伤害数字（世界坐标投影到屏幕）。
- `Touch`：按 pointerId 跟踪的浮动双摇杆 + 按钮，写入 `InputManager.touch`。
- `Builder`：7×7 DOM 网格（机头朝上）覆盖在独立 WebGL 预览上，正交相机经过计算使 3D 模块正好落在 DOM 格子下；可切换为环绕 3D 预览。

## 测试
`src/test/Autotest.ts` 在真实游戏循环里运行脚本化驾驶，并通过真实的 DOM 事件（KeyboardEvent、PointerEvent、按钮 click）驱动；`tools/autotest.mjs` 额外通过 CDP `Input.dispatchTouchEvent` 发送浏览器级多点触控。
