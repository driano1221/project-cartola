library(httr)
library(jsonlite)
library(dplyr)
library(purrr)

source("R/cache_rodadas.R")
source("R/sg_model.R")

fetch_cartola_data <- function() {
  url <- "https://api.cartola.globo.com/atletas/mercado"

  resposta <- tryCatch(
    httr::GET(url, httr::user_agent("Mozilla/5.0"), httr::timeout(30)),
    error = function(e) stop(paste("Falha de rede ao acessar a API do Cartola:", e$message))
  )

  if (httr::http_error(resposta)) {
    stop(paste(
      "API retornou HTTP", httr::status_code(resposta),
      "- verifique se o mercado do Cartola esta aberto."
    ))
  }

  jsonlite::fromJSON(httr::content(resposta, as = "text", encoding = "UTF-8"))
}

# Extrai mapeamento de posicoes diretamente da API (sem hardcode)
process_posicoes <- function(cartola_raw) {
  posicoes_list <- cartola_raw$posicoes
  purrr::map_dfr(names(posicoes_list), function(id) {
    p <- posicoes_list[[id]]
    data.frame(posicao_id = as.integer(p$id), posicao = p$nome, stringsAsFactors = FALSE)
  })
}

process_clubes <- function(cartola_raw) {
  clubes_list <- cartola_raw$clubes
  purrr::map_dfr(names(clubes_list), function(id_clube) {
    clube <- clubes_list[[id_clube]]
    data.frame(
      clube_id      = as.integer(clube$id),
      clube         = clube$abreviacao,
      clube_nome    = clube$nome_fantasia,
      clube_apelido = clube$apelido,
      escudo        = clube$escudos$`60x60`,
      stringsAsFactors = FALSE
    )
  })
}

process_atletas <- function(cartola_raw, df_clubes) {
  get_col <- function(df, column_name) {
    if (column_name %in% names(df)) {
      val <- df[[column_name]]
      return(ifelse(is.na(val), 0, val))
    } else {
      return(rep(0, nrow(df)))
    }
  }

  df_posicoes  <- process_posicoes(cartola_raw)
  partidas     <- cartola_raw$partidas
  has_partidas <- !is.null(partidas) && is.data.frame(partidas) && nrow(partidas) > 0
  mandantes    <- if (has_partidas && "clube_casa_id" %in% names(partidas)) partidas$clube_casa_id else integer(0)

  # === PRIMEIRA PASSAGEM: ETL e cálculo de métricas base ===
  df_atletas <- cartola_raw$atletas %>%
    filter(status_id == 7) %>%
    left_join(df_clubes, by = "clube_id") %>%
    left_join(df_posicoes, by = "posicao_id") %>%
    mutate(
      preco    = ifelse(is.na(preco_num), 0, preco_num),
      media    = ifelse(is.na(media_num), 0, media_num),
      jogos    = ifelse(is.na(jogos_num), 0, jogos_num),
      variacao = ifelse(is.na(variacao_num), 0, variacao_num),
      # Minimo de pontos necessarios para valorizar nesta rodada (MPV oficial da API)
      min_val  = get_col(., "minimo_para_valorizar"),

      is_mandante = clube_id %in% mandantes,

      # Fator Mando de Campo: +15% para mandantes, -10% para visitantes
      expectativa_pontos = ifelse(is_mandante, media * 1.15, media * 0.90),

      # Potencial de Valorizacao (hierarquia de 3 niveis de precisao):
      #   1) variacao_num real da API — melhor estimativa (rodadas 2+)
      #   2) media - min_val — quanto supera o MPV oficial (quando disponivel)
      #   3) heuristica Bom e Barato — fallback para rodada 1 sem historico
      potencial_valorizacao = ifelse(
        variacao != 0,
        variacao,
        ifelse(min_val > 0, media - min_val, (media * 1.5) - preco)
      ),

      # Flag: TRUE quando a expectativa ja supera o MPV — valorizacao quase certa
      valoriza_provavel = min_val > 0 & expectativa_pontos >= min_val,

      # --- Scouts com pesos oficiais do Cartola FC 2024+ ---

      # Scouts "volateis": eventos raros de alto valor (gol, assist, SG, etc.)
      # Alta variancia: o jogador pode nao ocorrer nenhum em varias rodadas
      scouts_vol_pos =
        get_col(., "scout.G")  * 8.0 +
        get_col(., "scout.A")  * 5.0 +
        get_col(., "scout.SG") * 5.0 +
        get_col(., "scout.DP") * 7.0 +
        get_col(., "scout.FT") * 3.0,

      # Scouts "regulares": eventos frequentes de valor menor (DS, FS, FF, etc.)
      # Baixa variancia: jogadores ativos quase sempre acumulam alguns desses
      scouts_reg_pos =
        get_col(., "scout.DS") * 1.5 +
        get_col(., "scout.FS") * 0.5 +
        get_col(., "scout.FF") * 0.8 +
        get_col(., "scout.FD") * 1.2 +
        get_col(., "scout.DE") * 1.3 +
        get_col(., "scout.PS") * 1.0,

      # Score total acumulado na temporada (validacao cruzada da media_num)
      pontos_scouts =
        scouts_vol_pos + scouts_reg_pos +
        get_col(., "scout.GC") * (-3.0) +
        get_col(., "scout.CV") * (-3.0) +
        get_col(., "scout.GS") * (-1.0) +
        get_col(., "scout.CA") * (-1.0) +
        get_col(., "scout.PP") * (-4.0) +
        get_col(., "scout.FC") * (-0.3) +
        get_col(., "scout.I")  * (-0.1),

      # Media por jogo calculada a partir dos scouts (deve ser proxima de media_num)
      media_scouts = ifelse(jogos > 0, pontos_scouts / jogos, 0),

      # Consistencia: proporcao de pontos oriundos de scouts regulares (0 a 1).
      # 0 = altamente dependente de gols/assistencias (alta variancia, "apostador")
      # 1 = pontos vem de scouts pequenos frequentes (baixa variancia, "consistente")
      consistencia = ifelse(
        scouts_vol_pos + scouts_reg_pos > 0,
        scouts_reg_pos / (scouts_vol_pos + scouts_reg_pos),
        0
      ),

      is_defesa = posicao %in% c("Goleiro", "Lateral", "Zagueiro")
    ) %>%
    filter(preco > 0)

  # Label compacto para o campo visual (usa apelido_abreviado da API se disponivel)
  df_atletas$label <- if ("apelido_abreviado" %in% names(df_atletas)) {
    ab <- df_atletas$apelido_abreviado
    ifelse(!is.na(ab) & nchar(ab) > 0, ab, df_atletas$apelido)
  } else {
    df_atletas$apelido
  }

  # === SEGUNDA PASSAGEM: Ajuste de Expectativa por Força do Adversário ===
  #
  # Inspirado no CartolaAnalitico: o gol do atacante de time A é o mesmo evento
  # que penaliza o goleiro/zagueiro de time B (-1 GS). Escalá-los juntos cria
  # dependência negativa. A solução é reduzir a expectativa dos defensores
  # proporcionalmente à força do ataque adversário desta rodada.
  #
  # Mecanismo:
  #   forca_ataque_adversario_norm ∈ [0, 1]  (0 = ataque mais fraco, 1 = mais forte)
  #   penalidade_defensores = -25% quando adversario tem ataque maximo (norm = 1)
  #   penalidade_defensores =   0% quando adversario tem ataque minimo (norm = 0)
  #
  # O optimizer naturalmente evitara defensores que enfrentam ataques fortes,
  # priorizando defesas com maior probabilidade de SG.

  # Forca de ataque de cada clube = media da expectativa dos seus atacantes e meias
  forca_ataque <- df_atletas %>%
    filter(posicao %in% c("Atacante", "Meia")) %>%
    group_by(clube_id) %>%
    summarise(forca_ataque = mean(expectativa_pontos, na.rm = TRUE), .groups = "drop")

  # Normaliza para [0, 1] para escalar a penalidade de forma uniforme
  fa_min   <- min(forca_ataque$forca_ataque, na.rm = TRUE)
  fa_max   <- max(forca_ataque$forca_ataque, na.rm = TRUE)
  fa_range <- max(fa_max - fa_min, 0.01)
  forca_ataque <- forca_ataque %>%
    mutate(forca_ataque_norm = (forca_ataque - fa_min) / fa_range)

  # Mapa de adversarios desta rodada (bidirecional: casa<->visitante)
  # Tenta os dois nomes possiveis do campo "visitante" na API.
  # Se a API nao retornar partidas (fora de temporada / antes da rodada abrir),
  # usa mapa vazio — os ajustes de forca_adversario ficam neutros (0.5).
  if (has_partidas) {
    col_visitante <- intersect(c("clube_visitante_id", "clube_fora_id"), names(partidas))
    col_visitante <- if (length(col_visitante) > 0) col_visitante[1] else NA_character_
    if (!is.na(col_visitante)) {
      mapa_adv <- bind_rows(
        data.frame(clube_id = partidas$clube_casa_id,
                   adversario_id = partidas[[col_visitante]], stringsAsFactors = FALSE),
        data.frame(clube_id = partidas[[col_visitante]],
                   adversario_id = partidas$clube_casa_id, stringsAsFactors = FALSE)
      ) %>% distinct(clube_id, .keep_all = TRUE)
    } else {
      mapa_adv <- data.frame(clube_id = integer(0), adversario_id = integer(0))
    }
  } else {
    mapa_adv <- data.frame(clube_id = integer(0), adversario_id = integer(0))
  }

  # Junta: cada jogador sabe quem eh o adversario e qual a forca do ataque dele
  df_atletas <- df_atletas %>%
    left_join(mapa_adv, by = "clube_id") %>%
    left_join(
      forca_ataque %>%
        rename(adversario_id = clube_id,
               forca_ataque_adversario     = forca_ataque,
               forca_ataque_adversario_norm = forca_ataque_norm),
      by = "adversario_id"
    ) %>%
    mutate(
      forca_ataque_adversario      = ifelse(is.na(forca_ataque_adversario), 0,   forca_ataque_adversario),
      forca_ataque_adversario_norm = ifelse(is.na(forca_ataque_adversario_norm), 0.5, forca_ataque_adversario_norm),

      # Aplica penalidade de ate -25% na expectativa dos defensores vs ataques fortes
      expectativa_pontos = ifelse(
        is_defesa,
        expectativa_pontos * (1 - 0.25 * forca_ataque_adversario_norm),
        expectativa_pontos
      )
    )

  # === TERCEIRA PASSAGEM: Integração de Dados Históricos (quando disponíveis) ===
  #
  # Usa o cache local (data/historico_rodadas.csv) acumulado rodada a rodada para:
  #   forma_recente — média ponderada das últimas 5 rodadas (substitui media como base)
  #                   quando disponível, produz expectativa_pontos mais precisa
  #   std_pontos    — desvio padrão real das pontuações por rodada (mede risco/volatilidade)
  #   prob_sg       — P(adversário marcar 0 gols) via Poisson: e^(-λ)
  #                   ajusta expectativa de defensores/goleiros com base no confronto real
  #
  # Fallbacks automáticos quando o cache tem dados insuficientes (< 2 rodadas):
  #   forma_recente → media_num da API    (comportamento original)
  #   std_pontos    → 0                   (sem informação de risco)
  #   prob_sg       → e^(-1.2) ≈ 0.30    (λ médio histórico do Brasileirão — neutro)

  historico  <- carregar_historico_por_rodada()
  stats_hist <- calcular_stats_atleta(historico)

  # --- Forma recente e desvio padrão ---
  if (!is.null(stats_hist) && nrow(stats_hist) > 0) {
    df_atletas <- df_atletas %>%
      left_join(
        stats_hist %>% select(atleta_id, forma_recente, std_pontos),
        by = "atleta_id"
      ) %>%
      mutate(
        # Recalcula expectativa_pontos usando forma_recente como base quando disponível.
        # Reaplicamos os dois ajustes anteriores (mando + forca_norm) para consistência.
        expectativa_pontos = ifelse(
          !is.na(forma_recente),
          forma_recente *
            ifelse(is_mandante, 1.15, 0.90) *
            ifelse(is_defesa, 1 - 0.25 * forca_ataque_adversario_norm, 1),
          expectativa_pontos
        )
      )
  } else {
    df_atletas$forma_recente <- NA_real_
    df_atletas$std_pontos    <- NA_real_
  }
  # Fallback: forma_recente = media atual quando sem histórico
  df_atletas$forma_recente[is.na(df_atletas$forma_recente)] <-
    df_atletas$media[is.na(df_atletas$forma_recente)]
  df_atletas$std_pontos[is.na(df_atletas$std_pontos)] <- 0

  # --- Probabilidade de SG via modelo de Poisson ---
  # λ do adversário estimado das últimas 5 rodadas do cache.
  # Ajuste aditivo: (prob_sg - 0.30) × 5 pts
  #   prob_sg > 0.30 → adversário fraco → bônus (> 0)
  #   prob_sg < 0.30 → adversário forte → malus (< 0)
  # Quando sem histórico: todos têm prob_sg = 0.30 → ajuste = 0 (neutro, sem dupla-contagem)
  prob_sg_df <- calcular_prob_sg_por_clube(mapa_adv, historico)
  df_atletas <- df_atletas %>%
    left_join(prob_sg_df, by = "clube_id") %>%
    mutate(
      prob_sg = ifelse(is.na(prob_sg), exp(-1.2), prob_sg),
      # Bônus/malus de SG: máximo ±1.5 pt (prob_sg ∈ [0.10, 0.50] na prática)
      expectativa_pontos = ifelse(
        is_defesa,
        expectativa_pontos + (prob_sg - exp(-1.2)) * 5.0,
        expectativa_pontos
      )
    )

  # Recalcula valoriza_provavel com a expectativa final (após todas as passagens)
  df_atletas$valoriza_provavel <- df_atletas$min_val > 0 &
    df_atletas$expectativa_pontos >= df_atletas$min_val

  df_atletas %>%
    select(
      id = atleta_id, nome = apelido, label, clube, clube_id, clube_nome,
      adversario_id, forca_ataque_adversario,
      posicao, is_defesa, is_mandante,
      preco, media, media_scouts, variacao, min_val,
      expectativa_pontos, potencial_valorizacao, valoriza_provavel,
      forma_recente, std_pontos, prob_sg,
      consistencia, escudo
    )
}
