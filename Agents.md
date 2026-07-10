# BlindWalker 技术规范

## 1. 项目定位

- 项目类型：`Godot 3D` 公益主题游戏
- 发布形态：`Web`，可直接在线访问
- 核心体验：玩家扮演视障者，通过盲杖探测、喷枪标记、问路与求助，到达目标地点
- 目标阶段：`一周内可交付 MVP`

## 2. 引擎与技术栈

- 引擎版本：`Godot 4.x`
- 运行时脚本语言：`GDScript`
- Web 导出目标：`Godot Web Export`
- 前端壳层：仅在必要时使用简单 HTML 承载导出产物
- AI 接入：通过 `HTTP API` 或赛事官方 `Agent`，不在客户端直连私钥

约束：

- `Web` 版本运行时代码禁止依赖 `C#`
- 不引入与 MVP 无关的复杂插件
- 不做多人联机

## 3. 目录约定

项目落地后统一使用以下结构：

```text
/
  project.godot
  Agents.md
  scenes/
    main/
    gameplay/
    ui/
    npc/
  scripts/
    core/
    player/
    interaction/
    ai/
    ui/
  assets/
    models/
    materials/
    textures/
    audio/
  web/
    shell/
  docs/
```

约束：

- 场景文件放在 `scenes/`
- 脚本文件放在 `scripts/`
- 美术与音频资源放在 `assets/`
- 与网页壳层相关的文件放在 `web/`

## 4. 场景与系统划分

MVP 最少包含以下场景：

- `Main`：启动、加载、进入主流程
- `Level_Street`：主关卡，包含下楼梯、过马路、问路
- `UI_Overlay`：提示、任务、字幕、AI 对话入口
- `Result`：成功/失败结算

核心系统：

- `PlayerController`：移动、视角、盲杖、喷枪
- `InteractionSystem`：物体交互、NPC 交互、触发器
- `AIService`：问路/求助请求封装
- `GameState`：任务状态、检查点、失败/通关
- `AudioManager`：环境音、提示音、语音播放

## 5. 编码规范

- 运行时代码统一使用 `GDScript`
- 一类职责一个脚本，不写超大脚本
- 节点引用优先使用 `@export` 或明确缓存，避免深层硬编码路径
- 系统间通信优先使用 `signal`
- 除 `GameState`、`AIService` 外，尽量避免继续增加全局单例
- 提交前保证无明显报错、无未使用大段调试代码

命名约定：

- 场景：`PascalCase`
- 脚本：`PascalCase.gd`
- 节点：语义化命名，如 `Player`, `CaneRay`, `SprayMarker`, `CrosswalkTrigger`
- 资源文件：小写下划线，如 `street_blockout.glb`

## 6. 玩法实现边界

MVP 只做以下能力：

- 玩家基础移动
- 盲杖探测前方物体/边缘
- 喷枪标记关键物体
- 与 NPC 问路
- 对盲文或提示牌发起 AI 求助
- 一条完整路线的成功/失败流程

MVP 不做：

- 开放世界
- 多关卡扩展系统
- 复杂数值成长
- 大量可收集内容
- 实时联网同步

## 7. AI 接入规范

允许的 AI 用途：

- NPC 问路回答
- 盲文/提示信息解释
- 世界观、文案、原画、配音等赛事要求材料生成

强制要求：

- 所有模型密钥只能放在服务端或安全代理层
- 客户端不得硬编码 API Key
- AI 输出必须经过长度限制与基础内容校验
- AI 请求失败时必须有降级方案

降级方案：

- 问路失败时返回预置规则回答
- 盲文识别失败时返回固定帮助提示

赛事留档要求：

- 保存官方 Agent 的关键对话记录
- 保存 AI 生成内容与对应用途说明
- 保留最终用于游戏内的文案/图片/语音清单

## 8. Web 导出规范

- 首要目标平台：桌面浏览器 `Chrome / Edge`
- 分辨率策略：默认 `16:9`，最小适配宽度 `1280x720`
- 输入方式：`键盘 + 鼠标`
- 移动端仅做基础兼容，不作为主验收目标

约束：

- 导出版本必须可在静态托管环境直接访问
- 页面加载后应能明确看到开始入口或自动进入主菜单
- 如需网页侧交互，优先通过 `JavaScriptBridge` 或标准 HTTP

## 9. 性能预算

- 目标帧率：桌面浏览器下稳定 `30 FPS` 以上，优先争取 `60 FPS`
- 单关场景控制在小体量
- 模型以低模为主，避免高面数与超大贴图
- 贴图优先使用适合 Web 的压缩尺寸
- 音频优先 `ogg`

建议预算：

- 单个主场景尽量控制为小型街区
- 单张贴图尽量不超过 `2048`
- 首屏资源尽量只保留通关所需内容

## 10. 交互与可访问性

由于题材与视障体验直接相关，必须保证：

- 音频提示优先级高于纯视觉提示
- 关键交互点必须同时具备声音、UI 或文本反馈
- 危险区域要有稳定、明确、可重复感知的反馈
- AI 说明文本必须简短直接，避免冗长回答

## 11. 部署与交付

最终交付至少包含：

- 可在线访问的 Web 地址
- 可运行的 Godot 工程
- 官方 Agent 使用记录
- AI 生成内容说明
- 简短玩法说明

## 12. Git 提交规范

- 格式遵循 [Conventional Commits](https://www.conventionalcommits.org/)
- 提交信息使用英文
- 如果提交涉及某个 ADR 或 Issue 的实现，在 commit message 末尾附上其编号

示例：

```
feat(audio): add audio manager autoload (issue #0007)
fix(cane): replace raycast with intersect_shape for penetration prevention (adr #0006)
docs: update cane system docs to reflect intersect_shape implementation (adr #0006, issue #0005)
```

常用类型：`feat` / `fix` / `docs` / `refactor` / `chore` / `test`

## 13. 变更原则

- 默认只做最小必要改动
- 非明确需求不扩展玩法范围
- 非明确重构请求，不调整既有结构到大改级别
- 所有新增功能必须先服务于 MVP 可交付

