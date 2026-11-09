# Instalação e operação mensal

## Pré-requisitos

Use a conexão PostgreSQL do Taiga no SQL Lab, com permissão para criar objetos em `rci_embratur` e executar as procedures. As tabelas operacionais de histórias, sprints e atributos em `public`, a entrada `taiga_schema.ausencias_raw` e a tabela legada `rci_embratur.d_calendario` devem existir.

O arquivo `01_estrutura.sql` amplia o calendário existente. A instalação é uma migração do ambiente do projeto. Para um banco vazio, primeiro devem ser provisionadas as fontes e a estrutura legada do calendário com os tipos compatíveis.

## Instalação

1. Execute as consultas de `sql/operacao/00_conferir_fontes.sql`. Confirme projeto, tipos das fontes e atributos.
2. Execute `sql/instalacao/01_estrutura.sql`.
3. Execute `sql/instalacao/02_procedure.sql`.
4. Execute `sql/instalacao/03_views.sql`.
5. Execute `sql/instalacao/08_fechamento_mensal.sql`.
6. Execute `sql/instalacao/12_sprints_no_grafico_mensal.sql`, depois de 08, para acrescentar os nomes das sprints à view publicada.
7. Execute `sql/operacao/05_executar_carga_salesforce.sql` para fazer a primeira carga.
8. Confira e aplique `sql/operacao/07_configurar_salesforce_rio.sql`, que documenta a configuração histórica confirmada e os feriados de outubro/2025 a dezembro/2026.
9. Faça a conferência por mês e efetue o fechamento explícito da competência desejada.

No SQL Lab, execute cada bloco `CREATE FUNCTION` ou `CREATE PROCEDURE` inteiro, incluindo `$$`. Execute cada transação completa na mesma conexão. A view publicada só mostra competências que passaram pelo procedimento de fechamento.

O arquivo 07 marca conferências históricas como concluídas. Sua aplicação exige que a pessoa responsável tenha conferido esses dados. A lista de feriados requer manutenção para períodos posteriores a 2026.

## Atualização recorrente

Importe os registros atuais do formulário para `taiga_schema.ausencias_raw`, mantendo os IDs do formulário. As datas de ausência dessa tabela são timestamps. O CSV pode ser preparado com datas ISO e a importação precisa manter os tipos compatíveis. Confira os nomes para unificar grafias da mesma pessoa antes da carga.

Execute a atualização mensal.

```sql
BEGIN;
CALL rci_embratur.sp_atualizar_rci_mensal_v2(
    p_projeto_id => 3,
    p_ausencias_raw_sao_deste_projeto => true,
    p_postos_mes_atual => 7
);
COMMIT;
```

Confira o resultado da carga e as competências.

```sql
SELECT *
FROM rci_embratur.controle_carga_mensal_v2
WHERE projeto_id = 3;

SELECT ano_mes, qib, qeb, qda, qdu, postos_trabalho,
       ies, ifb, iap, rci_preciso, situacao, pendencias
FROM rci_embratur.vw_rci_mensal_v2
WHERE projeto_id = 3
ORDER BY competencia;
```

A chamada configura sete postos no mês corrente quando insere o parâmetro. Os meses históricos precisam ter o número correto explicitamente definido. Alterações de ausências desmarcam a conferência das competências afetadas. Depois de revisar a entrada e a contagem diária, atualize somente os parâmetros dos meses conferidos.

## Fechamento e revisão

O fechamento exige competência encerrada, relatório final importado, apuração sem pendências e carga posterior ao término do mês. A confirmação `p_relatorio_final_importado` deve corresponder à conferência efetiva do relatório.

```sql
-- Exemplo histórico. Substitua pela competência efetivamente conferida.
BEGIN;
CALL rci_embratur.sp_fechar_rci_mensal_v2(
    p_competencia => DATE '2026-09-01',
    p_relatorio_final_importado => true,
    p_projeto_id => 3,
    p_motivo_revisao => 'Revisão após conferência dos registros de ausência'
);
COMMIT;
```

Repetir o fechamento com os mesmos valores preserva a versão. Valores modificados em um mês já publicado exigem motivo e geram nova versão. As anteriores ficam em `f_fechamentos_mensal_v2`.

```sql
SELECT ano_mes, qda, qdu, postos_trabalho,
       TRUNC(rci_preciso::numeric, 3) AS rci_exibido,
       versao_fechamento, fechado_em
FROM rci_embratur.vw_rci_meses_fechados_v2
WHERE projeto_id = 3
ORDER BY competencia;
```

## Atualização do Superset

Após o fechamento, use a atualização do dashboard para renovar as consultas em cache. Views comuns refletem os dados publicados diretamente. Alterações no conjunto de colunas da view exigem sincronização das colunas do dataset.

O filtro mensal precisa ser aplicado antes de consultar os quatro cartões. As expressões atuais exigem uma competência. O comportamento observado ao limpar o filtro está documentado em [estado do painel](estado-do-painel.md).

## Conferências essenciais

- Validar unicidade de IDs e os tipos de datas e horários na entrada.
- Conferir o número de postos e os feriados para a competência.
- Verificar dias de ausência, sobreposições, grafias dos nomes e registros de teste.
- Conferir QIB, QEB, falhas, não entregues e sprints abertas.
- Resolver as pendências antes do fechamento.
- Comparar a consulta publicada com os cartões e tabelas após atualizar o cache.

`04_conferencia.sql` reúne as consultas de apoio. `06_diagnosticar_execucao.sql` ajuda a conferir a primeira carga. `inventario_banco.sql` lista a estrutura e os relacionamentos físicos declarados nos três schemas.
