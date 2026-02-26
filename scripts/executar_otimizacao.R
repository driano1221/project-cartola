# Script Principal - Otimizador Cartola
source("R/data_processing.R")
source("R/optimization_logic.R")
source("R/visualization_logic.R")

# 1. Parâmetros
ORCAMENTO <- 120.0 # Altere aqui seu patrimônio

# 2. ETL
cat("📥 Buscando dados...\n")
dados_raw <- tryCatch(
  fetch_cartola_data(),
  error = function(e) { cat("❌", e$message, "\n"); stop() }
)
salvar_snapshot_rodada(dados_raw)
df_clubes  <- process_clubes(dados_raw)
df_atletas <- process_atletas(dados_raw, df_clubes)
cat(sprintf("✅ %d atletas disponíveis carregados.\n", nrow(df_atletas)))

# 3. Otimização Multi-Esquema
cat("🧠 Otimizando múltiplos esquemas táticos...\n")
esquemas          <- get_esquemas()
melhor_res_global <- NULL
max_pts           <- -1
melhor_nome_esq   <- ""

for (nome in names(esquemas)) {
  res <- resolver_otimizacao(df_atletas, ORCAMENTO, esquemas[[nome]], "expectativa_pontos")
  if (res$status == "ok" && res$valor > max_pts) {
    max_pts           <- res$valor
    melhor_res_global <- res
    melhor_nome_esq   <- nome
  }
}

# 4. Resultado Final
if (!is.null(melhor_res_global)) {
  df_atletas$escalado <- as.vector(melhor_res_global$vetor)
  meu_time <- df_atletas %>% filter(escalado == 1)

  # Capitão: maior média excluindo Técnico
  id_capitao <- meu_time$id[which.max(ifelse(meu_time$posicao == "Técnico", -99, meu_time$media))]
  meu_time   <- meu_time %>% mutate(is_capitao = (id == id_capitao))

  # Pontuação esperada: soma das médias + bônus extra do capitão (0.5x, pois 1.5x total)
  media_capitao <- max(meu_time$media[meu_time$posicao != "Técnico"])
  pontos_totais <- sum(meu_time$media) + 0.5 * media_capitao

  cat("\n✅ Melhor esquema encontrado:", melhor_nome_esq)
  cat("\n💰 Custo total: C$", sum(meu_time$preco))
  cat("\n🔥 Pontuação esperada (c/ capitão 1.5x):", round(pontos_totais, 2), "\n\n")

  print(meu_time %>% select(posicao, nome, clube, preco, media, expectativa_pontos))

  # Salvar resultado
  dir.create("output", showWarnings = FALSE, recursive = TRUE)
  write.csv(meu_time, "output/time_otimizado.csv", row.names = FALSE)

  # Gráfico
  p <- plot_time(meu_time, melhor_nome_esq, sum(meu_time$preco), pontos_totais)
  ggsave("output/campo_escala.png", p, width = 10, height = 7)
  cat("🖼️  Gráfico salvo em: output/campo_escala.png\n")
} else {
  cat("❌ Nenhuma solução encontrada para o orçamento de C$", ORCAMENTO, "\n")
  cat("   Tente aumentar o orçamento ou verificar a disponibilidade dos atletas.\n")
}
