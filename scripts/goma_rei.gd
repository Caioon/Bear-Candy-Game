extends CharacterBody2D

@export var velocidade_movimento: float = 80.0

var jogador: CharacterBody2D
# ---------------------------------------------------------
# ÁRVORE DA CENA ESPERADA
#
# GomaRei (CharacterBody2D)
# +-- AnimatedSprite2D    death, fall, idle, jump
# +-- CollisionShape2D    colisão do corpo (chão e alvo do golpe)
# +-- AreaDano (Area2D)   hitbox que machuca o jogador
# |   +-- CollisionShape2D
# +-- HealthBarGoma
#
# PLATAFORMAS ONE-WAY:
# - As plataformas one-way precisam estar numa camada (layer) própria,
#   diferente do chão normal. Informe o número dela em "camada_plataformas".
# - Quando o jogador está abaixo da goma, ela desliga a colisão com essa
#   camada por um instante e cai pela plataforma.
#
# SINAIS:
# - vida_alterada: usado pela barra de vida.
# - eliminada: emitido uma vez, no instante em que a goma morre
#   (o spawner usa para o contador de inimigos eliminados).
# ---------------------------------------------------------
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var area_dano: Area2D = $AreaDano
@onready var health_bar: Node2D = $HealthBarGoma

# Nomes das animações (têm que bater com o SpriteFrames)
const ANIM_IDLE := "idle"
const ANIM_JUMP := "jump"
const ANIM_FALL := "fall"
const ANIM_DEATH := "death"

enum State {
	IDLE,
	JUMP,
	FALL,
	DEAD
}

@export var vida_maxima: int = 6
@export var dano_de_contato: int = 1
@export var forca_do_pulo: float = 250.0
@export var tempo_idle_min: float = 1.0
@export var tempo_idle_max: float = 2.5
@export var sumir_apos_morrer: bool = true
@export var tempo_para_sumir: float = 1.0

@export_group("Plataformas")
## Se true, a goma atravessa plataformas one-way para descer até o jogador.
@export var descer_plataformas: bool = true
## Número da camada (1 a 32) onde estão as plataformas one-way.
@export_range(1, 32) var camada_plataformas: int = 4
## O jogador precisa estar pelo menos essa distância (em pixels) abaixo da goma.
@export var diferenca_para_descer: float = 24.0
## Tempo que a colisão com as plataformas fica desligada durante a descida.
@export var tempo_atravessando: float = 0.3

var vida: int
var state: State = State.IDLE
var tempo_idle_restante: float = 0.0
var saiu_do_chao: bool = false
var tween_flash: Tween
var atravessando: bool = false
var tempo_atravessando_restante: float = 0.0

signal vida_alterada(vida_atual: int)
signal eliminada


func _ready() -> void:
	jogador = get_tree().get_first_node_in_group("player") as CharacterBody2D

	vida = vida_maxima
	vida_alterada.emit(vida)

	# Garante por código que "jump" trava no último frame e que "fall"
	# e "death" tocam uma vez só. Só "idle" fica em loop.
	var frames := anim.sprite_frames
	frames.set_animation_loop(ANIM_IDLE, true)
	frames.set_animation_loop(ANIM_JUMP, false)
	frames.set_animation_loop(ANIM_FALL, false)
	frames.set_animation_loop(ANIM_DEATH, false)

	anim.animation_finished.connect(_on_anim_animation_finished)

	go_to_idle()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	atualizar_travessia(delta)

	# Checa em QUALQUER estado vivo, para reagir no mesmo instante
	if state != State.DEAD and deve_descer():
		go_to_drop()

	match state:
		State.IDLE:
			state_idle(delta)
		State.JUMP:
			state_jump()
		State.FALL:
			state_fall()
		State.DEAD:
			state_dead()

	move_and_slide()

	if state != State.DEAD:
		aplicar_dano_de_contato()


func levar_dano(quantidade: int) -> void:
	if state == State.DEAD:
		return

	vida = max(vida - quantidade, 0)

	vida_alterada.emit(vida)

	if vida <= 0:
		morrer()
		return

	piscar_dano()


func morrer() -> void:
	# Evita morrer (e contar) duas vezes.
	if state == State.DEAD:
		return

	state = State.DEAD
	velocity.x = 0
	anim.play(ANIM_DEATH)

	# Esconde a barra de vida instantaneamente
	health_bar.hide()

	# Perde a hitbox: o jogador não toma mais dano e os golpes não o acertam.
	# A máscara de colisão é mantida, então se morrer no ar ele ainda cai até o chão.
	area_dano.set_deferred("monitoring", false)
	set_deferred("collision_layer", 0)

	eliminada.emit()


func piscar_dano() -> void:
	if tween_flash:
		tween_flash.kill()
	anim.modulate = Color(1, 0.4, 0.4)
	tween_flash = create_tween()
	tween_flash.tween_property(anim, "modulate", Color(1, 1, 1), 0.2)


# =========================================================
# DANO DE CONTATO (goma -> jogador)
# =========================================================

func aplicar_dano_de_contato() -> void:
	# Checa todo frame: o jogador tem seu próprio tempo de invulnerabilidade
	# (HURT), então se continuar encostado ele toma dano de novo ao fim dele.
	for corpo in area_dano.get_overlapping_bodies():
		if corpo != self and corpo.is_in_group("player") and corpo.has_method("levar_dano"):
			corpo.levar_dano(dano_de_contato)


# =========================================================
# DESCER PELAS PLATAFORMAS ONE-WAY
# =========================================================

## O jogador está abaixo da goma e ela está pisando em algo?
func deve_descer() -> bool:
	if not descer_plataformas or atravessando:
		return false
	if not is_on_floor():
		return false
	if jogador == null or not is_instance_valid(jogador):
		return false
	return jogador.global_position.y - global_position.y > diferenca_para_descer


## Liga a colisão com as plataformas de novo quando o tempo acaba.
func atualizar_travessia(delta: float) -> void:
	if not atravessando:
		return

	tempo_atravessando_restante -= delta
	if tempo_atravessando_restante <= 0.0:
		atravessando = false
		set_collision_mask_value(camada_plataformas, true)


## Desliga a colisão com as plataformas e cai. Reaproveita o estado JUMP:
## ela se move em direção ao jogador e, ao pousar, toca a animação de pouso.
func go_to_drop() -> void:
	state = State.JUMP
	saiu_do_chao = false
	anim.play(ANIM_JUMP)

	atravessando = true
	tempo_atravessando_restante = tempo_atravessando
	set_collision_mask_value(camada_plataformas, false)

	# Começa a cair já no primeiro frame, sem esperar a gravidade acumular
	velocity.y = 60.0


# =========================================================
# ESTADO: IDLE
# =========================================================

func state_idle(delta: float) -> void:
	velocity.x = 0

	tempo_idle_restante -= delta
	if tempo_idle_restante <= 0.0:
		go_to_jump()


# =========================================================
# ESTADO: JUMP (anima os 2 frames e trava no segundo até tocar o chão)
# =========================================================

func state_jump() -> void:
	movimentar_em_direcao_ao_jogador()

	# Só considera "pousou" depois de ter realmente saído do chão.
	if not is_on_floor():
		saiu_do_chao = true
	elif saiu_do_chao:
		go_to_fall()


# =========================================================
# ESTADO: FALL (animação de pouso; ao terminar volta ao idle)
# =========================================================

func state_fall() -> void:
	# Se tocou o chão, interrompe o movimento imediatamente.
	if is_on_floor():
		velocity.x = 0
		return

	movimentar_em_direcao_ao_jogador()


# =========================================================
# ESTADO: DEAD
# =========================================================

func state_dead() -> void:
	velocity.x = 0


# =========================================================
# TRANSIÇÕES DE ESTADO
# =========================================================

func go_to_idle() -> void:
	state = State.IDLE

	# Freia instantaneamente ao tocar o chão.
	velocity.x = 0

	anim.play(ANIM_IDLE)
	tempo_idle_restante = randf_range(tempo_idle_min, tempo_idle_max)


func go_to_jump() -> void:
	state = State.JUMP
	saiu_do_chao = false
	anim.play(ANIM_JUMP)
	velocity.y = -forca_do_pulo


func go_to_fall() -> void:
	state = State.FALL
	anim.play(ANIM_FALL)


# =========================================================
# SINAIS
# =========================================================

func _on_anim_animation_finished() -> void:
	match state:
		State.FALL:
			go_to_idle()
		State.DEAD:
			if sumir_apos_morrer:
				await get_tree().create_timer(tempo_para_sumir).timeout
				queue_free()
		# State.JUMP: nada a fazer, a animação fica parada no último frame.


func movimentar_em_direcao_ao_jogador() -> void:
	if jogador == null or not is_instance_valid(jogador):
		velocity.x = 0
		return

	var direcao = sign(jogador.global_position.x - global_position.x)

	velocity.x = direcao * velocidade_movimento

	# Vira o sprite na direção do jogador.
	if direcao != 0:
		anim.flip_h = direcao < 0
