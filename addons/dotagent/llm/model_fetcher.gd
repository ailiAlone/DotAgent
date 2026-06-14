@tool
class_name ModelFetcher
extends RefCounted
## 共享模型获取工具
##
## 职责: 根据提供商信息获取可用模型列表。
## 返回模型信息字典，仅包含 id/name。vision 和 context 由用户通过模型设置页面手动配置。

const ProviderFactoryType = preload("res://addons/dotagent/llm/provider_factory.gd")

var _config: ConfigManager


func _init() -> void:
	_config = ConfigManager.instance()


## 根据提供商名称获取模型列表
## on_complete 回调签名: func(success: bool, models: Array[Dictionary], error_msg: String)
func fetch_models(provider_name: String, host_node: Node, on_complete: Callable) -> void:
	var api_key := _config.get_api_key()
	var base_url := ""
	if provider_name == "Custom":
		base_url = _config.get_base_url()
		if base_url.is_empty():
			on_complete.call(false, [], "Base URL is empty")
			return
	var provider = ProviderFactoryType.create(provider_name, base_url, api_key)
	provider.fetch_models(host_node, on_complete)


## 获取所有提供商定义（给 UI 渲染下拉框）
func get_providers() -> Array:
	return ProviderFactoryType.get_all()
