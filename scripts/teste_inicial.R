# Script de Teste e Validacao — Project Cartola
# Valida conectividade com a API e integridade do pipeline de dados.
source("R/data_processing.R")

cat("=== Teste de Conectividade e Validacao de Dados ===\n\n")
erros <- 0

# --- Teste 1: Conectividade com a API ---
cat("1. Testando conexao com a API do Cartola FC...\n")
dados_raw <- tryCatch(
  fetch_cartola_data(),
  error = function(e) {
    cat("   FALHOU:", e$message, "\n")
    stop("Abortando: sem conexao com a API.")
  }
)
cat("   OK - resposta recebida\n\n")

# --- Teste 2: Estrutura da resposta ---
cat("2. Validando estrutura da resposta da API...\n")
campos_obrigatorios <- c("atletas", "clubes", "posicoes", "partidas")
for (campo in campos_obrigatorios) {
  if (campo %in% names(dados_raw)) {
    cat(sprintf("   OK  '%s' presente\n", campo))
  } else {
    cat(sprintf("   ERRO '%s' ausente na resposta\n", campo))
    erros <- erros + 1
  }
}
cat("\n")

# --- Teste 3: Cache local de rodadas ---
cat("3. Salvando snapshot da rodada no cache local...\n")
rodada_salva <- salvar_snapshot_rodada(dados_raw)
hist_local   <- carregar_historico_por_rodada()
n_rodadas_cache <- if (!is.null(hist_local)) length(unique(hist_local$rodada)) else 0
cat(sprintf("   Cache: %d rodada(s) com deltas calculados em '%s'\n", n_rodadas_cache, CACHE_PATH))
if (n_rodadas_cache >= 2) {
  cat("   OK - forma_recente e std_pontos ativados\n")
  cat("   OK - modelo de Poisson (prob_sg) ativado\n")
} else {
  cat("   INFO - historico insuficiente (<2 rodadas): usando fallbacks conservadores\n")
}
cat("\n")

# --- Teste 4: Processamento dos dados ---
cat("4. Processando atletas disponiveis...\n")
df_clubes  <- process_clubes(dados_raw)
df_atletas <- process_atletas(dados_raw, df_clubes)

cat(sprintf("   %d clubes carregados\n", nrow(df_clubes)))
cat(sprintf("   %d atletas disponiveis (status Provavel, preco > 0)\n\n", nrow(df_atletas)))

if (nrow(df_atletas) < 100) {
  cat("   AVISO: numero de atletas muito baixo. Mercado pode estar fechado.\n")
  erros <- erros + 1
}

# --- Teste 5: Distribuicao por posicao ---
cat("5. Distribuicao por posicao:\n")
resumo <- df_atletas %>% dplyr::count(posicao, sort = TRUE)
for (i in seq_len(nrow(resumo))) {
  cat(sprintf("   %-10s: %d atletas\n", resumo$posicao[i], resumo$n[i]))
}
cat("\n")

# --- Teste 6: Top 5 por expectativa de pontos (com todas as metricas) ---
cat("6. Top 5 por expectativa de pontos (ajustada por confronto + historico):\n")
df_atletas %>%
  dplyr::arrange(dplyr::desc(expectativa_pontos)) %>%
  dplyr::slice(1:5) %>%
  dplyr::select(nome, clube, posicao, preco, media, forma_recente, expectativa_pontos,
                prob_sg, std_pontos, consistencia) %>%
  print()
cat("\n")

# --- Teste 7: Defensores mais consistentes com valorização provável ---
cat("7. Top 5 defensores com valoriza_provavel e maior prob_sg:\n")
df_atletas %>%
  dplyr::filter(is_defesa, valoriza_provavel) %>%
  dplyr::arrange(dplyr::desc(prob_sg)) %>%
  dplyr::slice(1:5) %>%
  dplyr::select(nome, clube, posicao, preco, media, min_val, prob_sg, std_pontos, consistencia) %>%
  print()
cat("\n")

# --- Resultado Final ---
if (erros == 0) {
  cat("=== Todos os testes passaram. Pipeline pronto para otimizacao! ===\n")
} else {
  cat(sprintf("=== %d problema(s) encontrado(s). Revise os erros acima. ===\n", erros))
}
