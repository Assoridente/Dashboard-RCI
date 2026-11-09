-- INSTALAÇÃO ADITIVA. Não chama a carga nem modifica as views antigas.
-- Requer permissões de DDL no schema rci_embratur.
CREATE SCHEMA IF NOT EXISTS rci_embratur;

ALTER TABLE rci_embratur.d_calendario
 ADD COLUMN IF NOT EXISTS inicio_mes date,
 ADD COLUMN IF NOT EXISTS fim_mes date,
 ADD COLUMN IF NOT EXISTS ano_mes text,
 ADD COLUMN IF NOT EXISTS ano_iso integer,
 ADD COLUMN IF NOT EXISTS dia_semana_iso integer;
CREATE UNIQUE INDEX IF NOT EXISTS ux_calendario_data_mensal_v2
 ON rci_embratur.d_calendario(data);

CREATE TABLE IF NOT EXISTS rci_embratur.d_feriados_mensal_v2 (
 data date PRIMARY KEY, descricao text NOT NULL
);
CREATE TABLE IF NOT EXISTS rci_embratur.controle_carga_mensal_v2 (
 projeto_id bigint PRIMARY KEY,
 inicio_cobertura date NOT NULL,
 ultima_publicacao timestamptz NOT NULL,
 qtd_sprints bigint NOT NULL, qtd_historias bigint NOT NULL,
 qtd_ausencias bigint NOT NULL
);
CREATE TABLE IF NOT EXISTS rci_embratur.parametros_mes_v2 (
 projeto_id bigint NOT NULL,
 competencia date NOT NULL CHECK (EXTRACT(DAY FROM competencia) = 1),
 postos_trabalho numeric CHECK (postos_trabalho > 0),
 ausencias_conferidas boolean NOT NULL DEFAULT false,
 feriados_conferidos boolean NOT NULL DEFAULT false,
 flags_vazias_significam_false boolean NOT NULL DEFAULT false,
 PRIMARY KEY (projeto_id, competencia)
);
CREATE TABLE IF NOT EXISTS rci_embratur.d_sprints_mensal_v2 (
 projeto_id bigint NOT NULL, sprint_id bigint NOT NULL,
 sprint_name text NOT NULL, inicio date, fim date, fechada boolean NOT NULL,
 presente_na_origem boolean NOT NULL DEFAULT true,
 PRIMARY KEY (projeto_id, sprint_id)
);
CREATE TABLE IF NOT EXISTS rci_embratur.f_userstories_mensal_v2 (
 projeto_id bigint NOT NULL, userstory_id bigint NOT NULL, ref bigint,
 sprint_id bigint, subject text, is_closed boolean NOT NULL,
 item_com_falha boolean, nao_entregue boolean, impedimento boolean,
 created_date timestamptz, modified_date timestamptz, finish_date timestamptz,
 presente_na_origem boolean NOT NULL DEFAULT true,
 PRIMARY KEY (projeto_id, userstory_id)
);
CREATE TABLE IF NOT EXISTS rci_embratur.f_ausencias_eventos_mensal_v2 (
 projeto_id bigint NOT NULL, origem_id bigint NOT NULL,
 colaborador_chave text NOT NULL, nome_colaborador text NOT NULL,
 data_inicio date NOT NULL, data_fim date NOT NULL,
 hora_inicio time, hora_fim time,
 presente_na_origem boolean NOT NULL DEFAULT true,
 CHECK (data_fim >= data_inicio),
 PRIMARY KEY (projeto_id, origem_id)
);

CREATE OR REPLACE FUNCTION rci_embratur.fn_booleano_mensal_v2(p_texto text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF NULLIF(BTRIM(p_texto), '') IS NULL THEN RETURN NULL; END IF;
 CASE LOWER(BTRIM(p_texto))
  WHEN 'true','t','1','sim','s','yes' THEN RETURN true;
  WHEN 'false','f','0','não','nao','n','no' THEN RETURN false;
  ELSE RAISE EXCEPTION 'Flag booleana inválida: %', p_texto;
 END CASE;
END $$;

CREATE OR REPLACE FUNCTION rci_embratur.fn_instante_mensal_v2(p_texto text)
RETURNS timestamptz LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
 IF NULLIF(BTRIM(p_texto), '') IS NULL THEN RETURN NULL; END IF;
 -- Valores sem offset na origem são tratados explicitamente como UTC.
 IF p_texto ~ '[T ]' AND p_texto ~ '(Z|[+-][0-9]{2}(:?[0-9]{2})?)$'
 THEN RETURN p_texto::timestamptz;
 ELSE RETURN (p_texto::timestamp AT TIME ZONE 'UTC'); END IF;
END $$;

-- Empate exato arredondado para o dígito par; mantém precisão no cálculo.
CREATE OR REPLACE FUNCTION rci_embratur.fn_arredondar_par_v2(p_valor numeric, p_casas integer)
RETURNS numeric LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE v_fator numeric; v_abs numeric; v_inteiro numeric;
BEGIN
 IF p_casas NOT BETWEEN 0 AND 10 THEN RAISE EXCEPTION 'Casas fora do intervalo 0..10'; END IF;
 v_fator := POWER(10::numeric, p_casas);
 v_abs := ABS(p_valor) * v_fator;
 v_inteiro := TRUNC(v_abs);
 IF v_abs - v_inteiro = 0.5 THEN
  RETURN SIGN(p_valor) * (v_inteiro + MOD(v_inteiro, 2)) / v_fator;
 END IF;
 RETURN ROUND(p_valor, p_casas);
END $$;

CREATE OR REPLACE PROCEDURE rci_embratur.sp_calendario_mensal_v2(p_inicio date, p_fim date)
LANGUAGE plpgsql AS $$
BEGIN
 IF p_inicio IS NULL OR p_fim IS NULL OR NOT ISFINITE(p_inicio)
    OR NOT ISFINITE(p_fim) OR p_inicio > p_fim
    OR p_fim - p_inicio > 36600
 THEN RAISE EXCEPTION 'Intervalo de calendário inválido ou superior a 100 anos'; END IF;
 INSERT INTO rci_embratur.d_calendario (
  data, ano, semestre, trimestre, mes, nome_mes, semana_ano, dia_mes,
  dia_semana, nome_dia, eh_final_semana, inicio_mes, fim_mes,
  ano_mes, ano_iso, dia_semana_iso)
 SELECT d::date, EXTRACT(YEAR FROM d)::integer,
  CASE WHEN EXTRACT(MONTH FROM d) <= 6 THEN 1 ELSE 2 END,
  EXTRACT(QUARTER FROM d)::integer, EXTRACT(MONTH FROM d)::integer,
  (ARRAY['Janeiro','Fevereiro','Março','Abril','Maio','Junho',
         'Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'])[EXTRACT(MONTH FROM d)::integer],
  EXTRACT(WEEK FROM d)::integer, EXTRACT(DAY FROM d)::integer,
  EXTRACT(DOW FROM d)::integer,
  (ARRAY['Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira',
         'Sexta-feira','Sábado','Domingo'])[EXTRACT(ISODOW FROM d)::integer],
  EXTRACT(ISODOW FROM d) IN (6,7), DATE_TRUNC('month', d)::date,
  (DATE_TRUNC('month', d) + INTERVAL '1 month - 1 day')::date,
  TO_CHAR(d, 'YYYY-MM'), EXTRACT(ISOYEAR FROM d)::integer,
  EXTRACT(ISODOW FROM d)::integer
 FROM GENERATE_SERIES(p_inicio::timestamp, p_fim::timestamp, INTERVAL '1 day') d
 ON CONFLICT (data) DO UPDATE SET
  ano=EXCLUDED.ano, semestre=EXCLUDED.semestre, trimestre=EXCLUDED.trimestre,
  mes=EXCLUDED.mes, nome_mes=EXCLUDED.nome_mes, semana_ano=EXCLUDED.semana_ano,
  dia_mes=EXCLUDED.dia_mes, dia_semana=EXCLUDED.dia_semana, nome_dia=EXCLUDED.nome_dia,
  eh_final_semana=EXCLUDED.eh_final_semana, inicio_mes=EXCLUDED.inicio_mes,
  fim_mes=EXCLUDED.fim_mes, ano_mes=EXCLUDED.ano_mes, ano_iso=EXCLUDED.ano_iso,
  dia_semana_iso=EXCLUDED.dia_semana_iso;
END $$;

CREATE OR REPLACE VIEW rci_embratur.vw_calendario_diario_mensal_v2 AS
SELECT c.*, f.descricao AS feriado,
       (NOT c.eh_final_semana AND f.data IS NULL) AS eh_dia_util
FROM rci_embratur.d_calendario c
LEFT JOIN rci_embratur.d_feriados_mensal_v2 f ON f.data=c.data;
