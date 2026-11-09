CREATE OR REPLACE VIEW rci_embratur.vw_rci_meses_fechados_v2 AS
WITH ultima AS (
    SELECT DISTINCT ON (projeto_id, competencia) *
    FROM rci_embratur.f_fechamentos_mensal_v2
    WHERE competencia < DATE_TRUNC('month', CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date
    ORDER BY projeto_id, competencia, versao DESC
)
SELECT r.*, u.versao AS versao_fechamento, u.fechado_em, u.motivo_revisao,
    s.sprints_do_mes,
    CONCAT_WS(E'\n', LEFT(r.nome_mes, 3) || ' ' || TO_CHAR(r.competencia, 'YY'), s.sprints_do_mes) AS mes_com_sprints
FROM ultima u
CROSS JOIN LATERAL JSONB_POPULATE_RECORD(NULL::rci_embratur.vw_rci_mensal_v2, u.resultado) r
LEFT JOIN LATERAL (
    SELECT STRING_AGG(d.sprint_name, ' · ' ORDER BY d.fim, d.sprint_id) AS sprints_do_mes
    FROM rci_embratur.d_sprints_mensal_v2 d
    WHERE d.projeto_id = u.projeto_id
      AND d.fim >= u.competencia
      AND d.fim < u.competencia + INTERVAL '1 month'
      AND d.presente_na_origem AND d.fechada
) s ON TRUE;

SELECT ano_mes, mes_com_sprints, qib, qeb
FROM rci_embratur.vw_rci_meses_fechados_v2
WHERE projeto_id = 3
ORDER BY competencia;
