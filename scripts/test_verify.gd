## Simple counter class with add, reset and count_changed signal.

extends Node

signal count_changed(new_count: int)

@export var count: int = 0.0

func add(amount: int = 1):
		count += amount
		count_changed.emit(count)
	

func reset():
		count = 0
		count_changed.emit(count)
	
