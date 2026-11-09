-- Regras confirmadas em 28/10/2026:
-- Salesforce 3; 12 postos até setembro/2026; 7 a partir de outubro/2026.
-- Ausências atualizadas; checkbox vazio significa não marcado.
-- Localidade adotada: município do Rio de Janeiro/RJ, capital.
-- Feriados gerais, sem pontos facultativos ou feriados de categorias específicas.
-- Abrangência cadastrada: outubro/2025 a dezembro/2026.
-- Fontes e notas em FERIADOS_RIO.md.
-- Execute TODO o arquivo na mesma execução do SQL Lab.
BEGIN;

INSERT INTO rci_embratur.d_feriados_mensal_v2(data,descricao) VALUES
 (DATE '2025-10-12','Nossa Senhora Aparecida - nacional'),
 (DATE '2025-11-02','Finados - nacional'),
 (DATE '2025-11-15','Proclamação da República - nacional'),
 (DATE '2025-11-20','Dia Nacional de Zumbi e da Consciência Negra - nacional'),
 (DATE '2025-12-25','Natal - nacional'),
 (DATE '2026-01-01','Confraternização Universal - nacional'),
 (DATE '2026-01-20','São Sebastião - municipal Rio de Janeiro'),
 (DATE '2026-02-17','Terça-feira de Carnaval - estadual RJ'),
 (DATE '2026-04-03','Paixão de Cristo'),
 (DATE '2026-04-21','Tiradentes - nacional'),
 (DATE '2026-04-23','São Jorge - estadual RJ'),
 (DATE '2026-05-01','Dia Mundial do Trabalho - nacional'),
 (DATE '2026-06-04','Corpus Christi - estadual RJ, Lei 11.002/2025'),
 (DATE '2026-09-07','Independência do Brasil - nacional'),
 (DATE '2026-10-12','Nossa Senhora Aparecida - nacional'),
 (DATE '2026-11-02','Finados - nacional'),
 (DATE '2026-11-15','Proclamação da República - nacional'),
 (DATE '2026-11-20','Dia Nacional de Zumbi e da Consciência Negra - nacional'),
 (DATE '2026-12-25','Natal - nacional')
ON CONFLICT(data) DO UPDATE SET descricao=EXCLUDED.descricao;

UPDATE rci_embratur.parametros_mes_v2
SET postos_trabalho=CASE WHEN competencia<DATE '2026-10-01' THEN 12 ELSE 7 END,
    ausencias_conferidas=true,
    feriados_conferidos=true,
    flags_vazias_significam_false=true
WHERE projeto_id=3
  AND competencia BETWEEN DATE '2025-10-01' AND DATE '2026-10-01';

COMMIT;

-- Views comuns refletem imediatamente a configuração, sem chamar a carga novamente.
SELECT ano_mes,qib,qeb,qtd_nao_entregue,qtd_item_falha,
       qda,qdu,postos_trabalho,ies,ifb,iap,rci,situacao,pendencias
FROM rci_embratur.vw_rci_mensal_v2
WHERE projeto_id=3 ORDER BY competencia;
