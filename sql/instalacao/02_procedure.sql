-- Versão paralela: não substitui sp_atualizar_rci() nem alimenta gráficos antigos.
-- Configurado para Salesforce (projeto 3), com ausências exclusivas desse projeto,
-- conforme confirmado pelo usuário. A instalação não executa a carga.
CREATE OR REPLACE PROCEDURE rci_embratur.sp_atualizar_rci_mensal_v2(
 p_projeto_id bigint DEFAULT 3,
 p_ausencias_raw_sao_deste_projeto boolean DEFAULT true,
 p_inicio date DEFAULT DATE '2025-10-01',
 p_postos_mes_atual numeric DEFAULT 7,
 p_id_falha bigint DEFAULT 1,
 p_id_nao_entregue bigint DEFAULT 4,
 p_id_impedimento bigint DEFAULT 3,
 p_permitir_fonte_vazia boolean DEFAULT false
)
LANGUAGE plpgsql AS $$
DECLARE v_inicio date; v_fim date; v_id bigint; v_padrao text;
BEGIN
 IF p_projeto_id IS NULL OR p_projeto_id <= 0
    OR p_inicio IS NULL OR NOT ISFINITE(p_inicio) OR p_inicio > CURRENT_DATE
    OR p_postos_mes_atual IS NULL OR p_postos_mes_atual <= 0
 THEN RAISE EXCEPTION 'Informe projeto, início de cobertura e quantidade de postos válidos'; END IF;
 IF p_ausencias_raw_sao_deste_projeto IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'A origem de ausências não possui projeto. Confirme seu escopo antes da carga';
 END IF;
 IF p_id_falha IS NULL OR p_id_nao_entregue IS NULL OR p_id_impedimento IS NULL
    OR p_id_falha=p_id_nao_entregue OR p_id_falha=p_id_impedimento
    OR p_id_nao_entregue=p_id_impedimento
 THEN RAISE EXCEPTION 'Mapeamento de atributos inválido'; END IF;
 -- Uma publicação de cada vez; liberação automática no fim da transação.
 IF NOT pg_try_advisory_xact_lock(726314902781::bigint) THEN
  RAISE EXCEPTION 'Já existe uma atualização mensal em execução. Tente novamente depois';
 END IF;
 FOR v_id, v_padrao IN SELECT * FROM (VALUES
   (p_id_falha, 'falha'), (p_id_nao_entregue, 'n[aã]o.*entreg'),
   (p_id_impedimento, 'imped')) AS x(id, padrao)
 LOOP
  IF NOT EXISTS (
   SELECT 1 FROM public.custom_attributes_userstorycustomattribute a
   WHERE (to_jsonb(a)->>'id')::bigint=v_id
     AND (to_jsonb(a)->>'project_id')::bigint=p_projeto_id
     AND LOWER(to_jsonb(a)->>'name') ~ v_padrao
  ) THEN RAISE EXCEPTION 'Atributo % não corresponde ao campo % no projeto %', v_id, v_padrao, p_projeto_id;
  END IF;
 END LOOP;

 CREATE TEMP TABLE IF NOT EXISTS rci_snapshot_mensal_v2(tipo text, raw jsonb) ON COMMIT DROP;
 TRUNCATE pg_temp.rci_snapshot_mensal_v2;
 -- Uma instrução para capturar as fontes no mesmo snapshot do PostgreSQL.
 INSERT INTO pg_temp.rci_snapshot_mensal_v2
 SELECT 'sprint', to_jsonb(s) FROM public.milestones_milestone s
 WHERE (to_jsonb(s)->>'project_id')::bigint=p_projeto_id
 UNION ALL
 SELECT 'historia', to_jsonb(u) || jsonb_build_object('_atributos', cv.attributes_values)
 FROM public.userstories_userstory u
 LEFT JOIN public.custom_attributes_userstorycustomattributesvalues cv ON cv.user_story_id=u.id
 WHERE (to_jsonb(u)->>'project_id')::bigint=p_projeto_id
 UNION ALL
 SELECT 'ausencia', to_jsonb(a) FROM taiga_schema.ausencias_raw a;

 IF NOT EXISTS (SELECT 1 FROM pg_temp.rci_snapshot_mensal_v2 WHERE tipo='sprint')
 THEN RAISE EXCEPTION 'Projeto sem sprints visíveis. Confira conexão, projeto e permissões'; END IF;
 IF p_permitir_fonte_vazia IS DISTINCT FROM true AND (
   (NOT EXISTS (SELECT 1 FROM pg_temp.rci_snapshot_mensal_v2 WHERE tipo='historia')
    AND EXISTS (SELECT 1 FROM rci_embratur.f_userstories_mensal_v2
                WHERE projeto_id=p_projeto_id AND presente_na_origem))
   OR (NOT EXISTS (SELECT 1 FROM pg_temp.rci_snapshot_mensal_v2 WHERE tipo='ausencia')
    AND EXISTS (SELECT 1 FROM rci_embratur.f_ausencias_eventos_mensal_v2
                WHERE projeto_id=p_projeto_id AND presente_na_origem))
 ) THEN RAISE EXCEPTION 'Fonte antes preenchida ficou vazia. Publicação bloqueada para conferência'; END IF;
 IF EXISTS (
  SELECT 1 FROM pg_temp.rci_snapshot_mensal_v2
  GROUP BY tipo, raw->>'id', raw->>'ID' HAVING COUNT(*)>1
 ) THEN RAISE EXCEPTION 'Chave duplicada nas fontes. Nenhuma publicação realizada'; END IF;
 IF EXISTS (
  SELECT 1 FROM pg_temp.rci_snapshot_mensal_v2
  WHERE (tipo IN ('sprint','historia') AND NULLIF(raw->>'id','') IS NULL)
     OR (tipo='ausencia' AND NULLIF(raw->>'ID','') IS NULL)
 ) THEN RAISE EXCEPTION 'Registro de origem sem ID'; END IF;

 CREATE TEMP TABLE IF NOT EXISTS rci_sprints_stage_v2 (
  sprint_id bigint PRIMARY KEY, nome text, inicio date, fim date, fechada boolean
 ) ON COMMIT DROP;
 TRUNCATE pg_temp.rci_sprints_stage_v2;
 INSERT INTO pg_temp.rci_sprints_stage_v2
 SELECT (raw->>'id')::bigint,
  COALESCE(NULLIF(BTRIM(raw->>'name'),''), 'Sprint #'||(raw->>'id')),
  NULLIF(raw->>'estimated_start','')::date,
  NULLIF(raw->>'estimated_finish','')::date,
  rci_embratur.fn_booleano_mensal_v2(raw->>'closed')
 FROM pg_temp.rci_snapshot_mensal_v2 WHERE tipo='sprint';
 IF EXISTS (SELECT 1 FROM pg_temp.rci_sprints_stage_v2
  WHERE inicio IS NULL OR fim IS NULL OR fechada IS NULL OR fim<inicio
    OR NOT ISFINITE(inicio) OR NOT ISFINITE(fim)
 ) THEN RAISE EXCEPTION 'Sprint com datas ou estado closed inválidos. Corrija a origem'; END IF;

 CREATE TEMP TABLE IF NOT EXISTS rci_historias_stage_v2 (
  id bigint PRIMARY KEY, ref bigint, sprint_id bigint, subject text, fechada boolean,
  falha boolean, nao_entregue boolean, impedimento boolean,
  criacao timestamptz, modificacao timestamptz, conclusao timestamptz
 ) ON COMMIT DROP;
 TRUNCATE pg_temp.rci_historias_stage_v2;
 INSERT INTO pg_temp.rci_historias_stage_v2
 SELECT (raw->>'id')::bigint, (raw->>'ref')::bigint,
  NULLIF(raw->>'milestone_id','')::bigint, raw->>'subject',
  rci_embratur.fn_booleano_mensal_v2(raw->>'is_closed'),
  rci_embratur.fn_booleano_mensal_v2(raw->'_atributos'->>p_id_falha::text),
  rci_embratur.fn_booleano_mensal_v2(raw->'_atributos'->>p_id_nao_entregue::text),
  rci_embratur.fn_booleano_mensal_v2(raw->'_atributos'->>p_id_impedimento::text),
  rci_embratur.fn_instante_mensal_v2(raw->>'created_date'),
  rci_embratur.fn_instante_mensal_v2(raw->>'modified_date'),
  rci_embratur.fn_instante_mensal_v2(raw->>'finish_date')
 FROM pg_temp.rci_snapshot_mensal_v2 WHERE tipo='historia';
 IF EXISTS (SELECT 1 FROM pg_temp.rci_historias_stage_v2 u
  WHERE u.fechada IS NULL OR (u.sprint_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM pg_temp.rci_sprints_stage_v2 s WHERE s.sprint_id=u.sprint_id))
 ) THEN RAISE EXCEPTION 'História sem estado ou ligada a sprint fora do projeto selecionado'; END IF;

 CREATE TEMP TABLE IF NOT EXISTS rci_ausencias_stage_v2 (
  id bigint PRIMARY KEY, chave text, nome text,
  inicio date, fim date, hora_inicio time, hora_fim time
 ) ON COMMIT DROP;
 TRUNCATE pg_temp.rci_ausencias_stage_v2;
 INSERT INTO pg_temp.rci_ausencias_stage_v2
 SELECT (raw->>'ID')::bigint,
  LOWER(REGEXP_REPLACE(BTRIM(raw->>'Nome do Colaborador Ausente:'), '[[:space:]]+', ' ', 'g')),
  BTRIM(raw->>'Nome do Colaborador Ausente:'),
  -- A exportação de estrutura confirmou timestamps, não texto DD/MM ou MM/DD.
  NULLIF(raw->>'Data início da ausência','')::timestamp::date,
  NULLIF(raw->>'Data Fim da ausência','')::timestamp::date,
  NULLIF(BTRIM(raw->>'Hora Início da Ausência'),'')::time,
  NULLIF(BTRIM(raw->>'Hora Fim da Ausência'),'')::time
 FROM pg_temp.rci_snapshot_mensal_v2 WHERE tipo='ausencia';
 IF EXISTS (SELECT 1 FROM pg_temp.rci_ausencias_stage_v2
  WHERE NULLIF(chave,'') IS NULL OR inicio IS NULL OR fim IS NULL OR fim<inicio
    OR NOT ISFINITE(inicio) OR NOT ISFINITE(fim)
    OR (hora_inicio IS NULL) <> (hora_fim IS NULL)
    OR (inicio=fim AND hora_inicio IS NOT NULL AND hora_fim<=hora_inicio)
 ) THEN RAISE EXCEPTION 'Ausência inválida: confira nome, datas, horários e ID. Publicação cancelada'; END IF;

 SELECT LEAST(DATE_TRUNC('month',p_inicio)::date,
              (SELECT MIN(inicio) FROM pg_temp.rci_sprints_stage_v2),
              (SELECT MIN(inicio) FROM pg_temp.rci_ausencias_stage_v2),
              (SELECT MIN(data) FROM rci_embratur.d_calendario)),
        GREATEST((DATE_TRUNC('year', CURRENT_DATE)+INTERVAL '3 years - 1 day')::date,
              (SELECT MAX(fim) FROM pg_temp.rci_sprints_stage_v2),
              (SELECT MAX(fim) FROM pg_temp.rci_ausencias_stage_v2),
              (SELECT MAX(data) FROM rci_embratur.d_calendario))
 INTO v_inicio, v_fim;
 CALL rci_embratur.sp_calendario_mensal_v2(v_inicio, v_fim);

 -- Alterações de ausências exigem nova conferência nos meses afetados.
 WITH mudancas AS (
  SELECT a.data_inicio AS inicio_antigo,a.data_fim AS fim_antigo,
         b.inicio AS inicio_novo,b.fim AS fim_novo
  FROM (SELECT * FROM rci_embratur.f_ausencias_eventos_mensal_v2
        WHERE projeto_id=p_projeto_id AND presente_na_origem) a
  FULL JOIN pg_temp.rci_ausencias_stage_v2 b ON b.id=a.origem_id
  WHERE ROW(a.origem_id,a.colaborador_chave,a.nome_colaborador,a.data_inicio,a.data_fim,a.hora_inicio,a.hora_fim)
    IS DISTINCT FROM ROW(b.id,b.chave,b.nome,b.inicio,b.fim,b.hora_inicio,b.hora_fim)
 )
 UPDATE rci_embratur.parametros_mes_v2 p SET ausencias_conferidas=false
 WHERE p.projeto_id=p_projeto_id AND EXISTS (
  SELECT 1 FROM mudancas m
  WHERE (p.competencia<=m.fim_antigo AND (p.competencia+INTERVAL '1 month')::date>m.inicio_antigo)
     OR (p.competencia<=m.fim_novo AND (p.competencia+INTERVAL '1 month')::date>m.inicio_novo)
 );

 -- Publicação atômica: registros removidos da fonte ficam inativos, sem apagar histórico.
 UPDATE rci_embratur.d_sprints_mensal_v2 SET presente_na_origem=false WHERE projeto_id=p_projeto_id;
 INSERT INTO rci_embratur.d_sprints_mensal_v2
 SELECT p_projeto_id,sprint_id,nome,inicio,fim,fechada,true FROM pg_temp.rci_sprints_stage_v2
 ON CONFLICT (projeto_id,sprint_id) DO UPDATE SET
  sprint_name=EXCLUDED.sprint_name,inicio=EXCLUDED.inicio,fim=EXCLUDED.fim,
  fechada=EXCLUDED.fechada,presente_na_origem=true;
 UPDATE rci_embratur.f_userstories_mensal_v2 SET presente_na_origem=false WHERE projeto_id=p_projeto_id;
 INSERT INTO rci_embratur.f_userstories_mensal_v2
 SELECT p_projeto_id,id,ref,sprint_id,subject,fechada,falha,nao_entregue,impedimento,
        criacao,modificacao,conclusao,true FROM pg_temp.rci_historias_stage_v2
 ON CONFLICT (projeto_id,userstory_id) DO UPDATE SET
  ref=EXCLUDED.ref,sprint_id=EXCLUDED.sprint_id,subject=EXCLUDED.subject,
  is_closed=EXCLUDED.is_closed,item_com_falha=EXCLUDED.item_com_falha,
  nao_entregue=EXCLUDED.nao_entregue,impedimento=EXCLUDED.impedimento,
  created_date=EXCLUDED.created_date,modified_date=EXCLUDED.modified_date,
  finish_date=EXCLUDED.finish_date,presente_na_origem=true;
 UPDATE rci_embratur.f_ausencias_eventos_mensal_v2 SET presente_na_origem=false WHERE projeto_id=p_projeto_id;
 INSERT INTO rci_embratur.f_ausencias_eventos_mensal_v2
 SELECT p_projeto_id,id,chave,nome,inicio,fim,hora_inicio,hora_fim,true
 FROM pg_temp.rci_ausencias_stage_v2
 ON CONFLICT (projeto_id,origem_id) DO UPDATE SET
  colaborador_chave=EXCLUDED.colaborador_chave,nome_colaborador=EXCLUDED.nome_colaborador,
  data_inicio=EXCLUDED.data_inicio,data_fim=EXCLUDED.data_fim,
  hora_inicio=EXCLUDED.hora_inicio,hora_fim=EXCLUDED.hora_fim,presente_na_origem=true;

 INSERT INTO rci_embratur.parametros_mes_v2 (projeto_id,competencia,postos_trabalho)
 SELECT p_projeto_id, m::date,
  CASE WHEN m::date=DATE_TRUNC('month',CURRENT_DATE)::date THEN p_postos_mes_atual END
 FROM GENERATE_SERIES(DATE_TRUNC('month',p_inicio), DATE_TRUNC('month',CURRENT_DATE), INTERVAL '1 month') m
 ON CONFLICT (projeto_id,competencia) DO NOTHING;
 -- Só o mês atual recebe os 7 postos confirmados; não inventa histórico de equipe.
 UPDATE rci_embratur.parametros_mes_v2 SET postos_trabalho=p_postos_mes_atual
 WHERE projeto_id=p_projeto_id AND competencia=DATE_TRUNC('month',CURRENT_DATE)::date;

 INSERT INTO rci_embratur.controle_carga_mensal_v2
 SELECT p_projeto_id,DATE_TRUNC('month',p_inicio)::date,CLOCK_TIMESTAMP(),
  (SELECT COUNT(*) FROM pg_temp.rci_sprints_stage_v2),
  (SELECT COUNT(*) FROM pg_temp.rci_historias_stage_v2),
  (SELECT COUNT(*) FROM pg_temp.rci_ausencias_stage_v2)
 ON CONFLICT (projeto_id) DO UPDATE SET
  inicio_cobertura=EXCLUDED.inicio_cobertura,ultima_publicacao=EXCLUDED.ultima_publicacao,
  qtd_sprints=EXCLUDED.qtd_sprints,qtd_historias=EXCLUDED.qtd_historias,
  qtd_ausencias=EXCLUDED.qtd_ausencias;
 -- Sem COMMIT interno: erro cancela toda a chamada, preservando a publicação anterior.
END $$;
