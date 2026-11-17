# Diário de Desenvolvimento (DEVLOG) - Bear Candy Game

## Aula 08 -- 07/10
**O que fiz:** Construção da fase de plataforma da doceria utilizando cinco `TileMapLayer` (`Map Background`, `Decoracao`, `Terreno`, `Paredes de fundo` e `Plataformas`) com tiles de 16×16, chão contínuo e paredes sólidas nas duas pontas do mapa, além de plataformas com colisão *one-way*. Criação do personagem bala de goma (`jogador.tscn`, um `CharacterBody2D`) com gravidade, pulo, corrida e *coyote time*, e de uma `Camera2D` (`camera.gd`) que segue o nó do grupo `player` com `limit_left = 0` e `limit_bottom = 208`. Configuração do projeto para pixel art (viewport 288×208, filtro Nearest, *stretch* `canvas_items` com escala inteira) e das ações de entrada (setas e A/D/W/S, `jump` no Espaço, atacar em J e K ou no clique esquerdo do mouse). Base reaproveitada de um projeto meu anterior.
**O que travou:** A câmera ficou travada no local ao invés de acompanhar o personagem.
**Como resolvi:** O problema era a posição do mapa e do personagem, que ficava fora dos limites da camera, então ela não se movia. Ajustei a posição do mapa e do personagem para ficar dentro dos limites.
