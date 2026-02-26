# Modelo de Poisson para Probabilidade de Jogo Sem Gol (P(SG))
#
# Fundamento matemático:
#   Número de gols de uma equipe por jogo segue distribuição de Poisson com parâmetro λ.
#   P(SG | adversário j) = P(X = 0) = e^(-λ_j)
#   λ_j = média de gols marcados pelo clube j nas últimas n_rodadas rodadas (cache local)
#
# λ padrão = 1.2 ≈ média histórica da Série A (~1.1–1.3 gols/time/jogo).
# Isso dá P(SG) ≈ 0.30, alinhado com dados empíricos do Brasileirão.
#
# Quando o cache não tem dados suficientes, todos os clubes recebem λ = 1.2,
# resultando em prob_sg = 0.30 para todos — ajuste neutro (sem viés).

LAMBDA_SG_DEFAULT <- 1.2

# Calcula P(SG) para cada clube da rodada com base no λ do adversário.
#
# mapa_adv : data.frame com colunas clube_id e adversario_id
#            (subset de distinct(clube_id, adversario_id) de process_atletas)
# historico : saída de carregar_historico_por_rodada() — pode ser NULL
#
# Retorna data.frame: clube_id, prob_sg
calcular_prob_sg_por_clube <- function(mapa_adv, historico) {
  if (is.null(mapa_adv) || nrow(mapa_adv) == 0) {
    return(data.frame(clube_id = integer(0), prob_sg = numeric(0)))
  }

  lambda_df <- calcular_lambda_gols_clube(historico)

  if (is.null(lambda_df)) {
    lambda_df <- data.frame(clube_id = integer(0), lambda_gols = numeric(0))
  }

  mapa_adv %>%
    dplyr::left_join(lambda_df, by = c("adversario_id" = "clube_id")) %>%
    dplyr::mutate(
      # Clubes sem histórico recebem λ padrão → ajuste neutro
      lambda_gols = ifelse(is.na(lambda_gols), LAMBDA_SG_DEFAULT, lambda_gols),
      prob_sg     = exp(-lambda_gols)
    ) %>%
    dplyr::select(clube_id, prob_sg) %>%
    dplyr::distinct(clube_id, .keep_all = TRUE)
}
