# 🏟️ Project Cartola: Inteligência Analítica e Otimização para Cartola FC

O **Project Cartola** é um ecossistema de Data Science e Pesquisa Operacional desenvolvido em R para dominar as ligas do Cartola FC. Ele utiliza **Programação Linear Inteira Mista (MILP)** para resolver o clássico "Problema da Mochila" aplicado ao futebol, permitindo escalações otimizadas para dois objetivos distintos: **Performance Máxima (Pontos)** e **Acúmulo de Patrimônio (Valorização)**.

---

## 🏗️ Arquitetura do Sistema

O projeto é modularizado para garantir escalabilidade e fácil manutenção:

*   **`R/data_processing.R`**: Motor de ETL (Extract, Transform, Load). Consome a API, trata scouts e calcula métricas derivadas.
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

### 3. Otimização "Bom e Barato" (Valorização)
Quando os dados oficiais de valorização estão ausentes, o sistema utiliza uma heurística de custo-benefício:
$$\text{Potencial} = (\text{Média} \times 1.5) - \text{Preço}$$
Isso força o solver a encontrar jogadores subvalorizados que têm alta probabilidade de explosão de preço.

---

## ➗ Modelagem Matemática

O problema de escalação é modelado como um problema de otimização linear:

**Função Objetivo:**
$$\text{Maximizar } Z = \sum_{i=1}^{n} P_i \cdot x_i$$
*Onde $P_i$ é a pontuação esperada (ou potencial de valorização) e $x_i$ é uma variável binária (1 se escalado, 0 caso contrário).*

**Restrições Principais:**
1.  **Orçamento:** $\sum_{i=1}^{n} C_i \cdot x_i \leq \text{Orçamento Máximo}$
2.  **Formação Tática:** $\sum x_{i, \text{posicao}} = K_{\text{posicao}}$
3.  **Limite de Grupo:** $\sum x_{i, \text{clube}} \leq 4$
4.  **Integridade:** $x_i \in \{0, 1\}$

---

## 📊 Dados e Variáveis

| Variável | Descrição | Fonte |
| :--- | :--- | :--- |
| `atleta_id` | Identificador único do jogador | API Globo |
| `preco_num` | Custo em Cartoletas | API Globo |
| `media_num` | Média de pontos por partida | API Globo |
| `scout.G/A/DS` | Gols, Assistências e Desarmes | API Globo |
| `is_mandante` | Flag de mando de campo | Tabela de Jogos |
| `escudo` | URL da imagem 60x60 do clube | CDN Globo |

---

## 🛠️ Stack Tecnológica

### Bibliotecas R (Dependencies)
*   `httr` & `jsonlite`: Comunicação com API e parse de JSON.
*   `dplyr` & `purrr`: Manipulação funcional de dados.
*   `CVXR`: Modelagem de otimização convexa.
*   `GLPK_MI`: Solver de alto desempenho para problemas inteiros.
*   `ggplot2` & `ggsoccer`: Renderização do campo de futebol.
*   `ggimage` & `ggrepel`: Plotagem de escudos e rótulos inteligentes.

### Fontes de Informação
*   **API Oficial:** `api.cartola.globo.com`
*   **Referência Técnica:** Repositório `caRtola` (Henrique Gomide).
*   **Estratégias:** Análise de probabilidade de SG e Mando de Campo (Chora API / ge.globo).

---

## 🚀 Como Executar

### Para Vencer a Rodada (Foco em Pontos)
Maximiza a pontuação esperada considerando mando de campo e risco defensivo.
```bash
Rscript scripts/escalar_pontos.R
```

### Para Ficar Rico (Foco em Valorização)
Prioriza jogadores "Bons e Baratos" para aumentar o patrimônio nas primeiras rodadas.
```bash
Rscript scripts/escalar_valorizacao.R
```

---
*Este projeto foi desenvolvido para fins acadêmicos e analíticos. O sucesso no Cartola FC depende de variáveis aleatórias inerentes ao esporte.*
