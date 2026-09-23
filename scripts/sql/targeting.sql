-- Gerado para o fase4-secrets.ps1: cria o banco (se não existir), as tabelas e os dados da demo.
-- Idempotente: pode rodar a cada sessão sem duplicar nada.
SELECT 'CREATE DATABASE targeting_db' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'targeting_db')\gexec
\c targeting_db

CREATE TABLE IF NOT EXISTS targeting_rules (
    id SERIAL PRIMARY KEY,

    -- 'flag_name' é a chave de negócio única. 
    -- Cada flag pode ter no máximo UMA regra de segmentação.
    flag_name VARCHAR(100) UNIQUE NOT NULL,
    
    -- Se a regra de segmentação em si está ativa ou não
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    
    -- Armazena a lógica da regra como um JSON.
    -- Ex: {"type": "PERCENTAGE", "value": 50}
    -- Ex: {"type": "USER_LIST", "values": ["u1", "u2"]}
    rules JSONB NOT NULL,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Trigger para atualizar 'updated_at' automaticamente (igual ao do flag-service)
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_timestamp ON targeting_rules;

CREATE TRIGGER set_timestamp
BEFORE UPDATE ON targeting_rules
FOR EACH ROW
EXECUTE PROCEDURE trigger_set_timestamp();
-- Regra de demonstração: 50% dos usuários recebem o novo checkout
INSERT INTO targeting_rules (flag_name, is_enabled, rules) VALUES
  ('enable-new-checkout', true, '{"type": "PERCENTAGE", "value": 50}'),
  ('dark-mode', true, '{"type": "PERCENTAGE", "value": 100}')
ON CONFLICT (flag_name) DO NOTHING;
