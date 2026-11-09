-- Somente leitura. Execute cada SELECT separadamente, na mesma conexão da carga.
-- 1. Confirma definição instalada, quantidade de argumentos e padrões.
SELECT n.nspname AS schema_rotina, p.proname AS rotina,
       p.prokind AS tipo, p.pronargs AS argumentos,
       p.pronargdefaults AS argumentos_com_padrao,
       p.prosrc AS codigo_instalado
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='rci_embratur'
  AND p.proname='sp_atualizar_rci_mensal_v2';

-- 2. Origem e destinos: fontes preenchidas não comprovam execução da carga.
SELECT 'sprints_fonte_salesforce' AS verificacao, COUNT(*) AS quantidade
FROM public.milestones_milestone WHERE project_id=3
UNION ALL
SELECT 'historias_fonte_salesforce', COUNT(*)
FROM public.userstories_userstory WHERE project_id=3
UNION ALL
SELECT 'publicacoes_salesforce', COUNT(*)
FROM rci_embratur.controle_carga_mensal_v2 WHERE projeto_id=3
UNION ALL
SELECT 'meses_salesforce', COUNT(*)
FROM rci_embratur.parametros_mes_v2 WHERE projeto_id=3;
