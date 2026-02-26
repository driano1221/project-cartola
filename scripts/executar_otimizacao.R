# Script Principal - Otimizador Cartola
source("R/data_processing.R")
source("R/optimization_logic.R")
source("R/visualization_logic.R")

# 1. Parâmetros
ORCAMENTO <- 120.0 # Altere aqui seu patrimônio

# 2. ETL
cat("📥 Buscando dados...
")
dados_raw <- fetch_cartola_data()
df_clubes <- process_clubes(dados_raw)
df_atletas <- process_atletas(dados_raw, df_clubes)

# 3. Otimização Multi-Esquema
cat("🧠 Otimizando...
")
esquemas <- get_esquemas()
melhor_res_global <- NULL
max_pts <- -1
melhor_nome_esq <- ""

for(nome in names(esquemas)) {
  res <- resolver_otimizacao(df_atletas, ORCAMENTO, nome, esquemas[[nome]])
  if(res$status == "ok" && res$valor > max_pts) {
    max_pts <- res$valor
    melhor_res_global <- res
    melhor_nome_esq <- nome
  }
}

# 4. Resultado Final
if(!is.null(melhor_res_global)) {
  df_atletas$escalado <- as.vector(melhor_res_global$vetor)
  meu_time <- df_atletas %>% filter(escalado == 1)
  
  # Capitão
  id_capitao <- meu_time$id[which.max(ifelse(meu_time$posicao=="Técnico", -99, meu_time$media))]
  meu_time <- meu_time %>% mutate(is_capitao = (id == id_capitao))
  
  pontos_totais <- sum(meu_time$media) + max(meu_time$media[meu_time$posicao != "Técnico"])
  
  cat("
✅ Melhor esquema encontrado:", melhor_nome_esq)
  cat("
💰 Custo total: C$", sum(meu_time$preco))
  cat("
🔥 Pontuação esperada:", pontos_totais, "

")
  
  print(meu_time %>% select(posicao, nome, clube, preco, media))
  
  # Salvar resultado
  write.csv(meu_time, "output/time_otimizado.csv", row.names = FALSE)
  
  # Gráfico
  p <- plot_time(meu_time, melhor_nome_esq, sum(meu_time$preco), pontos_totais)
  ggsave("output/campo_escala.png", p, width = 10, height = 7)
  cat("🖼️ Gráfico salvo em: output/campo_escala.png\n")
} else {
  cat("❌ Nenhuma solução encontrada para o orçamento de C$", ORCAMENTO, "
")
}
