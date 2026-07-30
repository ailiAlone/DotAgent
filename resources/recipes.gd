## Defines a crafting recipe: required materials and the resulting effect.

class_name Recipe
extends Resource

@export var id: String
@export var name: String
@export var description: String
@export var ingredients: Dictionary = {  }
@export var result_type: String
@export var result_value: int = 0.0
@export var result_amount: int = 1.0
@export var icon: String
@export var color: Color = Color.WHITE
