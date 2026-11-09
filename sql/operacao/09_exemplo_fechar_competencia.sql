-- PRIMEIRO importe o relatório final e execute o arquivo 05.
-- Confira os parâmetros e o resultado do mês. O arquivo 07 configura o histórico
-- confirmado até outubro/2026; não deve conferir automaticamente meses futuros.
-- Só então feche a competência escolhida. Outubro/2026 só a partir de 01/11/2026.
-- O exemplo fica comentado para não presumir qual relatório está sendo fechado.

-- BEGIN;
-- CALL rci_embratur.sp_fechar_rci_mensal_v2(
--  p_competencia => DATE '2026-09-01',
--  p_relatorio_final_importado => true,
--  p_projeto_id => 3
-- );
-- COMMIT;

-- Consulta dos dados efetivamente publicados no dashboard.
SELECT ano_mes,qib,qeb,qda,qdu,postos_trabalho,rci,fechado_em,versao_fechamento
FROM rci_embratur.vw_rci_meses_fechados_v2
WHERE projeto_id=3 ORDER BY competencia;
