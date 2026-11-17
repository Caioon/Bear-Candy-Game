extends Area2D

## O Portal (nó com o spawner2.gd). Se ficar vazio, usa o nó pai.
@export var spawner: Node2D

const GRUPO_JOGADOR := "player"


func _ready() -> void:
	if spawner == null:
		spawner = get_parent()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group(GRUPO_JOGADOR):
		spawner.jogador_entrou()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group(GRUPO_JOGADOR):
		spawner.jogador_saiu()
