// Captura la vista previa del cocodrilo con el Chromium de Playwright.
// Uso (desde la raíz del repo):
//   python3 tools/generar_cocodrilo.py
//   python3 -m http.server 8765 &   # sirve el repo
//   node tools/vista_previa/capturar.mjs [salida.png] [ancho] [alto] [consulta extra]
import { createRequire } from "node:module";
const { chromium } = createRequire(import.meta.url)("playwright");

const [salida = "tools/vista_previa/captura.png", ancho = "720", alto = "1280", extra = ""] = process.argv.slice(2);
const navegador = await chromium.launch({ args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
const pagina = await navegador.newPage({ viewport: { width: +ancho, height: +alto } });
pagina.on("console", (m) => console.log("[página]", m.text()));
pagina.on("pageerror", (e) => console.log("[error]", e.message));
await pagina.goto(`http://localhost:8765/tools/vista_previa/index.html?w=${ancho}&h=${alto}${extra}`);
await pagina.waitForFunction(() => window.listo === true, null, { timeout: 30000 });
await pagina.screenshot({ path: salida });
await navegador.close();
console.log("Captura guardada en", salida);
