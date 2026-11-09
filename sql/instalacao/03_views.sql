-- Dias úteis: de segunda a sexta, excluindo as datas cadastradas em feriados.
-- Ausência de vários dias mantém dias inteiros nas pontas: falta regra de jornada
-- para inferir frações dessas pontas. Eventos de um dia mantêm a regra <=4h = 0,5.
CREATE OR REPLACE VIEW rci_embratur.vw_ausencias_dia_mensal_v2 AS
WITH expandidas AS (
 SELECT a.projeto_id,a.colaborador_chave,MIN(a.nome_colaborador) OVER
        (PARTITION BY a.projeto_id,a.colaborador_chave) AS nome_colaborador,
  c.data, a.hora_inicio,a.hora_fim,
  (a.data_inicio<>a.data_fim OR a.hora_inicio IS NULL) AS dia_inteiro
 FROM rci_embratur.f_ausencias_eventos_mensal_v2 a
 JOIN rci_embratur.vw_calendario_diario_mensal_v2 c
  ON c.data BETWEEN a.data_inicio AND a.data_fim AND c.eh_dia_util
 WHERE a.presente_na_origem
), base AS (
 SELECT projeto_id,colaborador_chave,nome_colaborador,data,BOOL_OR(dia_inteiro) AS inteiro
 FROM expandidas GROUP BY 1,2,3,4
), intervalos AS (
 SELECT DISTINCT projeto_id,colaborador_chave,data,hora_inicio,hora_fim
 FROM expandidas WHERE NOT dia_inteiro
), anteriores AS (
 SELECT *,MAX(hora_fim) OVER (PARTITION BY projeto_id,colaborador_chave,data
  ORDER BY hora_inicio,hora_fim ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS fim_anterior
 FROM intervalos
), grupos AS (
 SELECT *,SUM(CASE WHEN fim_anterior IS NULL OR hora_inicio>fim_anterior THEN 1 ELSE 0 END)
 OVER (PARTITION BY projeto_id,colaborador_chave,data ORDER BY hora_inicio,hora_fim) AS grupo
 FROM anteriores
), ilhas AS (
 SELECT projeto_id,colaborador_chave,data,grupo,MIN(hora_inicio) AS inicio,MAX(hora_fim) AS fim
 FROM grupos GROUP BY 1,2,3,4
), horas AS (
 SELECT projeto_id,colaborador_chave,data,SUM(EXTRACT(EPOCH FROM (fim-inicio))) AS segundos
 FROM ilhas GROUP BY 1,2,3
)
SELECT b.projeto_id,b.colaborador_chave,b.nome_colaborador,b.data AS data_ausencia,
 DATE_TRUNC('month',b.data)::date AS competencia,
 CASE WHEN b.inteiro THEN 1::numeric
      WHEN h.segundos<=14400 THEN 0.5::numeric ELSE 1::numeric END AS dias_ausencia
FROM base b LEFT JOIN horas h USING(projeto_id,colaborador_chave,data);

CREATE OR REPLACE VIEW rci_embratur.vw_itens_mensal_v2 AS
SELECT u.*, s.sprint_name,s.inicio AS inicio_sprint,s.fim AS fim_sprint,s.fechada AS sprint_fechada,
 DATE_TRUNC('month',s.fim)::date AS competencia,
 (u.finish_date AT TIME ZONE 'America/Sao_Paulo')::date AS dia_conclusao_local
FROM rci_embratur.f_userstories_mensal_v2 u
LEFT JOIN rci_embratur.d_sprints_mensal_v2 s
 ON s.projeto_id=u.projeto_id AND s.sprint_id=u.sprint_id AND s.presente_na_origem
WHERE u.presente_na_origem;

CREATE OR REPLACE VIEW rci_embratur.vw_rci_mensal_v2 AS
WITH calendario AS (
 SELECT inicio_mes AS competencia,MIN(nome_mes) AS nome_mes,
        COUNT(*) FILTER (WHERE eh_dia_util) AS qdu
 FROM rci_embratur.vw_calendario_diario_mensal_v2 GROUP BY inicio_mes
), itens AS (
 SELECT projeto_id,competencia,COUNT(*) AS qib,
  COUNT(*) FILTER (WHERE is_closed AND nao_entregue IS NOT true) AS qeb,
  COUNT(*) FILTER (WHERE item_com_falha) AS qtd_item_falha,
  COUNT(*) FILTER (WHERE nao_entregue) AS qtd_nao_entregue,
  COUNT(*) FILTER (WHERE impedimento) AS qtd_impedimento,
  COUNT(*) FILTER (WHERE NOT is_closed AND nao_entregue IS NOT true) AS abertas_sem_flag,
  COUNT(*) FILTER (WHERE item_com_falha IS NULL) AS falhas_nao_preenchidas,
  COUNT(*) FILTER (WHERE nao_entregue IS NULL) AS entregas_nao_preenchidas
 FROM rci_embratur.vw_itens_mensal_v2 WHERE sprint_fechada
 GROUP BY projeto_id,competencia
), sprints AS (
 SELECT projeto_id,DATE_TRUNC('month',fim)::date AS competencia,
  COUNT(*) FILTER (WHERE fechada) AS sprints_fechadas,
  COUNT(*) FILTER (WHERE NOT fechada) AS sprints_abertas
 FROM rci_embratur.d_sprints_mensal_v2 WHERE presente_na_origem GROUP BY 1,2
), ausencias AS (
 SELECT projeto_id,competencia,SUM(dias_ausencia) AS qda
 FROM rci_embratur.vw_ausencias_dia_mensal_v2 GROUP BY 1,2
), base AS (
 SELECT p.projeto_id,p.competencia,
  EXTRACT(YEAR FROM p.competencia)::integer AS ano,
  EXTRACT(MONTH FROM p.competencia)::integer AS mes,
  TO_CHAR(p.competencia,'YYYY-MM') AS ano_mes,c.nome_mes,
  p.postos_trabalho,c.qdu,COALESCE(a.qda,0) AS qda,
  COALESCE(i.qib,0) AS qib,COALESCE(i.qeb,0) AS qeb,
  COALESCE(i.qtd_item_falha,0) AS qtd_item_falha,
  COALESCE(i.qtd_nao_entregue,0) AS qtd_nao_entregue,
  COALESCE(i.qtd_impedimento,0) AS qtd_impedimento,
  COALESCE(i.abertas_sem_flag,0) AS abertas_sem_flag,
  COALESCE(i.falhas_nao_preenchidas,0) AS falhas_nao_preenchidas,
  COALESCE(i.entregas_nao_preenchidas,0) AS entregas_nao_preenchidas,
  COALESCE(s.sprints_fechadas,0) AS sprints_fechadas,
  COALESCE(s.sprints_abertas,0) AS sprints_abertas,
  p.ausencias_conferidas,p.feriados_conferidos,p.flags_vazias_significam_false,
  cc.ultima_publicacao
 FROM rci_embratur.parametros_mes_v2 p
 JOIN rci_embratur.controle_carga_mensal_v2 cc ON cc.projeto_id=p.projeto_id
 JOIN calendario c ON c.competencia=p.competencia
 LEFT JOIN itens i ON i.projeto_id=p.projeto_id AND i.competencia=p.competencia
 LEFT JOIN sprints s ON s.projeto_id=p.projeto_id AND s.competencia=p.competencia
 LEFT JOIN ausencias a ON a.projeto_id=p.projeto_id AND a.competencia=p.competencia
 WHERE p.competencia>=cc.inicio_cobertura
), indices AS (
 SELECT *,
  CASE WHEN qib>0 AND (entregas_nao_preenchidas=0 OR flags_vazias_significam_false)
       THEN qtd_nao_entregue::numeric/qib*0.40 END AS ies,
  CASE WHEN qib>0 AND (falhas_nao_preenchidas=0 OR flags_vazias_significam_false)
       THEN qtd_item_falha::numeric/qib*0.30 END AS ifb,
  CASE WHEN ausencias_conferidas AND feriados_conferidos AND postos_trabalho>0 AND qdu>0
         AND qda<=postos_trabalho*qdu
       THEN qda/(postos_trabalho*qdu)*0.30 END AS iap,
  ARRAY_REMOVE(ARRAY[
   CASE WHEN qib=0 THEN 'SEM_ITENS_DE_SPRINTS_FECHADAS' END,
   CASE WHEN postos_trabalho IS NULL THEN 'POSTOS_NAO_INFORMADOS' END,
   CASE WHEN NOT ausencias_conferidas THEN 'AUSENCIAS_NAO_CONFERIDAS' END,
   CASE WHEN NOT feriados_conferidos THEN 'FERIADOS_NAO_CONFERIDOS' END,
   CASE WHEN (falhas_nao_preenchidas>0 OR entregas_nao_preenchidas>0)
        AND NOT flags_vazias_significam_false THEN 'FLAGS_VAZIAS_PENDENTES' END,
   CASE WHEN qdu=0 THEN 'SEM_DIAS_UTEIS' END,
   CASE WHEN qda>postos_trabalho*qdu THEN 'AUSENCIAS_SUPERAM_CAPACIDADE' END
  ],NULL) AS pendencias
 FROM base
), resultado AS (
 SELECT *,1::numeric-(ies+ifb+iap) AS rci_preciso FROM indices
)
SELECT *,rci_embratur.fn_arredondar_par_v2(rci_preciso,2) AS rci,
 CASE WHEN CARDINALITY(pendencias)>0 THEN 'PENDENTE'
      WHEN competencia>=DATE_TRUNC('month',CURRENT_DATE)::date OR sprints_abertas>0
      THEN 'PARCIAL' ELSE 'APURADO' END AS situacao,
 CASE WHEN rci_preciso IS NULL THEN NULL ELSE rci_preciso>=0.95 END AS meta_095
FROM resultado;

CREATE OR REPLACE VIEW rci_embratur.vw_filtro_meses_v2 AS
SELECT DISTINCT projeto_id,competencia,ano,mes,ano_mes,nome_mes
FROM rci_embratur.vw_rci_mensal_v2;
