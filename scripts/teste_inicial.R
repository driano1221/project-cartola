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

# --- Teste 3: Processamento dos dados ---
cat("3. Processando atletas disponiveis...\n")
df_clubes  <- process_clubes(dados_raw)
df_atletas <- process_atletas(dados_raw, df_clubes)

cat(sprintf("   %d clubes carregados\n", nrow(df_clubes)))
cat(sprintf("   %d atletas disponiveis (status Provavel, preco > 0)\n\n", nrow(df_atletas)))

if (nrow(df_atletas) < 100) {
  cat("   AVISO: numero de atletas muito baixo. Mercado pode estar fechado.\n")
  erros <- erros + 1
}

# --- Teste 4: Distribuicao por posicao ---
cat("4. Distribuicao por posicao:\n")
resumo <- df_atletas %>% dplyr::count(posicao, sort = TRUE)
for (i in seq_len(nrow(resumo))) {
  cat(sprintf("   %-10s: %d atletas\n", resumo$posicao[i], resumo$n[i]))
}
cat("\n")

# --- Teste 5: Top 5 por expectativa de pontos ---
cat("5. Top 5 por expectativa de pontos (com mando de campo):\n")
df_atletas %>%
  dplyr::arrange(dplyr::desc(expectativa_pontos)) %>%
  dplyr::slice(1:5) %>%
  dplyr::select(nome, clube, posicao, preco, media, expectativa_pontos, variacao) %>%
  print()
cat("\n")

# --- Resultado Final ---
if (erros == 0) {
  cat("=== Todos os testes passaram. Pipeline pronto para otimizacao! ===\n")
} else {
  cat(sprintf("=== %d problema(s) encontrado(s). Revise os erros acima. ===\n", erros))
}
