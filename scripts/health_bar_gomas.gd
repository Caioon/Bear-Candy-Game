extends Node2D

const HEART_FULL = preload("res://sprites/Bear candy sprites/Outros/coracao_preenchido.png")
const HEART_EMPTY = preload("res://sprites/Bear candy sprites/Outros/coracao_vazio.png")

@onready var hearts = [
	$Heart1,
	$Heart2,
]

func atualizar_vida(vida: int) -> void:
	for i in range(hearts.size()):
		if i < vida:
			hearts[i].texture = HEART_FULL
		else:
			hearts[i].texture = HEART_EMPTY

func _ready() -> void:
	var goma = get_parent()

	goma.vida_alterada.connect(atualizar_vida)

	atualizar_vida(goma.vida)
