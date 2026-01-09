extends Area2D

@onready var sprite: Sprite2D = $Sprite2D
@onready var particles: GPUParticles2D = $GPUParticles2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func explode():
	collision.set_deferred("disabled", true)
	sprite.visible = false
	particles.emitting = true
	await get_tree().create_timer(particles.lifetime).timeout
	queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player"):
		print("crate collision detected ")
		explode()
