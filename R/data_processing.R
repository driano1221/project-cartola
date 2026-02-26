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
      # variacao_num: variacao de preco real da API (positivo = valorizou)
      variacao = ifelse(is.na(variacao_num), 0, variacao_num),

      is_mandante = clube_id %in% mandantes,

      # Fator Mando de Campo: +15% para mandantes, -10% para visitantes
      expectativa_pontos = ifelse(is_mandante, media * 1.15, media * 0.90),

      # Potencial de Valorizacao:
      #   1) usa variacao_num real da API quando disponivel (melhor estimativa)
      #   2) cai para heuristica "Bom e Barato" na rodada 1 ou sem historico
      potencial_valorizacao = ifelse(
        variacao != 0,
        variacao,
        (media * 1.5) - preco
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

  df_atletas %>%
    select(
      id = atleta_id, nome = apelido, label, clube, clube_id,
      posicao, is_defesa, is_mandante,
      preco, media, variacao, expectativa_pontos, potencial_valorizacao,
      escudo
    )
}
