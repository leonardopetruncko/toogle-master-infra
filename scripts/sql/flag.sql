-- Gerado para o fase4-secrets.ps1: cria o banco (se não existir), as tabelas e os dados da demo.
-- Idempotente: pode rodar a cada sessão sem duplicar nada.
SELECT 'CREATE DATABASE flag_db' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'flag_db')\gexec
\c flag_db

CREATE TABLE IF NOT EXISTS flags (
    id SERIAL PRIMARY KEY,

    -- 'name' é a chave de negócio única (ex: 'enable-new-checkout')
    name VARCHAR(100) UNIQUE NOT NULL, 
    
    description TEXT,
    
    -- Este é o 'kill switch' global. Se for false, a flag está desativada para todos.
    is_enabled BOOLEAN NOT NULL DEFAULT false,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Opcional, mas boa prática: Trigger para atualizar 'updated_at' automaticamente
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Remove o trigger se já existir, para evitar erro na recriação
DROP TRIGGER IF EXISTS set_timestamp ON flags;

CREATE TRIGGER set_timestamp
BEFORE UPDATE ON flags
FOR EACH ROW
EXECUTE PROCEDURE trigger_set_timestamp();
-- Flags de demonstração
INSERT INTO flags (name, description, is_enabled) VALUES
  ('enable-new-checkout', 'Novo fluxo de checkout', true),
  ('dark-mode', 'Tema escuro no app', true),
  ('beta-banner', 'Banner do programa beta', false)
ON CONFLICT (name) DO NOTHING;
