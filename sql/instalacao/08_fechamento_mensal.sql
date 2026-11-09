-- Instalar após 01, 02 e 03. Não fecha nenhum mês automaticamente.
-- Regra: somente mês encerrado, relatório final importado e apuração sem pendências.
CREATE TABLE IF NOT EXISTS rci_embratur.f_fechamentos_mensal_v2 (
 projeto_id bigint NOT NULL,
 competencia date NOT NULL CHECK (EXTRACT(DAY FROM competencia)=1),
 versao integer NOT NULL CHECK (versao>0),
 fechado_em timestamptz NOT NULL DEFAULT CLOCK_TIMESTAMP(),
 motivo_revisao text,
 resultado jsonb NOT NULL,
 PRIMARY KEY(projeto_id,competencia,versao)
);

CREATE OR REPLACE PROCEDURE rci_embratur.sp_fechar_rci_mensal_v2(
 p_competencia date,
 p_relatorio_final_importado boolean DEFAULT false,
 p_projeto_id bigint DEFAULT 3,
 p_motivo_revisao text DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE v_resultado jsonb; v_anterior jsonb; v_versao integer;
BEGIN
 IF p_competencia IS NULL OR NOT ISFINITE(p_competencia)
    OR EXTRACT(DAY FROM p_competencia)<>1
    OR p_competencia>=DATE_TRUNC('month',CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date
 THEN RAISE EXCEPTION 'Informe o primeiro dia de uma competência já encerrada. Mês atual e futuro não podem ser fechados'; END IF;
 IF p_relatorio_final_importado IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'É necessário confirmar a importação do relatório final da competência'; END IF;
 IF p_projeto_id IS NULL OR p_projeto_id<=0 THEN RAISE EXCEPTION 'Projeto inválido'; END IF;
 IF NOT pg_try_advisory_xact_lock(726314902781::bigint) THEN
  RAISE EXCEPTION 'Carga ou fechamento em execução. Tente novamente depois'; END IF;
 SELECT TO_JSONB(v) INTO v_resultado FROM rci_embratur.vw_rci_mensal_v2 v
 WHERE v.projeto_id=p_projeto_id AND v.competencia=p_competencia;
 IF v_resultado IS NULL THEN RAISE EXCEPTION 'Competência não carregada para o projeto'; END IF;
 IF v_resultado->>'situacao'<>'APURADO' OR v_resultado->>'rci' IS NULL THEN
  RAISE EXCEPTION 'Competência ainda não pode ser fechada: situação %, pendências %, sprints abertas %',
   v_resultado->>'situacao',v_resultado->'pendencias',v_resultado->>'sprints_abertas'; END IF;
 IF ((v_resultado->>'ultima_publicacao')::timestamptz AT TIME ZONE 'America/Sao_Paulo')::date
    < (p_competencia+INTERVAL '1 month')::date THEN
  RAISE EXCEPTION 'A carga disponível é anterior ao encerramento do mês. Importe o relatório final e execute a atualização'; END IF;
 SELECT resultado,versao INTO v_anterior,v_versao
 FROM rci_embratur.f_fechamentos_mensal_v2
 WHERE projeto_id=p_projeto_id AND competencia=p_competencia
 ORDER BY versao DESC LIMIT 1;
 -- Repetir um fechamento sem mudar os números não cria nova versão.
 IF v_anterior IS NOT NULL
    AND (v_anterior-'ultima_publicacao')=(v_resultado-'ultima_publicacao') THEN RETURN; END IF;
 IF v_anterior IS NOT NULL AND NULLIF(BTRIM(p_motivo_revisao),'') IS NULL THEN
  RAISE EXCEPTION 'O mês já foi fechado com outros valores. Informe motivo para registrar uma revisão'; END IF;
 INSERT INTO rci_embratur.f_fechamentos_mensal_v2
  (projeto_id,competencia,versao,motivo_revisao,resultado)
 VALUES(p_projeto_id,p_competencia,COALESCE(v_versao,0)+1,
        NULLIF(BTRIM(p_motivo_revisao),''),v_resultado);
END $$;

-- Dataset de produção: última versão explicitamente fechada de cada mês.
-- O resultado é congelado: uma nova carga não modifica meses já publicados.
CREATE OR REPLACE VIEW rci_embratur.vw_rci_meses_fechados_v2 AS
WITH ultima AS (
 SELECT DISTINCT ON(projeto_id,competencia) *
 FROM rci_embratur.f_fechamentos_mensal_v2
 WHERE competencia<DATE_TRUNC('month',CURRENT_TIMESTAMP AT TIME ZONE 'America/Sao_Paulo')::date
 ORDER BY projeto_id,competencia,versao DESC
)
SELECT r.*,u.versao AS versao_fechamento,u.fechado_em,u.motivo_revisao
FROM ultima u
CROSS JOIN LATERAL JSONB_POPULATE_RECORD(NULL::rci_embratur.vw_rci_mensal_v2,u.resultado) r;

CREATE OR REPLACE VIEW rci_embratur.vw_filtro_meses_fechados_v2 AS
SELECT projeto_id,competencia,ano,mes,ano_mes,nome_mes
FROM rci_embratur.vw_rci_meses_fechados_v2;
