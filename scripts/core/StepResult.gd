class_name StepResult
## 步态执行结果的数据结构

enum StepResultType { SUCCESS, STAGGER, FALL }

var type: StepResultType = StepResultType.SUCCESS
var displacement: Vector3 = Vector3.ZERO
