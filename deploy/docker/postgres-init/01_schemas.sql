-- Create dedicated users
CREATE USER traccar_user WITH PASSWORD 'dSIVRok6jl4YakptQICM7B6j9YNmW3NjBM1niBw8G28=';
CREATE USER relay_user   WITH PASSWORD '4zDi63nGzQNolg7+4LLoOj2Iojf3RuHcgxOSau5oJGc=';

-- Create schemas owned by their respective users
CREATE SCHEMA traccar AUTHORIZATION traccar_user;
CREATE SCHEMA relay   AUTHORIZATION relay_user;

-- Grant connect to the database
GRANT CONNECT ON DATABASE postgres TO traccar_user;
GRANT CONNECT ON DATABASE postgres TO relay_user;

-- Explicit: relay_user has NO access to traccar schema
-- traccar_user has NO access to relay schema
REVOKE ALL ON SCHEMA traccar FROM relay_user;
REVOKE ALL ON SCHEMA relay   FROM traccar_user;
