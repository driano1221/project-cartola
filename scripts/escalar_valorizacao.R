# Solver: FOCO EM VALORIZAÇÃO
source("R/data_processing.R")
source("R/optimization_logic.R")
source("R/visualization_logic.R")

ORCAMENTO <- 115.0
cat("💰 Iniciando Otimização para VALORIZAÇÃO (Ficar Rico)
")

dados_raw  <- fetch_cartola_data()
salvar_snapshot_rodada(dados_raw)
df_atletas <- process_atletas(dados_raw, process_clubes(dados_raw))

# Prioriza jogadores com valorização quase certa (expectativa >= MPV oficial da API).
# Se o pool filtrado for pequeno demais para preencher uma formação, usa todos os atletas.
df_otimizar <- df_atletas %>% filter(valoriza_provavel)
MIN_POOL    <- 40  # minimo de atletas para garantir viabilidade da otimizacao
if (nrow(df_otimizar) < MIN_POOL) {
  cat(sprintf("   ℹ️  Pool 'valoriza_provavel' (%d atletas) muito pequeno — usando todos os atletas.\n",
              nrow(df_otimizar)))
  df_otimizar <- df_atletas
} else {
  cat(sprintf("   ✅ Otimizando sobre %d atletas com valorização provável (MPV disponível).\n",
              nrow(df_otimizar)))
}

# Usamos um esquema 4-4-2 que costuma ter meias mais baratos para valorizar
esquemas <- list("4-4-2" = c(Goleiro=1, Lateral=2, Zagueiro=2, Meia=4, Atacante=2, Técnico=1))
res <- resolver_otimizacao(df_otimizar, ORCAMENTO, esquemas[["4-4-2"]], "potencial_valorizacao")

if(res$status == "ok") {
  df_otimizar$escalado <- as.vector(res$vetor)
  meu_time <- df_otimizar %>% filter(escalado == 1)
  
  # Capitão: maior expectativa_pontos excluindo Técnico
  id_capitao <- meu_time$id[which.max(ifelse(meu_time$posicao == "Técnico", -99, meu_time$expectativa_pontos))]
  meu_time   <- meu_time %>% mutate(is_capitao = (id == id_capitao))
  
  cat("
✅ Time para VALORIZAÇÃO escalado com sucesso!
")
  print(meu_time %>% select(posicao, nome, clube, preco, media, min_val, potencial_valorizacao, valoriza_provavel))
  
  dir.create("output", showWarnings = FALSE, recursive = TRUE)
  p <- plot_time(meu_time, "4-4-2 (Foco Valorização)", sum(meu_time$preco), sum(meu_time$media))
  ggsave("output/time_valorizacao.png", p, width = 10, height = 7)
}
