# Issue #7: AudioManager 音频管理

**依赖**: Issue #1 (EventBus)  
**参考**: PRD §2.10

---

## 需求

创建 autoload 单例 `AudioManager.gd`。监听 EventBus 音频请求信号，在指定 3D 位置播放音效。

## 范围

1. 创建 `scripts/core/AudioManager.gd`，autoload
2. 维护一个 `AudioStreamPlayer3D` 池（MVP 用 4 个即可）
3. 监听 `EventBus.audio_requested(sound_id, position, volume_db)`
4. `play_3d(sound_id: String, position: Vector3, volume_db: float)`
5. `play_2d(sound_id: String, volume_db: float)` 用于 UI/系统提示
6. 预置一组音效映射表（sound_id → 资源路径），先用空音频占位，后续替换
7. `@export var master_volume_db: float = 0.0`

## 验收

- 发射 `audio_requested("step", Vector3(1,0,0), -6.0)` → 指定位置播放
- 音量调节后所有音效生效

## 文件

| 操作 | 文件 |
|------|------|
| 新建 | `scripts/core/AudioManager.gd` |
| 修改 | `project.godot`（添加 autoload） |
