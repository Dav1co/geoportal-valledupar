"""[Code A] Base para las pruebas de la Edge y de Chrome de «Consultar direcciones»: copia de producción con el registro flexible publicado (generar.rehacer)
+ la migración de este paquete. NUNCA Supabase. Solo crea o rehace bases emdupar_a_rf_* (rehacer_doble.py lo exige).
Uso: python3 -I base_chrome.py <base>      (-h: este uso)"""
import sys, json, pathlib, importlib.util
args = sys.argv[1:]
if any(a in ("-h", "--help") for a in args): print(__doc__); sys.exit(0)
raras = [a for a in args if a.startswith("-")]
if raras: print(f"Opción desconocida: {raras[0]}\n{__doc__}", file=sys.stderr); sys.exit(2)
if len(args) != 1 or not args[0].startswith("emdupar_a_rf"): print(__doc__, file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent
s = importlib.util.spec_from_file_location("gn", AQUI / "generar.py"); gn = importlib.util.module_from_spec(s); s.loader.exec_module(gn)
HL = json.loads((AQUI / "huellas_locales.json").read_text())
con = gn.rehacer(args[0])
con.execute(gn.a_local((AQUI.parent / f"migracion_{gn.NOMBRE}_editor.sql").read_text(), None))
h = con.execute(gn.HUELLA["campo"]).fetchone()[0]
if h != HL["nuevas"]["HUELLA_CAMPO_NUEVA"]: sys.exit(f"La huella de campo tras migrar no es la esperada: {h}")
print(f"base {args[0]} lista · huella de campo {h}")
