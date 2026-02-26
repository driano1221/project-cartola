library(dplyr)

CACHE_PATH <- "data/historico_rodadas.csv"

# Extrai o número da rodada da resposta da API.
# Ordem de prioridade:
#   1) campo rodada_atual ou rodada no corpo principal da resposta
#   2) endpoint /mercado/status (retorna rodada_id explicitamente)
#   3) NA — não salva o cache se a rodada for desconhecida
get_rodada_id <- function(cartola_raw) {
  if (!is.null(cartola_raw$rodada_atual) && !is.na(cartola_raw$rodada_atual))
    return(as.integer(cartola_raw$rodada_atual))
  if (!is.null(cartola_raw$rodada) && !is.na(cartola_raw$rodada))
    return(as.integer(cartola_raw$rodada))

  # Tenta o endpoint de status do mercado
  status <- tryCatch({
    resp <- httr::GET(
      "https://api.cartola.globo.com/mercado/status",
      httr::user_agent("Mozilla/5.0"),
      httr::timeout(10)
    )
    if (!httr::http_error(resp))
      jsonlite::fromJSON(httr::content(resp, as = "text", encoding = "UTF-8"))
    else NULL
  }, error = function(e) NULL)

  if (!is.null(status$rodada_atual)) return(as.integer(status$rodada_atual))
  if (!is.null(status$rodada_id))    return(as.integer(status$rodada_id))
  if (!is.null(status$rodada))       return(as.integer(status$rodada))

  # Rodada desconhecida — não salva para evitar dados com rótulo errado
  message("[cache] AVISO: nao foi possivel determinar a rodada atual. Snapshot nao salvo.")
  return(NA_integer_)
}

# Salva um snapshot dos dados brutos da rodada atual no cache local.
# Deve ser chamado logo após fetch_cartola_data(), antes de process_atletas().
# O cache acumula snapshots rodada a rodada — os deltas entre rodadas consecutivas
# permitem reconstruir a pontuação real de cada atleta por jogo.
salvar_snapshot_rodada <- function(cartola_raw) {
  rodada_id <- get_rodada_id(cartola_raw)
  df        <- cartola_raw$atletas

  if (is.na(rodada_id)) return(invisible(NULL))

  if (is.null(df) || nrow(df) == 0) {
    message("[cache] Nenhum atleta na resposta — snapshot nao salvo.")
    return(invisible(NULL))
  }

  get_s <- function(col) {
    if (col %in% names(df)) { v <- df[[col]]; ifelse(is.na(v), 0, v) }
    else rep(0, nrow(df))
  }

  snapshot <- data.frame(
    atleta_id        = df$atleta_id,
    clube_id         = df$clube_id,
    rodada           = rodada_id,
    media_num        = get_s("media_num"),
    jogos_num        = get_s("jogos_num"),
    variacao_num     = get_s("variacao_num"),
    preco_num        = get_s("preco_num"),
    scout_G          = get_s("scout.G"),
    scout_GS         = get_s("scout.GS"),
    stringsAsFactors = FALSE
  )
  snapshot$pontos_acumulados <- snapshot$media_num * snapshot$jogos_num

  dir.create(dirname(CACHE_PATH), showWarnings = FALSE, recursive = TRUE)

  if (file.exists(CACHE_PATH)) {
    hist_df <- utils::read.csv(CACHE_PATH, stringsAsFactors = FALSE)
    if (rodada_id %in% hist_df$rodada) {
      message(sprintf("[cache] Rodada %d ja salva — ignorando.", rodada_id))
      return(invisible(rodada_id))
    }
    hist_df <- rbind(hist_df, snapshot)
  } else {
    hist_df <- snapshot
  }

  utils::write.csv(hist_df, CACHE_PATH, row.names = FALSE)
  message(sprintf("[cache] Rodada %d salva (%d atletas).", rodada_id, nrow(snapshot)))
  invisible(rodada_id)
}

# Carrega o histórico e calcula pontuação por rodada via delta entre snapshots consecutivos.
#
# Lógica de delta:
#   - media_num e jogos_num são acumulativos na temporada
#   - pontos_acumulados = media_num * jogos_num  (total de pontos na temporada)
#   - Quando jogos_num cresce em 1 entre duas rodadas, o atleta jogou
#   - pontos_rodada = pontos_acumulados_atual - pontos_acumulados_anterior
#
# Retorna data.frame: atleta_id, clube_id, rodada, pontos_rodada, gols_rodada, gs_rodada
# Retorna NULL se o cache não existir ou tiver menos de 2 rodadas.
carregar_historico_por_rodada <- function() {
  if (!file.exists(CACHE_PATH)) return(NULL)

  hist_df <- utils::read.csv(CACHE_PATH, stringsAsFactors = FALSE)
  if (nrow(hist_df) == 0 || length(unique(hist_df$rodada)) < 2) return(NULL)

  hist_df %>%
    arrange(atleta_id, rodada) %>%
    group_by(atleta_id) %>%
    mutate(
      jogos_delta   = jogos_num         - lag(jogos_num),
      pts_delta     = pontos_acumulados - lag(pontos_acumulados),
      gols_delta    = scout_G           - lag(scout_G),
      gs_delta      = scout_GS         - lag(scout_GS),
      # Registra pontuação apenas quando o atleta efetivamente jogou (jogos aumentou em 1)
      pontos_rodada = ifelse(!is.na(jogos_delta) & jogos_delta == 1L, pts_delta,  NA_real_),
      gols_rodada   = ifelse(!is.na(jogos_delta) & jogos_delta == 1L, gols_delta, NA_real_),
      gs_rodada     = ifelse(!is.na(jogos_delta) & jogos_delta == 1L, gs_delta,   NA_real_)
    ) %>%
    ungroup() %>%
    filter(!is.na(pontos_rodada)) %>%
    select(atleta_id, clube_id, rodada, pontos_rodada, gols_rodada, gs_rodada)
}

# Calcula desvio padrão e forma recente ponderada por atleta.
# n_recente: número de rodadas recentes com maior peso (pesos decrescentes c(5,4,3,2,1))
# Retorna data.frame: atleta_id, std_pontos, forma_recente
# Retorna NULL se sem dados.
calcular_stats_atleta <- function(historico, n_recente = 5L) {
  if (is.null(historico) || nrow(historico) == 0L) return(NULL)

  pesos <- rev(seq_len(n_recente))  # c(5,4,3,2,1) — mais recente tem maior peso

  historico %>%
    group_by(atleta_id) %>%
    arrange(rodada, .by_group = TRUE) %>%
    summarise(
      std_pontos     = sd(pontos_rodada, na.rm = TRUE),
      n_rodadas_hist = n(),
      forma_recente  = {
        pts <- tail(pontos_rodada, n_recente)
        w   <- tail(pesos, length(pts))
        weighted.mean(pts, w)
      },
      .groups = "drop"
    ) %>%
    filter(n_rodadas_hist >= 2L) %>%   # stddev requer mínimo 2 observações
    mutate(std_pontos = ifelse(is.na(std_pontos), 0, std_pontos)) %>%
    select(atleta_id, std_pontos, forma_recente)
}

# Estima o parâmetro λ (gols marcados por partida) de cada clube.
# Usado pelo modelo de Poisson para calcular P(SG).
# Retorna data.frame: clube_id, lambda_gols
calcular_lambda_gols_clube <- function(historico, n_rodadas = 5L) {
  if (is.null(historico) || nrow(historico) == 0L) return(NULL)

  rodadas_recentes <- sort(unique(historico$rodada), decreasing = TRUE)
  rodadas_recentes <- rodadas_recentes[seq_len(min(n_rodadas, length(rodadas_recentes)))]

  historico %>%
    filter(rodada %in% rodadas_recentes, !is.na(gols_rodada)) %>%
    group_by(clube_id, rodada) %>%
    summarise(gols_partida = sum(gols_rodada, na.rm = TRUE), .groups = "drop") %>%
    group_by(clube_id) %>%
    summarise(lambda_gols = mean(gols_partida, na.rm = TRUE), .groups = "drop")
}
