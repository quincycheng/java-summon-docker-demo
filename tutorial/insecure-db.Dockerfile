FROM postgres:9.3
COPY database.sql /docker-entrypoint-initdb.d/init.sql
ENV POSTGRES_PASSWORD YourStrongPGPassword
