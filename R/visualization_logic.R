library(ggplot2)
library(ggsoccer)
library(ggrepel)
library(ggimage)

plot_time <- function(df_time, esquema_nome, orcamento_total, pontos_previstos) {
  # Distribuição em Y (Largura do campo)
  distribuir_y <- function(n) {
    if(n==1) return(50)
    if(n==2) return(c(20, 80))
    if(n==3) return(c(20, 50, 80))
    if(n==4) return(c(15, 38, 62, 85))
    return(seq(10, 90, length.out=n))
  }
  
  plot_data <- df_time %>%
    group_by(posicao) %>%
    mutate(
      idx = row_number(),
      x = case_when(
        posicao == "Goleiro"  ~ 6,
        posicao == "Zagueiro" ~ 22,
        posicao == "Lateral"  ~ 35,
        posicao == "Meia"     ~ 60,
        posicao == "Atacante" ~ 85,
        posicao == "Técnico"  ~ 50
      ),
      y = ifelse(posicao == "Técnico", -5, 0)
    ) %>%
    ungroup()
  
  for(p in unique(plot_data$posicao)) {
    if(p != "Técnico") {
      n_pos <- sum(plot_data$posicao == p)
      plot_data$y[plot_data$posicao == p] <- distribuir_y(n_pos)
    }
  }
  
  ggplot(plot_data) +
    annotate_pitch(dimensions = pitch_statsbomb, fill = "#2e8b57", colour = "white") +
    coord_cartesian(ylim = c(-10, 105)) +
    
    # Desenha o escudo do time (usando a URL da API)
    geom_image(aes(x=x, y=y, image=escudo), size=0.08) +
    
    # Sombra dourada para o Capitão
    geom_point(data = subset(plot_data, is_capitao), aes(x=x, y=y), 
               size=12, color="gold", shape=1, stroke=2, alpha=0.8) +
    
    # Rótulos com Label compacto e Média
    geom_label_repel(aes(x=x, y=y, label=paste0(label, "\n", round(media, 1), " pts")),
                     size=3, fontface="bold", box.padding = 0.5, segment.color = "grey80",
                     alpha=0.9) +
    
    theme_pitch() +
    theme(
      plot.title = element_text(hjust = 0.5, size = 18, face = "bold"),
      plot.subtitle = element_text(hjust = 0.5, size = 12)
    ) +
    labs(title = paste("Seleção Cartola FC -", esquema_nome),
         subtitle = paste0("Patrimônio: C$ ", round(orcamento_total, 2), " | Previsão: ", round(pontos_previstos, 2), " pts"),
         caption = "O círculo dourado indica o Capitão")
}
