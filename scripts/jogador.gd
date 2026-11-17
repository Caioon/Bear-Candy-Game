extends CharacterBody2D

# ---------------------------------------------------------
# ÁRVORE DA CENA ESPERADA
#
# Jogador (CharacterBody2D)
# +-- Corpo          (AnimatedSprite2D)  com maquina de estados
# +-- Garras         (AnimatedSprite2D)  os golpes laterais e cima/baixo (Visible desmarcado, Z Index 2)
# +-- CollisionShape2D                   colisão do corpo
# +-- AreaGolpe      (Area2D, posição 0,0)
#     +-- CollisionShape2D   (única hitbox, redimensionada e reposicionada a cada golpe)
#
# COYOTE TIME:
# - Ao sair do chão SEM ter pulado (andou para fora de uma borda, por exemplo),
#   o jogador ainda pode dar um pulo no ar durante "tempo_coyote" segundos.
# - Depois desse pulo, ou passado o tempo, não pode mais pular no ar.
# ---------------------------------------------------------
signal vida_alterada(vida_atual: int)
signal morreu

@onready var anim: AnimatedSprite2D = $Corpo
@onready var garras: AnimatedSprite2D = $Garras
@onready var collision: CollisionShape2D = $ColisaoCorpo
@onready var area_golpe: Area2D = $AreaGolpe
@onready var hitbox: CollisionShape2D = $AreaGolpe/CollisionShape2D

const SPEED = 150.0
const JUMP_VELOCITY = -300.0
const MAX_JUMPS = 1

const SPEED_RUN = 200.0

# Nomes das animações do nó Garras (têm que bater com o SpriteFrames)
const ANIM_GOLPE_LATERAL := "attack lateral partial"
const ANIM_GOLPE_CIMA := "attack up partial"
const ANIM_GOLPE_BAIXO := "attack down partial"

# Hitbox lateral (posição para a DIREITA; ao olhar para a esquerda, x é invertido)
const LATERAL_SIZE := Vector2(25.25, 59.0)
const LATERAL_POS := Vector2(17.0, -1.0)

# Hitbox de cima e de baixo (mesmo tamanho; baixo é o espelho vertical de cima)
const VERTICAL_SIZE := Vector2(58.0, 32.5)
const CIMA_POS := Vector2(0, -12.0)
const BAIXO_POS := Vector2(0, 12.0)

const VELOCIDADE_DURANTE_ATAQUE := 0.35

enum State {
	IDLE,
	WALK,
	JUMP,
	HURT,
	RUN,
	DEAD
}

@export var tempo_invencibilidade: float = 1.5

@export var vida_maxima: int = 5
@export var tempo_hurt: float = 0.4
@export var dano_do_golpe: int = 1
@export var quadro_do_golpe: int = 3
@export var recarga_ataque: float = 0.4
@export var intervalo_blink: float = 0.1

## Tempo (em segundos) após sair do chão em que ainda é possível pular.
@export var tempo_coyote: float = 0.2

var tempo_blink: float = 0.0
var sprite_visivel: bool = true

var inimigos_atingidos: Array[Node2D] = []
var vida: int
var state: State = State.IDLE
var jump_count: int = 0
var tempo_no_hurt: float = 0.0
var golpe_aplicado: bool = false
var atacando: bool = false
var recarga_restante: float = 0.0
var olhando_esquerda: bool = false
var forma_golpe: RectangleShape2D
var coyote_restante: float = 0.0


func _ready() -> void:
	vida = vida_maxima
	vida_alterada.emit(vida)

	forma_golpe = RectangleShape2D.new()
	hitbox.shape = forma_golpe
	hitbox.disabled = true

	area_golpe.monitoring = false
	garras.visible = false
	garras.animation_finished.connect(_on_garras_animation_finished)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Morto: só gravidade, sem input, sem ataque
	if state == State.DEAD:
		velocity.x = 0
		move_and_slide()
		return

	recarga_restante = max(0.0, recarga_restante - delta)
	atualizar_coyote(delta)

	match state:
		State.IDLE:
			state_idle()
		State.WALK:
			state_walk()
		State.JUMP:
			state_jump()
		State.HURT:
			state_hurt()

	# Ataque funciona em qualquer estado, menos HURT
	var direcao_ataque := obter_direcao_ataque()

	if direcao_ataque != 0 \
			and not atacando \
			and recarga_restante <= 0.0:
		iniciar_ataque(direcao_ataque)

	if atacando:
		atualizar_ataque()

	move_and_slide()

	if is_on_floor():
		jump_count = 0


# =========================================================
# COYOTE TIME
# =========================================================

## No chão a janela fica cheia; no ar ela vai acabando.
## Ao pular, a janela é zerada (ver consumir_coyote), então sair do chão
## por causa de um pulo não dá direito a outro pulo.
func atualizar_coyote(delta: float) -> void:
	if is_on_floor():
		coyote_restante = tempo_coyote
	else:
		coyote_restante = max(0.0, coyote_restante - delta)


func consumir_coyote() -> void:
	coyote_restante = 0.0


## Pode pular no ar? Só durante o coyote time, e só se ainda não pulou.
func pode_pular_no_ar() -> bool:
	return jump_count < MAX_JUMPS and (coyote_restante > 0.0 or jump_count > 0)


func levar_dano(quantidade: int) -> void:
	if state == State.HURT or state == State.DEAD:
		return

	vida = max(vida - quantidade, 0)

	vida_alterada.emit(vida)

	if vida <= 0:
		morrer()
		return

	go_to_hurt()


func morrer() -> void:
	state = State.DEAD
	encerrar_ataque()
	anim.visible = true
	anim.play("death")
	velocity.x = 0
	morreu.emit()


func update_direction() -> float:
	var direction := Input.get_axis("left", "right")

	# Durante o golpe a direção fica travada, para o efeito e a hitbox
	# continuarem coerentes até o fim da animação.
	if not atacando:
		if direction > 0:
			olhando_esquerda = false
			anim.flip_h = false
		elif direction < 0:
			olhando_esquerda = true
			anim.flip_h = true

	return direction


# =========================================================
# ATAQUE (Garras + hitbox)
# =========================================================

func iniciar_ataque(direcao: int) -> void:
	atacando = true
	golpe_aplicado = false
	inimigos_atingidos.clear()
	recarga_restante = recarga_ataque

	# Vira o personagem para o lado do ataque
	olhando_esquerda = direcao < 0
	anim.flip_h = olhando_esquerda

	var nome_anim: String

	garras.flip_h = false
	garras.flip_v = false

	if Input.is_action_pressed("down"):
		nome_anim = ANIM_GOLPE_BAIXO
		garras.flip_v = true
		forma_golpe.size = VERTICAL_SIZE
		hitbox.position = BAIXO_POS

	elif Input.is_action_pressed("up"):
		nome_anim = ANIM_GOLPE_CIMA
		forma_golpe.size = VERTICAL_SIZE
		hitbox.position = CIMA_POS

	else:
		nome_anim = ANIM_GOLPE_LATERAL
		garras.flip_h = olhando_esquerda
		forma_golpe.size = LATERAL_SIZE
		hitbox.position = Vector2(
			-LATERAL_POS.x if olhando_esquerda else LATERAL_POS.x,
			LATERAL_POS.y
		)

	area_golpe.set_deferred("monitoring", true)
	hitbox.set_deferred("disabled", false)

	garras.visible = true
	garras.play(nome_anim)


func atualizar_ataque() -> void:
	if not atacando or not area_golpe.monitoring:
		return

	var corpos = area_golpe.get_overlapping_bodies()

	for corpo in corpos:
		if corpo == self:
			continue

		if not corpo.is_in_group("inimigos"):
			continue

		if not corpo.has_method("levar_dano"):
			continue

		# Impede que o mesmo inimigo receba dano duas vezes
		# durante a mesma execução do ataque.
		if corpo in inimigos_atingidos:
			continue

		inimigos_atingidos.append(corpo)

		corpo.levar_dano(dano_do_golpe)


func encerrar_ataque() -> void:
	atacando = false
	golpe_aplicado = false

	inimigos_atingidos.clear()

	garras.stop()
	garras.visible = false

	area_golpe.set_deferred("monitoring", false)
	hitbox.set_deferred("disabled", true)


func _on_garras_animation_finished() -> void:
	if atacando:
		encerrar_ataque()


# Retorna -1 (esquerda), 1 (direita) ou 0 (nenhum ataque pedido)
func obter_direcao_ataque() -> int:
	if Input.is_action_just_pressed("attack_left"):
		return -1

	if Input.is_action_just_pressed("attack_right"):
		return 1

	if Input.is_action_just_pressed("attack_mouse"):
		var mouse_x := get_global_mouse_position().x
		return -1 if mouse_x < global_position.x else 1

	return 0


func obter_velocidade_movimento() -> float:
	var velocidade_base := SPEED_RUN if Input.is_action_pressed("run") else SPEED

	if atacando:
		return velocidade_base * VELOCIDADE_DURANTE_ATAQUE

	return velocidade_base


# =========================================================
# ESTADO: IDLE
# =========================================================

func state_idle() -> void:
	if not is_on_floor():
		go_to_fall()
		return

	velocity.x = move_toward(velocity.x, 0, SPEED)
	var direction := update_direction()

	if direction != 0:
		go_to_walk()
		return

	if Input.is_action_just_pressed("jump"):
		go_to_jump()
		return


# =========================================================
# ESTADO: WALK
# =========================================================

func state_walk() -> void:
	if not is_on_floor():
		go_to_fall()
		return

	var direction := update_direction()

	if direction == 0:
		go_to_idle()
		return

	if Input.is_action_just_pressed("jump"):
		go_to_jump()
		return

	velocity.x = direction * obter_velocidade_movimento()


# =========================================================
# ESTADO: JUMP
# =========================================================

func state_jump() -> void:
	var direction := update_direction()

	if direction != 0:
		velocity.x = direction * obter_velocidade_movimento()
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# Pulo no ar: só vale dentro do coyote time (ver pode_pular_no_ar).
	if Input.is_action_just_pressed("jump") and pode_pular_no_ar():
		velocity.y = JUMP_VELOCITY
		jump_count += 1
		consumir_coyote()
		return

	if is_on_floor():
		jump_count = 0

		if direction != 0:
			go_to_walk()
			return

		go_to_idle()
		return


# =========================================================
# ESTADO: HURT
# =========================================================
func state_hurt() -> void:
	var delta = get_physics_process_delta_time()

	tempo_no_hurt += delta
	tempo_blink += delta

	var direction := Input.get_axis("left", "right")

	# Movimentação durante o HURT
	velocity.x = direction * obter_velocidade_movimento()

	# Atualiza a direção do sprite
	if direction > 0:
		olhando_esquerda = false
		anim.flip_h = false
	elif direction < 0:
		olhando_esquerda = true
		anim.flip_h = true

	# Permite pular durante o HURT (no chão ou dentro do coyote time)
	if Input.is_action_just_pressed("jump") and (is_on_floor() or coyote_restante > 0.0):
		velocity.y = JUMP_VELOCITY
		jump_count = 1
		consumir_coyote()

	# Controla o piscar
	if tempo_blink >= intervalo_blink:
		tempo_blink = 0.0
		anim.visible = !anim.visible

	# Finaliza a imunidade
	if tempo_no_hurt >= tempo_invencibilidade:
		anim.visible = true
		go_to_idle()


# =========================================================
# TRANSIÇÕES DE ESTADO
# =========================================================

func go_to_idle() -> void:
	state = State.IDLE
	anim.play("idle")


func go_to_walk() -> void:
	state = State.WALK
	anim.play("walk")


func go_to_jump() -> void:
	state = State.JUMP
	anim.play("jump")
	velocity.y = JUMP_VELOCITY
	jump_count += 1
	# Pulou do chão: não ganha coyote time ao sair dele.
	consumir_coyote()


func go_to_hurt() -> void:
	state = State.HURT
	anim.play("idle")

	tempo_no_hurt = 0.0
	tempo_blink = 0.0
	sprite_visivel = true

	anim.visible = true

	velocity.x = 0


# Saiu do chão sem pular: ainda tem o coyote time para dar um pulo no ar.
# jump_count fica em 0; quem limita o pulo é o tempo (pode_pular_no_ar).
func go_to_fall() -> void:
	state = State.JUMP
	anim.play("jump")
	jump_count = 0
