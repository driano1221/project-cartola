# 🏟️ Project Cartola: Inteligência Analítica e Otimização para Cartola FC

O **Project Cartola** é um ecossistema de Data Science e Pesquisa Operacional desenvolvido em R para dominar as ligas do Cartola FC. Ele utiliza **Programação Linear Inteira Mista (MILP)** para resolver o clássico "Problema da Mochila" aplicado ao futebol, permitindo escalações otimizadas para dois objetivos distintos: **Performance Máxima (Pontos)** e **Acúmulo de Patrimônio (Valorização)**.

---

## 🏗️ Arquitetura do Sistema

O projeto é modularizado para garantir escalabilidade e fácil manutenção:

*   **`R/data_processing.R`**: Motor de ETL (Extract, Transform, Load). Consome a API, calcula métricas derivadas e computa score de scouts com os pesos oficiais.
*   **`R/optimization_logic.R`**: O "cérebro" matemático. Define as variáveis de decisão, restrições e funções objetivo usando o framework `CVXR`.
*   **`R/visualization_logic.R`**: Camada de apresentação que traduz dados abstratos em um campo de futebol visual com escudos e posicionamento tático.
*   **`scripts/`**: Orquestradores de alto nível para execução rápida.

---

## 🧪 Estratégias e Inteligência de Jogo

O projeto não olha apenas para a média; ele aplica regras de especialistas e estatística avançada:

### 1. Fator Mando de Campo (Home Advantage)
Baseado em dados históricos que mostram que mandantes vencem ~50% das vezes, o script aplica um **multiplicador de 1.15x** na expectativa de pontos para jogadores que atuam em casa e **0.90x** para visitantes.

### 2. Gestão de Risco Defensivo (Anti-Stacking)
Para evitar que um único gol sofrido destrua a rodada, implementamos uma restrição matemática que limita a **no máximo 2 jogadores de defesa** (Goleiro, Lateral, Zagueiro) do mesmo clube.

### 3. Otimização por Valorização com MPV Oficial
O sistema usa o campo `minimo_para_valorizar` da API (MPV — Mínimo Para Valorizar) para identificar com alta precisão jogadores que vão valorizar. A hierarquia de cálculo do potencial é:

1. **`variacao_num` real da API** (melhor estimativa, rodadas 2+)
2. **`media - min_val`** quando o MPV está disponível (quanto o jogador supera o mínimo)
3. **Heurística Bom e Barato** `(média × 1.5) − preço` como fallback para rodada 1

O flag `valoriza_provavel` (`TRUE` quando `expectativa_pontos >= min_val`) é usado para filtrar o pool de jogadores antes da otimização, priorizando quem tem valorização quase certa.

### 4. Score de Scouts com Pesos Oficiais
Todos os scouts disponíveis na API são computados com os **pesos oficiais do Cartola FC (2024+)**:

| Scout | Descrição | Peso |
| :--- | :--- | :---: |
| G | Gol | +8,0 |
| A | Assistência | +5,0 |
| SG | Sem Gol | +5,0 |
| DP | Defesa de Pênalti | +7,0 |
| FT | Finalização na Trave | +3,0 |
| DS | Desarme | +1,5 |
| DE | Defesa (goleiro) | +1,3 |
| FD | Finalização Defendida | +1,2 |
| FF | Finalização para Fora | +0,8 |
| FS | Falta Sofrida | +0,5 |
| PS | Pênalti Sofrido | +1,0 |
| GC | Gol Contra | -3,0 |
| CV | Cartão Vermelho | -3,0 |
| GS | Gol Sofrido | -1,0 |
| CA | Cartão Amarelo | -1,0 |
| PP | Pênalti Perdido | -4,0 |
| FC | Falta Cometida | -0,3 |
| I | Impedimento | -0,1 |

Isso gera `media_scouts` (pontuação média baseada em scouts) como validação cruzada da `media_num` da API.

### 5. Seleção de Capitão Inteligente
O capitão recebe **multiplicador de 1,5x** na pontuação (positiva e negativa). O sistema prioriza atacantes mandantes como capitão, seguido de meias mandantes. Técnicos são excluídos automaticamente da seleção de capitão.

> ⚠️ **Atenção**: desde 2024 o multiplicador da braçadeira é **1,5x** (não mais 2x). Evite goleiros como capitão — cada gol sofrido vira **-1,5 pt** com a braçadeira.

---

## ➗ Modelagem Matemática

O problema de escalação é modelado como um problema de otimização linear:

**Função Objetivo:**
$$\text{Maximizar } Z = \sum_{i=1}^{n} P_i \cdot x_i$$
*Onde $P_i$ é a pontuação esperada (ou potencial de valorização) e $x_i$ é uma variável binária (1 se escalado, 0 caso contrário).*

**Restrições Principais:**
1.  **Orçamento:** $\sum_{i=1}^{n} C_i \cdot x_i \leq \text{Orçamento Máximo}$
2.  **Formação Tática:** $\sum x_{i, \text{posição}} = K_{\text{posição}}$
3.  **Limite de Grupo:** $\sum x_{i, \text{clube}} \leq 4$
4.  **Anti-Stacking Defensivo:** $\sum x_{i, \text{defesa\_clube}} \leq 2$
5.  **Integridade:** $x_i \in \{0, 1\}$

---

## 📊 Dados e Variáveis

| Variável | Descrição | Fonte |
| :--- | :--- | :--- |
| `atleta_id` | Identificador único do jogador | API Globo |
| `preco_num` | Custo em Cartoletas | API Globo |
| `media_num` | Média de pontos por partida | API Globo |
| `variacao_num` | Variação de preço na última rodada | API Globo |
| `minimo_para_valorizar` | Mínimo de pontos para valorizar nesta rodada | API Globo |
| `is_mandante` | Flag de mando de campo | Tabela de Jogos |
| `expectativa_pontos` | `media` ajustada pelo mando de campo | Calculada |
| `potencial_valorizacao` | Estimativa de valorização (3 níveis de precisão) | Calculada |
| `valoriza_provavel` | `TRUE` quando expectativa ≥ MPV | Calculada |
| `media_scouts` | Média calculada pelos scouts com pesos oficiais | Calculada |
| `escudo` | URL da imagem 60x60 do clube | CDN Globo |

---

## 🛠️ Stack Tecnológica

### Bibliotecas R (Dependencies)
*   `httr` & `jsonlite`: Comunicação com API e parse de JSON.
*   `dplyr` & `purrr`: Manipulação funcional de dados.
*   `CVXR`: Modelagem de otimização convexa.
*   `Rglpk` (`GLPK_MI`): Solver primário para problemas inteiros.
*   `ggplot2` & `ggsoccer`: Renderização do campo de futebol.
*   `ggimage` & `ggrepel`: Plotagem de escudos e rótulos inteligentes.

### Fontes de Informação
*   **API Oficial:** `api.cartola.globo.com`
*   **Referência Técnica:** Repositório `caRtola` (Henrique Gomide).
*   **Pesos dos Scouts:** Cartola FC Brasil / Documentação oficial 2024+.

---

## 🚀 Como Executar

### Para Vencer a Rodada (Foco em Pontos)
Maximiza a pontuação esperada considerando mando de campo e risco defensivo.
```bash
Rscript scripts/escalar_pontos.R
```

### Para Ficar Rico (Foco em Valorização)
Prioriza jogadores com `valoriza_provavel = TRUE` e alto potencial de valorização.
```bash
Rscript scripts/escalar_valorizacao.R
```

### Otimização Multi-Esquema (Melhor dos Dois Mundos)
Testa 5 formações táticas e seleciona automaticamente a que maximiza pontos.
```bash
Rscript scripts/executar_otimizacao.R
```

### Teste de Conectividade e Validação
Valida a conexão com a API e a integridade do pipeline antes de otimizar.
```bash
Rscript scripts/teste_inicial.R
```

---
*Este projeto foi desenvolvido para fins acadêmicos e analíticos. O sucesso no Cartola FC depende de variáveis aleatórias inerentes ao esporte.*
