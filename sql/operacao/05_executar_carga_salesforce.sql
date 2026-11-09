-- Executar após instalar 01_estrutura.sql, 02_procedure.sql e 03_views.sql.
-- Salesforce: projeto 3. Ausências exclusivas desse projeto, confirmado pelo usuário.
-- Sete postos no mês atual; atributos conferidos no Taiga.
-- Execute TODO o bloco na mesma execução/conexão do SQL Lab.
-- COMMIT explícito e consulta final permitem verificar persistência da carga.
BEGIN;
CALL rci_embratur.sp_atualizar_rci_mensal_v2(
 p_projeto_id => 3,
 p_ausencias_raw_sao_deste_projeto => true,
 p_postos_mes_atual => 7,
 p_id_falha => 1,
 p_id_nao_entregue => 4,
 p_id_impedimento => 3
);
COMMIT;

SELECT projeto_id,ultima_publicacao,qtd_sprints,qtd_historias,qtd_ausencias
FROM rci_embratur.controle_carga_mensal_v2
WHERE projeto_id=3;
