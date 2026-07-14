class_name TutorialPrompt
extends Resource
## 上下文教程内容资源。触发逻辑由 TutorialManager 管理，资源只保存文案。

@export var tutorial_id: StringName = &""
@export var title: String = ""
@export_multiline var body: String = ""
