-- Somente leitura. Executar após a primeira carga.
SELECT * FROM rci_embratur.controle_carga_mensal_v2;
SELECT projeto_id, competencia, postos_trabalho, ausencias_conferidas,
       feriados_conferidos, flags_vazias_significam_false
FROM rci_embratur.parametros_mes_v2 ORDER BY projeto_id,competencia;
SELECT projeto_id,ano_mes,qib,qeb,qtd_nao_entregue,qtd_item_falha,
       qda,qdu,postos_trabalho,ies,ifb,iap,rci_preciso,rci,situacao,pendencias
FROM rci_embratur.vw_rci_mensal_v2 ORDER BY projeto_id,competencia;

SELECT projeto_id,COUNT(*) AS historias_sem_sprint
FROM rci_embratur.vw_itens_mensal_v2 WHERE sprint_id IS NULL GROUP BY projeto_id;

-- Deve retornar zero linhas: uma linha por competência e projeto.
SELECT projeto_id,competencia,COUNT(*)
FROM rci_embratur.vw_rci_mensal_v2 GROUP BY projeto_id,competencia HAVING COUNT(*)>1;

-- Salesforce (projeto 3). Conferir a competência antes de executar os modelos.
-- Não assumir sete postos em todos os meses passados.
-- UPDATE rci_embratur.parametros_mes_v2 SET postos_trabalho=7
-- WHERE projeto_id=3 AND competencia=DATE '2026-10-01';
-- Após conferir a fonte inteira do mês, os feriados e a convenção dos checkboxes:
-- UPDATE rci_embratur.parametros_mes_v2
-- SET ausencias_conferidas=true,feriados_conferidos=true,
--     flags_vazias_significam_false=true
-- WHERE projeto_id=3 AND competencia=DATE '2026-10-01';
