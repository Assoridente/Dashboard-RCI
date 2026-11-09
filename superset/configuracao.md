# Configuração do dashboard no Superset

O dashboard `Indicadores RCI`, ID 19, usa a conexão `Taiga_1`. Os oito gráficos compartilham o dataset físico `rci_embratur.vw_rci_meses_fechados_v2`. Cada gráfico é filtrado pelo projeto 3.

## Filtro de competência

O controle é do tipo seleção de valor, baseado na coluna calculada `mes_rotulo`, com uma competência por vez. O valor padrão configurado é `Set 26`. O filtro precisa atingir os oito gráficos.

```sql
LEFT(nome_mes, 3) || ' ' || TO_CHAR(competencia, 'YY')
```

A métrica auxiliar `Ordem cronológica` usa `MAX(ano * 100 + mes)`. Para obter janeiro, fevereiro e os meses seguintes, selecione essa métrica na ordenação do filtro e use ordem crescente. A conclusão desse ajuste no filtro permanece pendente de conferência no ambiente.

## Cartões

| ID | Título | Expressão SQL da métrica | Formato |
|---|---|---|---|
| 14256806 | RCI | `CASE WHEN COUNT(*) = 1 THEN TRUNC(MAX(rci_preciso)::numeric, 3) END` | `,.3f` |
| 14256805 | IAP | `CASE WHEN COUNT(*) = 1 THEN MAX(iap) END` | `,.4f` |
| 14256803 | IES | `CASE WHEN COUNT(*) = 1 THEN MAX(ies) END` | `,.4f` |
| 14256804 | IFB | `CASE WHEN COUNT(*) = 1 THEN MAX(ifb) END` | `,.4f` |

Sem uma única competência, essas expressões retornam `NULL` e o Superset pode mostrar `No data`. Esse comportamento ainda existe na configuração registrada. Os componentes já estão ponderados e o RCI é calculado a partir de seu valor preciso.

## Demais gráficos

| ID | Título | Configuração principal |
|---|---|---|
| 14256810 | Resultado e fechamento mensal | Registros brutos com mês, `TRUNC(rci_preciso::numeric, 3)` rotulado como RCI, resultado da meta e instante de fechamento local |
| 14256809 | Entregas por mês | Barras com categoria `mes_com_sprints`, métricas de entregues e não entregues |
| 14256807 | Apuração das entregas do mês | Totais de QIB, QEB, não entregues e itens com falha |
| 14256808 | Ausências por mês | QDA, QDU, postos e IAP |

Na tabela de resultados, configure o formato numérico da coluna RCI como `,.3f`. A categoria `mes_com_sprints` vem da view e inclui o mês abreviado seguido dos nomes das sprints fechadas.

O fechamento é apresentado em Brasília a partir de `fechado_em`. A expressão de referência é `TO_CHAR(fechado_em AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')`. O resultado da meta utiliza `meta_095` para identificar se a meta foi alcançada.

## Reprodução da configuração

Cadastre a view publicada como dataset físico, sincronize as colunas e crie as colunas calculadas necessárias. Configure os gráficos e o filtro com as expressões acima. Se a edição for aberta a partir do dashboard, remova filtros temporários herdados do mês antes de salvar a definição permanente do gráfico.

Esta pasta documenta a configuração aplicada. Os arquivos de exportação anteriores a novembro guardados na pasta de trabalho pertencem a versões anteriores e não integram esta publicação como backup importável do estado atual.
