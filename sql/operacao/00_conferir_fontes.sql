-- Somente leitura. Execute cada SELECT separadamente no SQL Lab.
SELECT id, name FROM public.projects_project ORDER BY id;

SELECT to_jsonb(a)->>'project_id' AS projeto_id,
       to_jsonb(a)->>'id' AS atributo_id,
       to_jsonb(a)->>'name' AS atributo_nome,
       to_jsonb(a)->>'type' AS tipo
FROM public.custom_attributes_userstorycustomattribute a
ORDER BY 1, 2;

SELECT to_jsonb(s)->>'project_id' AS projeto_id,
       COUNT(*) AS sprints,
       COUNT(*) FILTER (WHERE to_jsonb(s)->>'closed' = 'true') AS fechadas,
       MIN(s.estimated_start) AS inicio,
       MAX(s.estimated_finish) AS fim
FROM public.milestones_milestone s GROUP BY 1 ORDER BY 1;

SELECT COUNT(*) AS registros, COUNT(DISTINCT "ID") AS ids_distintos,
       COUNT(*) FILTER (WHERE "ID" IS NULL) AS ids_nulos,
       MIN("Data início da ausência") AS menor_data,
       MAX("Data Fim da ausência") AS maior_data
FROM taiga_schema.ausencias_raw;
