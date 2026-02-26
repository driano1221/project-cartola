library(CVXR)
library(dplyr)

resolver_otimizacao <- function(df_atletas, orcamento, limites_posicao, campo_objetivo = "expectativa_pontos") {
  n <- nrow(df_atletas)
  x <- Variable(n, boolean = TRUE)
  
  # Matrizes de Posição
  posicoes <- c("Goleiro", "Lateral", "Zagueiro", "Meia", "Atacante", "Técnico")
  mat_pos <- matrix(0, n, length(posicoes))
  colnames(mat_pos) <- posicoes
  for(p in posicoes) mat_pos[, p] <- as.integer(df_atletas$posicao == p)
  
  # Matriz de Clubes
  clubes_unicos <- unique(df_atletas$clube_id)
  mat_clubes <- matrix(0, n, length(clubes_unicos))
  for(i in seq_along(clubes_unicos)) mat_clubes[, i] <- as.integer(df_atletas$clube_id == clubes_unicos[i])
  
  # Matriz de Defesa por Clube (Anti-Stacking)
  mat_defesa_clube <- matrix(0, n, length(clubes_unicos))
  for(i in seq_along(clubes_unicos)) {
    mat_defesa_clube[, i] <- as.integer(df_atletas$clube_id == clubes_unicos[i] & df_atletas$is_defesa)
  }
  
  # Restrições
  constraints <- list(
    sum(x * df_atletas$preco) <= orcamento,
    sum(x) == 12,
    (t(mat_pos) %*% x) == limites_posicao,
    (t(mat_clubes) %*% x) <= 4,        # Máximo 4 jogadores do mesmo clube (geral)
    (t(mat_defesa_clube) %*% x) <= 2   # Máximo 2 de defesa do mesmo clube (Gestão de Risco)
  )
  
  # Objetivo (Pontos ou Valorização)
  obj_vec <- df_atletas[[campo_objetivo]]
  prob <- Problem(Maximize(t(obj_vec) %*% x), constraints)
  
  solver_usado <- ifelse("GLPK_MI" %in% installed_solvers(), "GLPK_MI", "ECOS_BB")
  res <- solve(prob, solver = solver_usado)
  
  if(res$status %in% c("optimal", "optimal_inaccurate")) {
    return(list(status = "ok", valor = res$value, vetor = round(res$getValue(x))))
  } else {
    return(list(status = "error"))
  }
}
