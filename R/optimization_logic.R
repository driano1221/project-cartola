library(CVXR)
library(dplyr)

# Retorna todos os esquemas taticos suportados (12 jogadores cada)
get_esquemas <- function() {
  list(
    "4-3-3" = c(Goleiro=1, Lateral=2, Zagueiro=2, Meia=3, Atacante=3, Técnico=1),
    "4-4-2" = c(Goleiro=1, Lateral=2, Zagueiro=2, Meia=4, Atacante=2, Técnico=1),
    "3-5-2" = c(Goleiro=1, Lateral=2, Zagueiro=1, Meia=5, Atacante=2, Técnico=1),
    "4-5-1" = c(Goleiro=1, Lateral=2, Zagueiro=2, Meia=5, Atacante=1, Técnico=1),
    "3-4-3" = c(Goleiro=1, Lateral=2, Zagueiro=1, Meia=4, Atacante=3, Técnico=1)
  )
}

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
  obj_vec <- as.numeric(df_atletas[[campo_objetivo]])
  stopifnot(!any(is.na(obj_vec)), !any(is.infinite(obj_vec)))
  prob <- Problem(Maximize(t(obj_vec) %*% x), constraints)

  # Hierarquia robusta de solvers: prefere solvers mais confiaveis para MILP.
  # ECOS_BB e o ultimo fallback — tem problemas documentados de corretude para MILP puro.
  hierarquia_solvers <- c("GUROBI", "MOSEK", "CBC", "GLPK_MI", "ECOS_BB")
  disponiveis        <- hierarquia_solvers[hierarquia_solvers %in% installed_solvers()]
  if (length(disponiveis) == 0) stop("Nenhum solver MILP instalado. Instale o pacote 'Rglpk'.")
  solver_usado <- disponiveis[1]

  res <- solve(prob, solver = solver_usado)

  if (res$status == "optimal_inaccurate") {
    warning(sprintf(
      "Solver '%s' retornou optimal_inaccurate: solucao pode ser subotima. Considere instalar GLPK_MI.",
      solver_usado
    ))
  }

  if (res$status %in% c("optimal", "optimal_inaccurate")) {
    return(list(status = "ok", valor = res$value, vetor = as.integer(round(res$getValue(x)))))
  } else {
    return(list(status = "error"))
  }
}
