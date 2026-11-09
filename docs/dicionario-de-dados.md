# Dicionário de dados

Os objetos abaixo pertencem a `rci_embratur`, salvo indicação em contrário. O inventário foi elaborado a partir dos SQLs do projeto e das configurações observadas durante a manutenção do painel.

## Tabelas persistentes do modelo mensal

| Objeto | Tipo e granularidade | Chave | Conteúdo |
|---|---|---|---|
| `d_calendario` | Dimensão, uma data | Índice único em `data` adicionado pelo pacote | Ano, semestre, trimestre, mês, nomes, semana, dia, fim de semana e referências mensais |
| `d_feriados_mensal_v2` | Dimensão auxiliar, um feriado por data | `data` | Descrição e data excluída da contagem de dias úteis |
| `d_sprints_mensal_v2` | Dimensão, uma sprint por projeto | `(projeto_id, sprint_id)` | Nome, início, fim previsto, fechamento e presença na origem |
| `f_userstories_mensal_v2` | Fato operacional, uma história por projeto | `(projeto_id, userstory_id)` | Sprint, referência, assunto, estado, flags e instantes de criação, alteração e conclusão |
| `f_ausencias_eventos_mensal_v2` | Fato de eventos, um registro do formulário por projeto | `(projeto_id, origem_id)` | Colaborador normalizado, datas, horários e presença na origem |
| `parametros_mes_v2` | Configuração, um projeto e mês | `(projeto_id, competencia)` | Postos, conferência de ausências e feriados, interpretação de flags vazias |
| `controle_carga_mensal_v2` | Controle, última carga por projeto | `projeto_id` | Cobertura inicial, instante da publicação e contagens de fontes |
| `f_fechamentos_mensal_v2` | Fato de resultados versionados, uma versão por projeto e mês | `(projeto_id, competencia, versao)` | Resultado aprovado em JSONB, instante e motivo da revisão |

O campo `presente_na_origem` existe nas histórias, sprints e eventos. Registros removidos das fontes ficam inativos no modelo. A carga precisa enxergar a origem completa do projeto para interpretar corretamente essas remoções.

## Views

| View | Grão | Transformação |
|---|---|---|
| `vw_calendario_diario_mensal_v2` | Uma data | Calendário enriquecido com feriado e condição de dia útil |
| `vw_ausencias_dia_mensal_v2` | Um colaborador, projeto e dia útil | Expande eventos, une intervalos sobrepostos e classifica fração de ausência |
| `vw_itens_mensal_v2` | Uma história | Acrescenta sprint, competência e data local de conclusão |
| `vw_rci_mensal_v2` | Um projeto e competência configurada | Agrega histórias, dias úteis, ausências e calcula indicadores e pendências |
| `vw_filtro_meses_v2` | Um projeto e competência | Competências disponíveis para apuração |
| `vw_rci_meses_fechados_v2` | Um projeto e competência publicada | Recupera a última versão aprovada e acrescenta os nomes atuais das sprints |
| `vw_filtro_meses_fechados_v2` | Um projeto e competência publicada | Competências efetivamente fechadas |

A view complementar `vw_sprints_meses_publicados_v2` foi criada durante a manutenção para consultar sprints de meses publicados. O gráfico separado de sprints foi retirado do layout a pedido da usuária. Os oito gráficos oficiais compartilham a view mensal publicada.

## Campos da apuração mensal

| Campo | Significado |
|---|---|
| `competencia` | Primeiro dia do mês de referência |
| `ano_mes` | Identificação `YYYY-MM` |
| `qib` | Histórias de sprints fechadas previstas para a competência |
| `qeb` | Histórias fechadas sem marcação explícita de não entrega |
| `qtd_nao_entregue` | Histórias com flag de não entrega |
| `qtd_item_falha` | Histórias com flag de falha |
| `qtd_impedimento` | Histórias com flag de impedimento, expostas para conferência |
| `abertas_sem_flag` | Histórias abertas sem flag de não entrega |
| `qda` | Soma dos dias equivalentes de ausência por colaborador e dia útil |
| `qdu` | Quantidade de dias úteis do mês |
| `postos_trabalho` | Capacidade de equipe configurada para a competência |
| `ies`, `ifb`, `iap` | Parcelas ponderadas que reduzem o RCI |
| `rci_preciso` | Resultado antes do arredondamento de apresentação |
| `rci` | Campo legado arredondado em duas casas |
| `situacao` | `PENDENTE`, `PARCIAL` ou `APURADO` |
| `pendencias` | Lista de condições que impedem a publicação |
| `meta_095` | Comparação do resultado preciso com a meta de 0,95 |
| `versao_fechamento`, `fechado_em`, `motivo_revisao` | Metadados acrescentados pela view publicada |
| `sprints_do_mes` | Nomes atuais das sprints fechadas concatenados por competência |
| `mes_com_sprints` | Mês abreviado e nomes das sprints para a categoria do gráfico de entregas |

`mes_rotulo`, `resultado_meta` e `fechado_em_brasilia` são colunas calculadas no dataset do Superset. Consulte [configuração dos gráficos](../superset/configuracao.md).

## Regras de ausência e capacidade

Eventos de um único dia com até quatro horas contam 0,5 dia. Acima de quatro horas contam um dia. Eventos sobrepostos do mesmo nome normalizado são unidos antes da classificação, com limite de um dia por colaborador e data. Eventos de vários dias contam os dias úteis inteiros, incluindo as pontas. Sábados, domingos e feriados cadastrados contribuem com zero.

A origem identifica colaboradores pelo nome. A normalização trata espaços e caixa. Diferenças de grafia precisam ser conciliadas na entrada para representar a mesma pessoa.

A configuração histórica confirmada é de 12 postos até setembro de 2026 e 7 a partir de outubro de 2026. Os postos são parâmetros por competência. Meses novos precisam ter sua configuração conferida.

## Fontes e objetos legados

As tabelas antigas `d_sprints`, `f_userstories`, `f_ausencias` e `f_indicadores_sprint`, além das views antigas de RCI por sprint, coexistem no ambiente. O pacote mensal usa objetos `_v2` e aproveita a dimensão `d_calendario` existente. A documentação apresenta as dependências utilizadas pelo painel mensal. Uma listagem de todos os objetos do banco pode ser obtida com as consultas de inventário incluídas em `sql/operacao`.
