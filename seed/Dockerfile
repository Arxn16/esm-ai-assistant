# Derived from official mysql image (our base image)
# Pinned to 8.2 to match the existing data dir version in databases/mysql
# (MySQL refuses to open an 8.2 datadir with 9.x).
FROM mysql:8.2
# Add a database
ENV MYSQL_DATABASE soup_esm_emr
# Add the content of the sql-scripts/ directory to your image
# All scripts in docker-entrypoint-initdb.d/ are automatically
# executed during container startup
COPY seed.sql /docker-entrypoint-initdb.d/

