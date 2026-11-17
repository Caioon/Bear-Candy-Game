extends Node2D

# ---------------------------------------------------------
# ESTRUTURA
#
# Portal (Node2D)          <- este script
# +-- esquerdo (Node2D)    (visual + marcador1)
# +-- direito (Node2D)     (visual + marcador2)
# +-- Area2D               <- o retângulo (startspawn.gd)
#     +-- CollisionShape2D
#
# - Os portais são só visuais, nunca são escondidos.
# - Jogador entra no Area2D: aparece o aviso, depois o timer roda.
# - Jogador sai: os timers pausam e o label do timer fica cinza.
# - Jogador morre: o evento para completamente.
# - Tempo acaba: todos os inimigos morrem e aparece "Você venceu!".
# - Cada AnimatedSprite2D dentro de "Esquerdo" e "Direito" ganha uma colisão
#   criada por código, que só fica ativa enquanto o evento está ativo
#   (do início do timer até o fim do tempo ou a morte do jogador).
# - Os inimigos nascem em TODOS os Marker2D dentro do Portal.
# - O jogador precisa estar no grupo "player" e ter o sinal "morreu".
# - Se um inimigo tiver o método morrer(), ele é chamado na vitória;
#   senão o inimigo é removido com queue_free().
# ---------------------------------------------------------

signal tempo_esgotado

@export_group("Inimigos")
@export var cenas_inimigos: Array[PackedScene] = [
	preload("res://entities/goma-azul.tscn"),
	preload("res://entities/goma-laranja.tscn"),
	preload("res://entities/goma-rosa.tscn"),
	preload("res://entities/goma-verde.tscn")
]
@export var max_inimigos_vivos: int = 12

@export_group("Goma Rei")
@export var cena_goma_rei: PackedScene = preload("res://entities/goma-rei.tscn")
## Segundos (desde o início) em que a Goma Rei começa a aparecer.
@export var rei_inicio: float = 30.0
## Intervalo entre cada Goma Rei depois do início.
@export var rei_intervalo: float = 5.0

@export_group("Introdução")
@export var duracao_intro: float = 5.0
@export var texto_intro: String = "Sobreviva um minuto"

@export_group("Tempo")
@export var duracao_total: float = 60.0
## Intervalo entre spawns no começo do evento.
@export var intervalo_spawn_inicial: float = 2.0
## Intervalo entre spawns no final do evento (mais rápido).
@export var intervalo_spawn_final: float = 0.4
@export var variacao_intervalo: float = 0.15
## Se true, depois que o tempo acaba o evento não reinicia ao entrar de novo.
@export var so_uma_vez: bool = true

@export_group("Blocos")
## Nós (Esquerdo / Direito) que têm AnimatedSprite2D dentro. Cada sprite
## ganha uma colisão, criada por código, que só fica ativa durante o evento.
## Os nomes precisam bater com a cena (o Godot diferencia maiúsculas).
@export var blocos: Array[NodePath] = [^"Esquerdo", ^"Direito"]
## Camada de física dos blocos. Use a mesma do chão, para o jogador colidir.
@export_flags_2d_physics var camada_blocos: int = 1

@export_group("Posição")
@export var variacao_x: float = 24.0
## Não spawna em pontos mais perto que isso do jogador (0 desativa).
@export var distancia_minima_jogador: float = 80.0

@onready var label_timer: Node2D = $"../HudTimer"

const GRUPO_JOGADOR := "player"
const GRUPO_INIMIGOS := "inimigos_evento"

var timer_intro: Timer
var timer_duracao: Timer
var timer_spawn: Timer
var timer_rei_inicio: Timer
var timer_rei: Timer
var inimigos_vivos: int = 0
var evento_ativo: bool = false
var em_intro: bool = false
var concluido: bool = false
var jogador_na_area: bool = false
var formas_blocos: Array[CollisionShape2D] = []


func _ready() -> void:
	timer_intro = _criar_timer(true, _on_intro_timeout)
	timer_duracao = _criar_timer(true, _on_duracao_timeout)
	timer_spawn = _criar_timer(true, _on_spawn_timeout)
	timer_rei_inicio = _criar_timer(true, _on_rei_inicio_timeout)
	timer_rei = _criar_timer(false, _on_rei_timeout)

	if label_timer:
		label_timer.mostrar(false)

	_criar_colisoes_blocos()
	_definir_colisao_blocos(false)

	var jogador := get_tree().get_first_node_in_group(GRUPO_JOGADOR)
	if jogador and jogador.has_signal("morreu"):
		jogador.morreu.connect(_on_jogador_morreu)


func _criar_timer(one_shot: bool, callback: Callable) -> Timer:
	var t := Timer.new()
	t.one_shot = one_shot
	t.timeout.connect(callback)
	add_child(t)
	return t


func _process(_delta: float) -> void:
	if not evento_ativo or label_timer == null:
		return
	var t := int(ceil(duracao_total if em_intro else timer_duracao.time_left))
	label_timer.set_texto("%d:%02d" % [floori(t / 60.0), t % 60])


# =========================================================
# ENTRADA / SAÍDA DO JOGADOR
# =========================================================

## Chamado pelo startspawn.gd quando o jogador entra no Area2D.
func jogador_entrou() -> void:
	jogador_na_area = true

	if evento_ativo:
		# Retoma de onde parou.
		_pausar_timers(false)
		if label_timer:
			label_timer.set_pausado(false)
			if em_intro:
				label_timer.mostrar_aviso(texto_intro)
	elif not (concluido and so_uma_vez):
		_iniciar_evento()


## Chamado pelo startspawn.gd quando o jogador sai do Area2D.
func jogador_saiu() -> void:
	jogador_na_area = false

	if evento_ativo:
		_pausar_timers(true)
		if label_timer:
			label_timer.set_pausado(true)
			label_timer.esconder_aviso()


func _pausar_timers(valor: bool) -> void:
	timer_intro.paused = valor
	timer_duracao.paused = valor
	timer_spawn.paused = valor
	timer_rei_inicio.paused = valor
	timer_rei.paused = valor


func _iniciar_evento() -> void:
	if cenas_inimigos.is_empty():
		push_warning("Spawner: 'cenas_inimigos' está vazio.")
		return
	if pegar_pontos().is_empty():
		push_warning("Spawner: nenhum Marker2D encontrado dentro do Portal.")
		return

	evento_ativo = true
	em_intro = true
	_pausar_timers(false)
	timer_rei.stop()
	_definir_colisao_blocos(true)

	if label_timer:
		label_timer.set_pausado(false)
		label_timer.mostrar_aviso(texto_intro)
		label_timer.mostrar(true)

	timer_intro.start(duracao_intro)


## Fim da introdução: começam os timers de verdade.
func _on_intro_timeout() -> void:
	em_intro = false
	if label_timer:
		label_timer.esconder_aviso()
	timer_duracao.start(duracao_total)
	timer_rei_inicio.start(rei_inicio)
	agendar_proximo_spawn()


func _mostrar_label(valor: bool) -> void:
	if label_timer:
		label_timer.mostrar(valor)


# =========================================================
# MORTE DO JOGADOR
# =========================================================

func _on_jogador_morreu() -> void:
	evento_ativo = false
	em_intro = false
	timer_intro.stop()
	timer_duracao.stop()
	timer_spawn.stop()
	timer_rei_inicio.stop()
	timer_rei.stop()
	_mostrar_label(false)
	_definir_colisao_blocos(false)


# =========================================================
# SPAWN DOS INIMIGOS NORMAIS (acelera com o tempo)
# =========================================================

## Intervalo atual: vai de "inicial" até "final" conforme o tempo passa.
func intervalo_atual() -> float:
	var progresso := 1.0 - (timer_duracao.time_left / duracao_total)
	return lerp(intervalo_spawn_inicial, intervalo_spawn_final, clampf(progresso, 0.0, 1.0))


func agendar_proximo_spawn() -> void:
	var espera := intervalo_atual() + randf_range(-variacao_intervalo, variacao_intervalo)
	timer_spawn.start(max(0.1, espera))


func _on_spawn_timeout() -> void:
	if not evento_ativo:
		return
	if inimigos_vivos < max_inimigos_vivos:
		spawnar()
	agendar_proximo_spawn()


func spawnar() -> void:
	var inimigo := _spawnar_cena(cenas_inimigos.pick_random())
	if inimigo == null:
		return
	inimigos_vivos += 1
	inimigo.tree_exited.connect(_on_inimigo_saiu)


func _on_inimigo_saiu() -> void:
	inimigos_vivos = max(0, inimigos_vivos - 1)


# =========================================================
# GOMA REI
# =========================================================

## Chega nos 30s: spawna a primeira e começa o ciclo de 5s.
func _on_rei_inicio_timeout() -> void:
	if not evento_ativo:
		return
	spawnar_rei()
	timer_rei.start(rei_intervalo)


func _on_rei_timeout() -> void:
	if not evento_ativo:
		return
	spawnar_rei()


## A Goma Rei não conta no limite de inimigos vivos.
func spawnar_rei() -> void:
	_spawnar_cena(cena_goma_rei)


# =========================================================
# UTILIDADES
# =========================================================

## Instancia a cena em um ponto aleatório livre e devolve o nó.
func _spawnar_cena(cena: PackedScene) -> Node2D:
	if cena == null:
		return null

	var pontos := pegar_pontos_livres()
	if pontos.is_empty():
		pontos = pegar_pontos()
	if pontos.is_empty():
		return null

	var ponto: Node2D = pontos.pick_random()
	var inimigo := cena.instantiate() as Node2D
	inimigo.add_to_group(GRUPO_INIMIGOS)
	get_parent().add_child(inimigo)
	inimigo.global_position = ponto.global_position + Vector2(randf_range(-variacao_x, variacao_x), 0)
	# Conta no momento da morte (sinal "eliminada"). Se o inimigo não tiver
	# esse sinal, conta quando ele sai da cena.
	if inimigo.has_signal("eliminada"):
		inimigo.connect("eliminada", _on_inimigo_eliminado, CONNECT_ONE_SHOT)
	else:
		inimigo.tree_exited.connect(_on_inimigo_eliminado, CONNECT_ONE_SHOT)
	return inimigo


## Conta a eliminação só enquanto o evento está rodando.
## (Na vitória, na morte do jogador e no reinício da cena não conta.)
func _on_inimigo_eliminado() -> void:
	if not evento_ativo or not is_inside_tree() or is_queued_for_deletion():
		return
	if label_timer and is_instance_valid(label_timer):
		label_timer.adicionar_eliminado()


## Cria uma colisão (StaticBody2D + retângulo do tamanho do quadro) para cada
## AnimatedSprite2D dentro dos nós listados em "blocos". Começam desligadas.
func _criar_colisoes_blocos() -> void:
	formas_blocos.clear()

	for caminho in blocos:
		var bloco := get_node_or_null(caminho)
		if bloco == null:
			push_warning("Spawner: bloco '%s' não encontrado." % caminho)
			continue

		for no in bloco.find_children("*", "AnimatedSprite2D", true, false):
			var sprite := no as AnimatedSprite2D
			if sprite.sprite_frames == null:
				continue
			var textura := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
			if textura == null:
				continue

			var tamanho := textura.get_size()

			var forma := CollisionShape2D.new()
			var retangulo := RectangleShape2D.new()
			retangulo.size = tamanho
			forma.shape = retangulo
			forma.disabled = true
			# Centro do retângulo: na origem se "centered", senão no meio do quadro.
			forma.position = sprite.offset + (Vector2.ZERO if sprite.centered else tamanho / 2.0)

			var corpo := StaticBody2D.new()
			corpo.collision_layer = camada_blocos
			corpo.collision_mask = 0
			corpo.add_child(forma)
			# Filho do sprite: herda posição, escala e rotação dele.
			sprite.add_child(corpo)

			formas_blocos.append(forma)


## Liga/desliga as colisões criadas para os blocos.
func _definir_colisao_blocos(ativa: bool) -> void:
	for forma in formas_blocos:
		if is_instance_valid(forma):
			forma.set_deferred("disabled", not ativa)


## Todos os Marker2D dentro do Portal (esquerdo, direito, etc.).
func pegar_pontos() -> Array[Node2D]:
	var pontos: Array[Node2D] = []
	for no in find_children("*", "Marker2D", true, false):
		pontos.append(no as Node2D)
	return pontos


func pegar_pontos_livres() -> Array[Node2D]:
	var pontos := pegar_pontos()
	if distancia_minima_jogador <= 0.0:
		return pontos

	var jogador := get_tree().get_first_node_in_group(GRUPO_JOGADOR) as Node2D
	if jogador == null:
		return pontos

	var livres: Array[Node2D] = []
	for ponto in pontos:
		if ponto.global_position.distance_to(jogador.global_position) >= distancia_minima_jogador:
			livres.append(ponto)
	return livres


# =========================================================
# FIM DO TEMPO (VITÓRIA)
# =========================================================

func _on_duracao_timeout() -> void:
	evento_ativo = false
	concluido = true
	timer_spawn.stop()
	timer_rei_inicio.stop()
	timer_rei.stop()
	_mostrar_label(false)
	_definir_colisao_blocos(false)

	_matar_todos_inimigos()

	if label_timer:
		label_timer.mostrar_vitoria()

	tempo_esgotado.emit()


## Mata todos os inimigos criados pelo evento (normais e Gomas Rei).
func _matar_todos_inimigos() -> void:
	for inimigo in get_tree().get_nodes_in_group(GRUPO_INIMIGOS):
		if not is_instance_valid(inimigo):
			continue
		if inimigo.has_method("morrer"):
			inimigo.morrer()
		else:
			inimigo.queue_free()
