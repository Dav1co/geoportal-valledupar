"""[Code A] Base para la prueba de Chrome de «Etiqueta del último pago»: copia de producción (generar.rehacer: huella de campo c476f14d…) y, con «con», la
migración de este paquete; con «sin», la función publicada (para ver que la pantalla nueva sigue mostrando el periodo del consumo). NUNCA Supabase.
Solo crea o rehace bases emdupar_a_rf_pago* (rehacer_doble.py exige emdupar_a_rf*).
Uso: python3 -I base_chrome.py <base> con|sin      (-h: este uso)"""
import sys, json, pathlib, importlib.util
args = sys.argv[1:]
if any(a in ("-h", "--help") for a in args): print(__doc__); sys.exit(0)
raras = [a for a in args if a.startswith("-")]
if raras: print(f"Opción desconocida: {raras[0]}\n{__doc__}", file=sys.stderr); sys.exit(2)
if len(args) != 2 or not args[0].startswith("emdupar_a_rf_pago") or args[1] not in ("con", "sin"): print(__doc__, file=sys.stderr); sys.exit(2)
AQUI = pathlib.Path(__file__).resolve().parent
s = importlib.util.spec_from_file_location("gn", AQUI / "generar.py"); gn = importlib.util.module_from_spec(s); s.loader.exec_module(gn)
HL = json.loads((AQUI / "huellas_locales.json").read_text())
con = gn.rehacer(args[0])
if args[1] == "con":
    con.execute(gn.a_local((AQUI.parent / f"migracion_{gn.NOMBRE}_editor.sql").read_text()))
h = con.execute(gn.HUELLA["campo"]).fetchone()[0]
esperada = HL["nuevas"]["HUELLA_CAMPO_NUEVA"] if args[1] == "con" else HL["partida"]["HUELLA_CAMPO"]
if h != esperada: sys.exit(f"La huella de campo no es la esperada: {h}")
print(f"base {args[0]} lista ({args[1]} el paquete) · huella de campo {h}")
