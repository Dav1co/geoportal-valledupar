"""Sustituto local de «pgserver» para los arneses de campo: en vez de bajar y levantar un PostgreSQL temporal, crea una base nueva en el
clúster local propio (localhost:55434). CAMPO_DB fija el nombre (se rehace si existe); sin ella, uno temporal que cleanup() borra."""
import os, uuid, psycopg
ADMIN = "postgresql://postgres@localhost:55434/postgres"
class _Servidor:
    def __init__(self):
        self.fija = os.environ.get("CAMPO_DB")
        self.db = self.fija or ("campo_tmp_" + uuid.uuid4().hex[:10])
        assert self.db.startswith("campo_"), self.db
        with psycopg.connect(ADMIN, autocommit=True) as c:
            c.execute(f'drop database if exists "{self.db}" with (force)')
            # los roles son del clúster, no de la base: el molde de campo los crea sin «if not exists», así que se quitan antes (este clúster es solo de estas pruebas)
            for (r,) in c.execute("select rolname from pg_roles where not rolsuper and rolname !~ '^pg_'").fetchall():
                try: c.execute(f'drop role "{r}"')
                except Exception: pass
            c.execute(f'create database "{self.db}"')
    def get_uri(self): return f"postgresql://postgres@localhost:55434/{self.db}"
    def cleanup(self):
        if self.fija: return
        with psycopg.connect(ADMIN, autocommit=True) as c: c.execute(f'drop database if exists "{self.db}" with (force)')
def get_server(_dir=None, **_k): return _Servidor()
