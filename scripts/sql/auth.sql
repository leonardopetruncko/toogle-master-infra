-- Gerado para o fase4-secrets.ps1: cria o banco (se não existir), as tabelas e os dados da demo.
-- Idempotente: pode rodar a cada sessão sem duplicar nada.
SELECT 'CREATE DATABASE auth_db' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'auth_db')\gexec
\c auth_db

CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    
    -- key_hash armazena o hash SHA-256 da chave, que tem 64 caracteres hexadecimais
    key_hash VARCHAR(64) NOT NULL UNIQUE, 
    
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
-- A chave do evaluation-service é inserida pelo script (hash SHA-256 calculado na hora).
