# ==============================================================================
# ⚽ PROJECT CARTOLA - OTIMIZADOR INTELIGENTE (PONTOS & VALORIZAÇÃO)
# ==============================================================================
source("R/data_processing.R")
source("R/optimization_logic.R")
source("R/visualization_logic.R")
source("R/cache_rodadas.R")
source("R/sg_model.R")

cat("\n==================================================\n")
cat("🏟️  BEM-VINDO AO OTIMIZADOR PROJECT CARTOLA\n")
cat("==================================================\n\n")

# 1. ENTRADA DE DADOS INTERATIVA
read_input <- function(prompt_msg) {
  cat(prompt_msg)
  if (interactive()) {
    return(readline())
  } else {
    return(readLines(file("stdin"), n = 1))
  }
}

input_orcamento <- read_input("💰 Quanto quer gastar (em cartoletas)? [Ex: 120.5]: ")
ORCAMENTO <- as.numeric(input_orcamento)
if (is.na(ORCAMENTO)) ORCAMENTO <- 120.0

cat("\nEscolha o objetivo da escalação:\n")
cat("[1] Maximizar PONTOS (Melhor para vencer a rodada)\n")
cat("[2] Maximizar VALORIZAÇÃO (Melhor para ganhar dinheiro)\n")
input_objetivo <- read_input("Opção [1 ou 2]: ")

campo_alvo <- if (input_objetivo == "2") "potencial_valorizacao" else "expectativa_pontos"
label_objetivo <- if (input_objetivo == "2") "VALORIZAÇÃO" else "PONTOS"

# 2. ETL & CACHE
cat(sprintf("\n🎯 OBJETIVO SELECIONADO: %s\n", label_objetivo))
cat("🔄 Conectando à API do Cartola FC...\n")
dados_raw <- fetch_cartola_data()

# Salva snapshot para o histórico
rodada_id <- salvar_snapshot_rodada(dados_raw)

cat("🧹 Processando atletas e aplicando inteligência estatística...\n")
df_clubes <- process_clubes(dados_raw)
df_atletas <- process_atletas(dados_raw, df_clubes)

# 3. OTIMIZAÇÃO MULTI-ESQUEMA
cat(sprintf("🧠 Analisando todos os esquemas táticos para %s...\n", label_objetivo))

esquemas <- get_esquemas()
resultados_esquemas <- data.frame(Esquema=character(), Pontuacao=numeric(), Custo=numeric(), Status=character())
melhor_res <- NULL
max_val <- -1
melhor_nome_esq <- ""

for(nome in names(esquemas)) {
  res <- resolver_otimizacao(df_atletas, ORCAMENTO, esquemas[[nome]], campo_alvo)
  
  if(res$status == "ok") {
    resultados_esquemas <- rbind(resultados_esquemas, data.frame(
      Esquema = nome, 
      Pontuacao = round(res$valor, 2), 
      Custo = round(sum(df_atletas$preco[res$vetor == 1]), 2),
      Status = "✅"
    ))
    
    if(res$valor > max_val) {
      max_val <- res$valor
      melhor_res <- res
      melhor_nome_esq <- nome
    }
  } else {
    resultados_esquemas <- rbind(resultados_esquemas, data.frame(
      Esquema = nome, Pontuacao = 0, Custo = 0, Status = "❌ Inviável"
    ))
  }
}

# 4. EXIBIR COMPARAÇÃO DE ESQUEMAS
cat("\n📊 COMPARAÇÃO DE FORMAÇÕES TÁTICAS:\n")
print(resultados_esquemas %>% arrange(desc(Pontuacao)))

# 5. LISTAR 3 MELHORES OPÇÕES POR TIME (TOP 3)
cat("\n🌟 DESTAQUES POR CLUBE (Top 3 Melhores Opções):\n")
destaques <- df_atletas %>%
  group_by(clube_nome) %>%
  slice_max(order_by = !!sym(campo_alvo), n = 3, with_ties = FALSE) %>%
  select(clube_nome, nome, posicao, preco, media, valor = !!sym(campo_alvo)) %>%
  arrange(clube_nome, desc(valor))

# Formatação simples para exibição por blocos de time
clube_atual <- ""
for(i in 1:nrow(destaques)) {
  if(destaques$clube_nome[i] != clube_atual) {
    clube_atual <- destaques$clube_nome[i]
    cat(sprintf("\n🔹 %s:\n", clube_atual))
  }
  cat(sprintf("   - %-15s (%-8s) | C$ %5.2f | Val: %5.2f\n", 
              destaques$nome[i], destaques$posicao[i], destaques$preco[i], destaques$valor[i]))
}

# 6. RESULTADOS DO TIME CAMPEÃO E VISUALIZAÇÃO
if(!is.null(melhor_res)) {
  df_atletas$escalado <- as.vector(melhor_res$vetor)
  meu_time <- df_atletas %>% filter(escalado == 1)
  
  # Capitão Inteligente
  meu_time <- meu_time %>%
    mutate(peso_capitao = case_when(
      posicao == "Atacante" & is_mandante ~ media * 2.0,
      posicao == "Atacante" ~ media * 1.5,
      posicao == "Meia" & is_mandante ~ media * 1.3,
      TRUE ~ media
    ))
  
  id_capitao <- meu_time$id[which.max(ifelse(meu_time$posicao == "Técnico", -99, meu_time$peso_capitao))]
  meu_time <- meu_time %>% mutate(is_capitao = (id == id_capitao))
  
  # Cálculo de Pontuação Projetada (Consistente com o Objetivo)
  # Soma as expectativas e adiciona o bônus do capitão (que ganha +0.5x da sua expectativa no Cartola)
  # Nota: O capitão na verdade ganha 2x, mas como já somamos 1x no sum(), adicionamos apenas o bônus.
  
  valor_capitao <- meu_time[[campo_alvo]][meu_time$is_capitao]
  pts_proj <- sum(meu_time[[campo_alvo]]) + valor_capitao
  
  cat("\n==================================================\n")
  cat(sprintf("🏆 ESCALAÇÃO CAMPEÃ: %s\n", melhor_nome_esq))
  cat(sprintf("💰 Custo: C$ %.2f | 📊 Expectativa da Rodada: %.2f\n", sum(meu_time$preco), pts_proj))
  cat("==================================================\n\n")
  
  print(meu_time %>% 
          select(posicao, nome, clube, preco, media, expectativa_pontos) %>%
          arrange(match(posicao, c("Goleiro","Lateral","Zagueiro","Meia","Atacante","Técnico"))))
  
  nome_arquivo <- if (input_objetivo == "2") "time_valorizacao" else "time_pontos"
  write.csv(meu_time, sprintf("output/%s.csv", nome_arquivo), row.names = FALSE)
  
  cat("\n🖼️  Gerando campo visual...\n")
  p <- plot_time(meu_time, sprintf("%s (%s)", melhor_nome_esq, label_objetivo), sum(meu_time$preco), pts_proj)
  ggsave(sprintf("output/%s.png", nome_arquivo), p, width = 10, height = 7)
  
  cat(sprintf("\n✅ Sucesso! Verifique a pasta 'output/' para ver o arquivo %s.png\n", nome_arquivo))
  
} else {
  cat("\n❌ Erro: Não foi possível encontrar uma solução viável para este orçamento.\n")
}
