-- Consultas de leitura. Execute separadamente no SQL Lab para inspecionar
-- a distribuição física dos objetos, tipos e restrições do ambiente.
SELECT table_schema, table_name, table_type
FROM information_schema.tables
WHERE table_schema IN ('public', 'taiga_schema', 'rci_embratur')
ORDER BY table_schema, table_type, table_name;

SELECT table_schema, table_name, ordinal_position, column_name,
       data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'rci_embratur'
ORDER BY table_name, ordinal_position;

SELECT tc.table_schema, tc.table_name, tc.constraint_name,
       tc.constraint_type, kcu.column_name, kcu.ordinal_position
FROM information_schema.table_constraints tc
LEFT JOIN information_schema.key_column_usage kcu
  ON kcu.constraint_catalog = tc.constraint_catalog
 AND kcu.constraint_schema = tc.constraint_schema
 AND kcu.constraint_name = tc.constraint_name
 AND kcu.table_name = tc.table_name
WHERE tc.table_schema = 'rci_embratur'
ORDER BY tc.table_name, tc.constraint_name, kcu.ordinal_position;

SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'rci_embratur'
ORDER BY tablename, indexname;
