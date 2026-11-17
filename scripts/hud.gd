# hud.gd
extends Node2D

@onready var label_timer: Label = $HudTimer/LabelTimer

const COR_NORMAL := Color.WHITE
const COR_PAUSADO := Color(0.5, 0.5, 0.5, 1.0)

## Tempo entre a morte e a tela "Você morreu" (para ver a animação).
const ATRASO_TELA_MORTE := 1.0

## Duração do fade-out do aviso (texto + fundo escurecido).
const DURACAO_FADE_AVISO := 0.6

var raiz_aviso: Control
var label_aviso: Label
var tween_aviso: Tween
var tela_morte: CanvasLayer
var tela_vitoria: CanvasLayer
var jogo_encerrado: bool = false
var label_contador: Label
var eliminados: int = 0
## O spawner quer o timer visível? (controlado por mostrar())
var timer_desejado: bool = false
## O aviso "Sobreviva..." está na tela? Enquanto estiver, timer e contador somem.
var aviso_ativo: bool = false


func _ready() -> void:
	_estilizar_label()
	_criar_contador()
	_criar_aviso()
	tela_morte = _criar_tela_final("Você morreu")
	tela_vitoria = _criar_tela_final("Você venceu!")

	var jogador := get_tree().get_first_node_in_group("player")
	if jogador and jogador.has_signal("morreu"):
		jogador.morreu.connect(_on_jogador_morreu)


func _config(tamanho: int) -> LabelSettings:
	var cfg := LabelSettings.new()
	cfg.font_size = tamanho
	cfg.font_color = Color.WHITE
	cfg.outline_size = 8
	cfg.outline_color = Color.BLACK
	return cfg


func _estilizar_label() -> void:
	label_timer.label_settings = _config(18)
	label_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_timer.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label_timer.position.y = 0


# =========================================================
# TIMER
# =========================================================

func set_texto(t: String) -> void:
	label_timer.text = t


func mostrar(valor: bool) -> void:
	timer_desejado = valor
	_atualizar_visibilidade()


## Timer e contador só aparecem quando o aviso NÃO está na tela.
func _atualizar_visibilidade() -> void:
	$HudTimer.visible = timer_desejado and not aviso_ativo
	if label_contador:
		label_contador.visible = not aviso_ativo


## true = cinza (parado), false = cor normal.
func set_pausado(valor: bool) -> void:
	label_timer.modulate = COR_PAUSADO if valor else COR_NORMAL


# =========================================================
# CONTADOR DE INIMIGOS ELIMINADOS (canto superior esquerdo, só o número)
# =========================================================

func _criar_contador() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 5
	add_child(camada)

	label_contador = Label.new()
	label_contador.label_settings = _config(14)
	label_contador.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label_contador.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label_contador.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label_contador.position = Vector2(8, 6)
	label_contador.mouse_filter = Control.MOUSE_FILTER_IGNORE
	camada.add_child(label_contador)

	_atualizar_contador()


func _atualizar_contador() -> void:
	label_contador.text = str(eliminados)


## Chamado pelo spawner toda vez que um inimigo é eliminado.
func adicionar_eliminado() -> void:
	if jogo_encerrado:
		return
	eliminados += 1
	_atualizar_contador()


# =========================================================
# AVISO ("Sobreviva um minuto") com fundo escurecido
# =========================================================

func _criar_aviso() -> void:
	var camada := CanvasLayer.new()
	camada.layer = 10
	add_child(camada)

	# Raiz do aviso: o fade é aplicado nela, então afeta fundo e texto juntos.
	raiz_aviso = Control.new()
	raiz_aviso.set_anchors_preset(Control.PRESET_FULL_RECT)
	raiz_aviso.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz_aviso.visible = false
	camada.add_child(raiz_aviso)

	# Fundo escurecido (mesmo das telas finais)
	var fundo := ColorRect.new()
	fundo.color = Color(0, 0, 0, 0.6)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	fundo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	raiz_aviso.add_child(fundo)

	label_aviso = Label.new()
	label_aviso.label_settings = _config(14)
	label_aviso.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_aviso.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label_aviso.set_anchors_preset(Control.PRESET_FULL_RECT)
	label_aviso.offset_bottom = -30
	raiz_aviso.add_child(label_aviso)


func mostrar_aviso(texto: String) -> void:
	if tween_aviso:
		tween_aviso.kill()
	label_aviso.text = texto
	raiz_aviso.modulate.a = 1.0
	raiz_aviso.visible = true
	aviso_ativo = true
	_atualizar_visibilidade()


## Some com fade-out. Use instantaneo = true para esconder na hora.
## Timer e contador voltam a aparecer assim que o aviso começa a sumir.
func esconder_aviso(instantaneo: bool = false) -> void:
	aviso_ativo = false
	_atualizar_visibilidade()

	if tween_aviso:
		tween_aviso.kill()

	if instantaneo or not raiz_aviso.visible:
		raiz_aviso.visible = false
		return

	tween_aviso = create_tween()
	tween_aviso.tween_property(raiz_aviso, "modulate:a", 0.0, DURACAO_FADE_AVISO)
	tween_aviso.tween_callback(func(): raiz_aviso.visible = false)


# =========================================================
# TELAS FINAIS (morte / vitória)
# =========================================================

## Cria uma tela escurecida com um título e o botão "Reiniciar".
func _criar_tela_final(texto: String) -> CanvasLayer:
	var tela := CanvasLayer.new()
	tela.layer = 20
	tela.visible = false
	add_child(tela)

	# Fundo escurecido (também bloqueia cliques no jogo)
	var fundo := ColorRect.new()
	fundo.color = Color(0, 0, 0, 0.6)
	fundo.set_anchors_preset(Control.PRESET_FULL_RECT)
	tela.add_child(fundo)

	var centro := CenterContainer.new()
	centro.set_anchors_preset(Control.PRESET_FULL_RECT)
	tela.add_child(centro)

	var caixa := VBoxContainer.new()
	caixa.add_theme_constant_override("separation", 16)
	centro.add_child(caixa)

	var titulo := Label.new()
	titulo.text = texto
	titulo.label_settings = _config(36)
	titulo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caixa.add_child(titulo)

	var botao := Button.new()
	botao.text = "Reiniciar"
	botao.custom_minimum_size = Vector2(140, 40)
	botao.pressed.connect(_on_reiniciar)
	caixa.add_child(botao)

	return tela


## Chamado pelo spawner quando o tempo acaba.
func mostrar_vitoria() -> void:
	if jogo_encerrado:
		return
	jogo_encerrado = true
	esconder_aviso(true)
	tela_vitoria.visible = true


func _on_jogador_morreu() -> void:
	if jogo_encerrado:
		return
	jogo_encerrado = true
	esconder_aviso(true)
	await get_tree().create_timer(ATRASO_TELA_MORTE).timeout
	tela_morte.visible = true


func _on_reiniciar() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
