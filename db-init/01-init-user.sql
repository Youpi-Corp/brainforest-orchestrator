-- Initialize database user and permissions
-- This script runs when the PostgreSQL container first starts

-- Create the application user if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_user WHERE usename = 'brainforest_user') THEN
        CREATE USER brainforest_user WITH PASSWORD 'secure_db_password';
    END IF;
END
$$;

-- Create the production database if it doesn't exist
SELECT 'CREATE DATABASE brainforest_prod OWNER brainforest_user'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'brainforest_prod')\gexec

-- Grant necessary privileges
GRANT ALL PRIVILEGES ON DATABASE brainforest_prod TO brainforest_user;

-- Connect to the production database
\c brainforest_prod

-- Grant schema privileges
GRANT ALL ON SCHEMA public TO brainforest_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO brainforest_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO brainforest_user;

-- Grant future privileges
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO brainforest_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO brainforest_user;
