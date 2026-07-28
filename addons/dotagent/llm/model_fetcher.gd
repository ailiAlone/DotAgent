@tool
class_name ModelFetcher
extends RefCounted
## 共享模型获取工具
##
## 职责: 
##   - 从 ModelDatabase 获取提供商列表（UI 下拉框用）
##   - 从 ModelDatabase 获取指定提供商的模型列表（不再调用 API）

var _db: ModelDatabase = null


func _init() -> void:
	_db = ModelDatabase.new()


## 获取指定提供商的模型列表（从本地缓存）
## on_complete 回调签名: func(success: bool, models: Array[Dictionary], error_msg: String)
func fetch_models(provider_name: String, _host_node: Node, on_complete: Callable) -> void:
	var raw_models: Array = _db.get_provider_models(provider_name)
	if raw_models.is_empty():
		var empty: Array[Dictionary] = []
		on_complete.call(false, empty, "No models found for provider: " + provider_name)
	else:
		var models: Array[Dictionary] = []
		for m in raw_models:
			models.append(m)
		on_complete.call(true, models, "")


## 获取所有提供商定义（给 UI 渲染下拉框）
func get_providers() -> Array:
	return _db.get_providers()


## 刷新模型数据库（从 models.dev 重新下载）
## on_complete 回调签名: func(success: bool, message: String)
func refresh_database(host_node: Node, on_complete: Callable) -> void:
	_db.refresh(host_node, on_complete)


## 获取缓存信息
func get_cache_info() -> Dictionary:
	return _db.get_cache_info()
