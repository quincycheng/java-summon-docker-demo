CREATE DATABASE demo_db;

/* connect to it */

\c demo_db;

CREATE TABLE pets (
  id serial primary key,
  name varchar(256)
);

/* Create Application User */

CREATE USER demo_service_account PASSWORD 'YourStrongSAPassword';

/* Grant Permissions */

GRANT SELECT, INSERT ON public.pets TO demo_service_account;
GRANT USAGE, SELECT ON SEQUENCE public.pets_id_seq TO demo_service_account
