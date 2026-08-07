-- Script SQL para limpar todos os dados de todas as tabelas de um banco PostgreSQL
-- Executa diretamente no PostgreSQL
--
-- ATENÇÃO: Esta operação irá REMOVER TODOS OS DADOS de todas as tabelas!
-- As tabelas e estruturas serão mantidas, apenas os dados serão removidos.
-- Esta ação NÃO PODE ser desfeita!
--
-- Uso:
--   psql -h localhost -p 5432 -U postgres -d commerce_platform_db -f sql/truncate-all-tables-postgres.sql
--
-- Ou via pipe:
--   cat sql/truncate-all-tables-postgres.sql | psql -h localhost -p 5432 -U postgres -d commerce_platform_db

BEGIN;

-- Limpar todos os dados das tabelas do schema public usando SQL dinâmico
DO $$
DECLARE
    r RECORD;
    table_count INTEGER := 0;
    rows_deleted INTEGER := 0;
BEGIN
    -- Desabilitar temporariamente triggers para melhor performance
    -- (opcional, mas pode ser necessário dependendo da configuração)
    
    -- Listar e limpar todas as tabelas
    FOR r IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
        ORDER BY tablename
    ) LOOP
        BEGIN
            -- TRUNCATE é mais eficiente que DELETE para limpar todas as linhas
            -- CASCADE: também limpa tabelas relacionadas via foreign keys
            -- RESTART IDENTITY: reseta sequências (AUTO_INCREMENT)
            EXECUTE format('TRUNCATE TABLE %I CASCADE RESTART IDENTITY', r.tablename);
            table_count := table_count + 1;
            RAISE NOTICE 'Dados limpos da tabela: %', r.tablename;
        EXCEPTION
            WHEN OTHERS THEN
                -- Se falhar (ex: tabela sem permissão), continua com as outras
                RAISE WARNING 'Erro ao limpar tabela %: %', r.tablename, SQLERRM;
        END;
    END LOOP;
    
    IF table_count = 0 THEN
        RAISE NOTICE 'Nenhuma tabela encontrada no schema public.';
    ELSE
        RAISE NOTICE 'Total de tabelas limpas: %', table_count;
    END IF;
END $$;

-- Verificar quantas linhas ainda existem nas tabelas
DO $$
DECLARE
    r RECORD;
    total_rows BIGINT := 0;
    table_with_data INTEGER := 0;
BEGIN
    -- Contar linhas em todas as tabelas
    FOR r IN (
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public'
        ORDER BY tablename
    ) LOOP
        BEGIN
            EXECUTE format('SELECT COUNT(*) FROM %I', r.tablename) INTO total_rows;
            IF total_rows > 0 THEN
                table_with_data := table_with_data + 1;
                RAISE WARNING 'Tabela % ainda contém % linha(s).', r.tablename, total_rows;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                -- Ignora erros de contagem
                NULL;
        END;
    END LOOP;
    
    IF table_with_data = 0 THEN
        RAISE NOTICE 'Limpeza concluída! Todas as tabelas estão vazias.';
    ELSE
        RAISE WARNING 'Ainda existem dados em % tabela(s).', table_with_data;
    END IF;
END $$;

COMMIT;

-- Mensagem final
SELECT 'Todos os dados foram removidos com sucesso! As tabelas foram mantidas.' AS resultado;

