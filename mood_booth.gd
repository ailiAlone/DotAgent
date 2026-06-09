extends Control

@onready var emoji_label := %EmojiLabel
@onready var mood_label := %MoodLabel
@onready var bg_panel := $BgPanel

const MOODS := {
	"happy": {"emoji": "😊", "text": "Happy \u2728", "color": Color("#2ecc71"), "bg_color": Color("#1a3a2a")},
	"neutral": {"emoji": "😐", "text": "Neutral", "color": Color("#f39c12"), "bg_color": Color("#2a2218")},
	"sad": {"emoji": "😢", "text": "Sad", "color": Color("#3498db"), "bg_color": Color("#1a223a")},
	"surprised": {"emoji": "😲", "text": "Surprised", "color": Color("#e74c3c"), "bg_color": Color("#3a1a1a")},
	"love": {"emoji": "😍", "text": "Love", "color": Color("#e91e63"), "bg_color": Color("#3a1a2a")},
	"cool": {"emoji": "😎", "text": "Cool", "color": Color("#00bcd4"), "bg_color": Color("#1a2a3a")},
}

func _ready() -> void:
	_update_mood("happy")


func _on_happy_btn_pressed() -> void:
	_update_mood("happy")


func _on_neutral_btn_pressed() -> void:
	_update_mood("neutral")


func _on_sad_btn_pressed() -> void:
	_update_mood("sad")


func _on_random_btn_pressed() -> void:
	var keys = MOODS.keys()
	var key = keys[randi() % keys.size()]
	_update_mood(key)


func _update_mood(key: String) -> void:
	if not MOODS.has(key):
		return
	var mood = MOODS[key]
	emoji_label.text = mood["emoji"]
	mood_label.text = mood["text"]
	mood_label.add_theme_color_override("font_color", mood["color"])
	bg_panel.modulate = mood["bg_color"]
