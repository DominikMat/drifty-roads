extends Node2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _on_play_button_pressed() -> void:
	# visible = false
	animation_player.play("title_card_move")
