# Solver: FOCO EM PONTOS
source("R/data_processing.R")
source("R/optimization_logic.R")
source("R/visualization_logic.R")

ORCAMENTO <- 115.0
cat("🚀 Iniciando Otimização para PONTOS (Mando de Campo + Risco Defensivo)
")

dados_raw <- fetch_cartola_data()
df_atletas <- process_atletas(dados_raw, process_clubes(dados_raw))

esquemas <- list("4-3-3" = c(Goleiro=1, Lateral=2, Zagueiro=2, Meia=3, Atacante=3, Técnico=1))
res <- resolver_otimizacao(df_atletas, ORCAMENTO, esquemas[["4-3-3"]], "expectativa_pontos")

if(res$status == "ok") {
  df_atletas$escalado <- as.vector(res$vetor)
  meu_time <- df_atletas %>% filter(escalado == 1)
  
  # Lógica de Capitão Inteligente (Prioridade: Atacante > Meia, Mandante)
  meu_time <- meu_time %>%
    mutate(peso_capitao = case_when(
      posicao == "Atacante" & is_mandante ~ media * 2,
      posicao == "Atacante" ~ media * 1.5,
      posicao == "Meia" & is_mandante ~ media * 1.3,
      TRUE ~ media
    ))
  
  id_capitao <- meu_time$id[which.max(meu_time$peso_capitao)]
  meu_time <- meu_time %>% mutate(is_capitao = (id == id_capitao))
  
  cat("
✅ Time para PONTOS escalado com sucesso!
")
  print(meu_time %>% select(posicao, nome, clube, preco, media))
  
  p <- plot_time(meu_time, "4-3-3 (Foco Pontos)", sum(meu_time$preco), res$valor)
  ggsave("output/time_pontos.png", p, width = 10, height = 7)
}
