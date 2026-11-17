# Diário de Desenvolvimento (DEVLOG) - Bear Candy Game

## Aula 08 -- 07/10
**O que fiz:** Construção da fase de plataforma da doceria utilizando cinco `TileMapLayer` (`Map Background`, `Decoracao`, `Terreno`, `Paredes de fundo` e `Plataformas`) com tiles de 16×16, chão contínuo e paredes sólidas nas duas pontas do mapa, além de plataformas com colisão *one-way*. Criação do personagem bala de goma (`jogador.tscn`, um `CharacterBody2D`) com gravidade, pulo, corrida e *coyote time*, e de uma `Camera2D` (`camera.gd`) que segue o nó do grupo `player` com `limit_left = 0` e `limit_bottom = 208`. Configuração do projeto para pixel art (viewport 288×208, filtro Nearest, *stretch* `canvas_items` com escala inteira) e das ações de entrada (setas e A/D/W/S, `jump` no Espaço, atacar em J e K ou no clique esquerdo do mouse). Base reaproveitada de um projeto meu anterior.
**O que travou:** A câmera ficou travada no local ao invés de acompanhar o personagem.
**Como resolvi:** O problema era a posição do mapa e do personagem, que ficava fora dos limites da camera, então ela não se movia. Ajustei a posição do mapa e do personagem para ficar dentro dos limites.

## Aula 09 -- 21/10
**O que fiz:** Criação dos inimigos (`goma-azul`, `goma-laranja`, `goma-rosa` e `goma-verde`, todos `CharacterBody2D` no grupo `inimigos` com o script `gomas.gd`), que pulam em direção ao jogador, causam dano de contato pela `AreaDano` e atravessam as plataformas *one-way* para descer quando o jogador está abaixo, além da `goma-rei` (`goma_rei.gd`, 6 de vida). Criação do evento de horda no `Portal` (`spawner2.gd` e `start_spawn.gd`): ao entrar na área o jogador vê o aviso "Sobreviva um minuto", os timers rodam por 60 s e pausam se ele sai, o intervalo de spawn acelera de 2 s para 0,4 s com no máximo 12 gomas vivas, e a Goma Rei aparece a partir dos 30 s, a cada 5 s. Sistema de vida do jogador com 5 corações (`health_bar.gd`), estado HURT com invencibilidade de 1,5 s e piscar, e sinal `morreu`. HUD (`hud.tscn` e `hud.gd`) com cronômetro, contador de gomas eliminadas e telas "Você morreu" e "Você venceu!" com botão Reiniciar. Camadas de física: jogador na camada 2 e gomas na camada 3.
**O que travou:** A goma não dava dano de contato no jogador.
**Como resolvi:** A solução foi configurar corretamente as mascaras e layers do projeto, sendo elas world (1), jogador (2), inimigos (3) e plataformas (4)

## Aula 10 -- 28/10
**O que fiz:** Adição dos sprites de portais
**O que travou:** O timer não startava ao entrar na area
**Como resolvi:** Corrigi adicionando um script trigger, separado do script de lógica de spawn de inimigos
