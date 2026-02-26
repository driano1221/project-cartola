# Solver: FOCO EM VALORIZAÇÃO
source("R/data_processing.R")
source("R/optimization_logic.R")
source("R/visualization_logic.R")

ORCAMENTO <- 115.0
cat("💰 Iniciando Otimização para VALORIZAÇÃO (Ficar Rico)
")

dados_raw <- fetch_cartola_data()
df_atletas <- process_atletas(dados_raw, process_clubes(dados_raw))

# Usamos um esquema 4-4-2 que costuma ter meias mais baratos para valorizar
esquemas <- list("4-4-2" = c(Goleiro=1, Lateral=2, Zagueiro=2, Meia=4, Atacante=2, Técnico=1))
res <- resolver_otimizacao(df_atletas, ORCAMENTO, esquemas[["4-4-2"]], "potencial_valorizacao")

if(res$status == "ok") {
  df_atletas$escalado <- as.vector(res$vetor)
  meu_time <- df_atletas %>% filter(escalado == 1)
  
  meu_time <- meu_time %>% mutate(is_capitao = (id == id[which.max(media)]))
  
  cat("
✅ Time para VALORIZAÇÃO escalado com sucesso!
")
  print(meu_time %>% select(posicao, nome, clube, preco, media, potencial_valorizacao))
  
  p <- plot_time(meu_time, "4-4-2 (Foco Valorização)", sum(meu_time$preco), sum(meu_time$media))
  ggsave("output/time_valorizacao.png", p, width = 10, height = 7)
}
