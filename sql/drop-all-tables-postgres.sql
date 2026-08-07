-- Script SQL para remover todas as tabelas de um banco PostgreSQL
-- Executa diretamente no PostgreSQL
--
-- ATENÇÃO: Esta operação irá REMOVER TODAS AS TABELAS do banco de dados!
-- Esta ação NÃO PODE ser desfeita!
--
-- Uso:
--   psql -h localhost -p 5432 -U postgres -d commerce_platform_db -f scripts/drop-all-tables.sql
--
-- Ou via pipe:
--   cat scripts/drop-all-tables.sql | psql -h localhost -p 5432 -U postgres -d commerce_platform_db

BEGIN;

-- Remover todas as tabelas do schema public usando SQL dinâmico
DO $$
DECLARE
    r RECORD;
    table_count INTEGER := 0;
BEGIN
    -- Listar e remover todas as tabelas
    FOR r IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
        ORDER BY tablename
    ) LOOP
        EXECUTE format('DROP TABLE IF EXISTS %I CASCADE', r.tablename);
        table_count := table_count + 1;
        RAISE NOTICE 'Tabela removida: %', r.tablename;
    END LOOP;
    
    IF table_count = 0 THEN
        RAISE NOTICE 'Nenhuma tabela encontrada no schema public.';
    ELSE
        RAISE NOTICE 'Total de tabelas removidas: %', table_count;
    END IF;
END $$;

-- Remover tipos ENUM customizados após remover tabelas
DO $$
DECLARE
    r RECORD;
    enum_count INTEGER := 0;
BEGIN
    -- Listar e remover todos os tipos ENUM do schema public
    FOR r IN (
        SELECT typname 
        FROM pg_type 
        WHERE typtype = 'e' 
        AND typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
        ORDER BY typname
    ) LOOP
        EXECUTE format('DROP TYPE IF EXISTS %I CASCADE', r.typname);
        enum_count := enum_count + 1;
        RAISE NOTICE 'Tipo ENUM removido: %', r.typname;
    END LOOP;
    
    IF enum_count = 0 THEN
        RAISE NOTICE 'Nenhum tipo ENUM encontrado no schema public.';
    ELSE
        RAISE NOTICE 'Total de tipos ENUM removidos: %', enum_count;
    END IF;
END $$;

-- Verificar se ainda existem tabelas
DO $$
DECLARE
    remaining_tables INTEGER;
BEGIN
    SELECT COUNT(*) INTO remaining_tables
    FROM pg_tables 
    WHERE schemaname = 'public';
    
    IF remaining_tables > 0 THEN
        RAISE WARNING 'Ainda existem % tabela(s) no schema public.', remaining_tables;
    ELSE
        RAISE NOTICE 'Limpeza concluída! Nenhuma tabela restante no schema public.';
    END IF;
END $$;

COMMIT;

-- Mensagem final
SELECT 'Todas as tabelas foram removidas com sucesso!' AS resultado;

