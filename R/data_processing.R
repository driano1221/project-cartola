library(httr)
library(jsonlite)
library(dplyr)
library(purrr)

fetch_cartola_data <- function() {
  url <- "https://api.cartola.globo.com/atletas/mercado"
  resposta <- httr::GET(url, httr::user_agent("Mozilla/5.0"), httr::config(ssl_verifypeer = FALSE))
  jsonlite::fromJSON(httr::content(resposta, as = "text", encoding = "UTF-8"))
}

process_clubes <- function(cartola_raw) {
  clubes_list <- cartola_raw$clubes
  purrr::map_dfr(names(clubes_list), function(id_clube) {
    clube <- clubes_list[[id_clube]]
    data.frame(
      clube_id = as.integer(clube$id),
      clube = clube$abreviacao,
      clube_nome = clube$nome_fantasia,
      escudo = clube$escudos$`60x60`,
      stringsAsFactors = FALSE
    )
  })
}

process_atletas <- function(cartola_raw, df_clubes) {
  # Função auxiliar para pegar coluna se existir, senão retornar 0
  get_col <- function(df, column_name) {
    if (column_name %in% names(df)) {
      val <- df[[column_name]]
      return(ifelse(is.na(val), 0, val))
    } else {
      return(rep(0, nrow(df)))
    }
  }

  partidas <- cartola_raw$partidas
  mandantes <- c(partidas$clube_casa_id)
  
  df_atletas <- cartola_raw$atletas %>%
    filter(status_id == 7) %>% 
    left_join(df_clubes, by = "clube_id") %>%
    mutate(
      preco = ifelse(is.na(preco_num), 0, preco_num),
      media = ifelse(is.na(media_num), 0, media_num),
      min_val = get_col(., "minimo_para_valorizar"),
      jogos = ifelse(is.na(jogos_num), 0, jogos_num),
      is_mandante = clube_id %in% mandantes,
      
      # Fator Mando de Campo (+15% de expectativa para mandantes)
      expectativa_pontos = ifelse(is_mandante, media * 1.15, media * 0.90),
      
      # Índice de Valorização (Bom e Barato)
      # Se min_val for 0, usamos a relação entre média e preço para forçar a riqueza
      potencial_valorizacao = ifelse(min_val == 0, (media * 1.5) - preco, media - min_val),
      
      posicao = case_when(
        posicao_id == 1 ~ "Goleiro", posicao_id == 2 ~ "Lateral",
        posicao_id == 3 ~ "Zagueiro", posicao_id == 4 ~ "Meia",
        posicao_id == 5 ~ "Atacante", posicao_id == 6 ~ "Técnico"
      ),
      is_defesa = posicao %in% c("Goleiro", "Lateral", "Zagueiro")
    ) %>%
    filter(preco > 0) %>%
    select(id=atleta_id, nome=apelido, clube, clube_id, posicao, is_defesa, is_mandante, 
           preco, media, expectativa_pontos, potencial_valorizacao, escudo)
  
  return(df_atletas)
}
