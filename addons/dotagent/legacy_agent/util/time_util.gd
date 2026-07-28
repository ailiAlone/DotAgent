@tool
class_name TimeUtil
extends RefCounted
## 时间工具 — 集中所有"格式 + 替换"重复代码

## 返回适合做文件名的 timestamp: "2025-01-30_14-22-35"
## 跨文件统一,避免每个 backup/session/logger 重复 Time.get_datetime_string_from_system + replace
static func ts_slug() -> String:
	return Time.get_datetime_string_from_system(false).replace(":", "-").replace("T", "_")


## 短时间戳 "2025-01-30 14:22:35" 适合在 UI 显示
static func ts_display() -> String:
	return Time.get_datetime_string_from_system(false)
