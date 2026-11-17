extends Node2D

const HEART_FULL = preload("res://sprites/Bear candy sprites/Outros/coracao_preenchido.png")
const HEART_EMPTY = preload("res://sprites/Bear candy sprites/Outros/coracao_vazio.png")

# Quantos pontos de vida cada coração vale (6 de vida / 3 corações = 2)
const VIDA_POR_CORACAO := 2

@onready var hearts = [
	$Heart1,
	$Heart2,
	$Heart3
]

func atualizar_vida(vida: int) -> void:
	# Cada coração representa VIDA_POR_CORACAO pontos de vida.
	# O coração só esvazia quando perde os 2 pontos dele (vida > i * 2 = ainda cheio).
	for i in range(hearts.size()):
		if vida > i * VIDA_POR_CORACAO:
			hearts[i].texture = HEART_FULL
		else:
			hearts[i].texture = HEART_EMPTY

func _ready() -> void:
	var goma = get_parent()

	goma.vida_alterada.connect(atualizar_vida)

	atualizar_vida(goma.vida)
