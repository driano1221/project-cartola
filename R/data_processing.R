library(httr)
library(jsonlite)
library(dplyr)
library(purrr)

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

  df_posicoes <- process_posicoes(cartola_raw)
  partidas    <- cartola_raw$partidas
  mandantes   <- c(partidas$clube_casa_id)

  df_atletas <- cartola_raw$atletas %>%
    filter(status_id == 7) %>%
    left_join(df_clubes, by = "clube_id") %>%
    left_join(df_posicoes, by = "posicao_id") %>%
    mutate(
      preco    = ifelse(is.na(preco_num), 0, preco_num),
      media    = ifelse(is.na(media_num), 0, media_num),
      jogos    = ifelse(is.na(jogos_num), 0, jogos_num),
      variacao = ifelse(is.na(variacao_num), 0, variacao_num),
      # Minimo de pontos necessarios para valorizar nesta rodada (da API oficial)
      min_val  = get_col(., "minimo_para_valorizar"),

      is_mandante = clube_id %in% mandantes,

      # Fator Mando de Campo: +15% para mandantes, -10% para visitantes
      expectativa_pontos = ifelse(is_mandante, media * 1.15, media * 0.90),

      # Potencial de Valorizacao (hierarquia de 3 niveis):
      #   1) variacao_num real da API — melhor proxy quando disponivel (rodadas 2+)
      #   2) media - min_val — quanto o jogador deve superar o minimo (rodadas com MPV)
      #   3) heuristica "Bom e Barato" — fallback para rodada 1 sem historico
      potencial_valorizacao = ifelse(
        variacao != 0,
        variacao,
        ifelse(min_val > 0, media - min_val, (media * 1.5) - preco)
      ),

      # Flag: TRUE quando a expectativa de pontos ja supera o MPV — valorização quase certa
      valoriza_provavel = min_val > 0 & expectativa_pontos >= min_val,

      # Score de scouts da temporada usando os pesos oficiais do Cartola FC (2024+)
      # Permite calcular uma media baseada em scouts como alternativa/validacao da media_num
      pontos_scouts =
        get_col(., "scout.G")  *  8.0 +
        get_col(., "scout.A")  *  5.0 +
        get_col(., "scout.SG") *  5.0 +
        get_col(., "scout.DP") *  7.0 +
        get_col(., "scout.FT") *  3.0 +
        get_col(., "scout.DE") *  1.3 +
        get_col(., "scout.DS") *  1.5 +
        get_col(., "scout.FD") *  1.2 +
        get_col(., "scout.FF") *  0.8 +
        get_col(., "scout.FS") *  0.5 +
        get_col(., "scout.PS") *  1.0 +
        get_col(., "scout.GC") * (-3.0) +
        get_col(., "scout.CV") * (-3.0) +
        get_col(., "scout.GS") * (-1.0) +
        get_col(., "scout.CA") * (-1.0) +
        get_col(., "scout.PP") * (-4.0) +
        get_col(., "scout.FC") * (-0.3) +
        get_col(., "scout.I")  * (-0.1),

      # Media por jogo calculada a partir dos scouts (deve ser proxima de media_num)
      media_scouts = ifelse(jogos > 0, pontos_scouts / jogos, 0),

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

  df_atletas %>%
    select(
      id = atleta_id, nome = apelido, label, clube, clube_id,
      posicao, is_defesa, is_mandante,
      preco, media, media_scouts, variacao, min_val,
      expectativa_pontos, potencial_valorizacao, valoriza_provavel,
      escudo
    )
}
