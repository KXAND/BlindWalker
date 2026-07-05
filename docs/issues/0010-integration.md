# Issue #10: 集成 —— 场景装配 + Autoload 注册 + 旧代码清理

**依赖**: Issue #1 ~ #9 全部完成  
**参考**: PRD §3（依赖图）

---

## 需求

将所有模块组装到 `Main.tscn` 中，确认所有 autoload 注册正确，移除旧代码，端到端验证。

## 范围

1. `project.godot` 中注册所有 autoload：`EventBus`, `GameState`, `AudioManager`
2. 更新 `Main.tscn` 中 Player 子节点：
   ```
   Player (CharacterBody3D, 脚本: GaitController)
   ├── CollisionShape3D
   ├── Head → Camera3D
   ├── TouchMemorySystem (已有)
   ├── PlayerAttributes (新)
   ├── ViewController (新)
   └── CaneSystem (新)
   ```
3. 场景根节点添加 `CutsceneManager`
4. 替换 Player 脚本：移除 `PlayerController.gd`（已有 .bak 备份，清理之）
5. 验证启动无报错
6. 在街道场景放置 1-2 个 NPC 测试节点
7. 添加一个 TargetArea（Area3D，走到即通关）

## 验收

- 游戏启动 → 无脚本报错
- W/E 交替迈步正常工作
- 鼠标控制盲杖扫动正常
- R 键控制视角正常
- 走完街道进入 NPC 区域 → 交互提示出现
- 到达 TargetArea → GameState 切换 SUCCESS

## 文件

| 操作 | 文件 |
|------|------|
| 修改 | `project.godot` |
| 修改 | `scenes/main/Main.tscn` |
| 删除 | `scripts/player/PlayerController.gd.bak`（确认 GaitController 工作正常后） |
