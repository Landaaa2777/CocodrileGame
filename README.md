# ASCEND · Glow Up

Web de comunidad de mejora personal (glow up) con estética 2026: modo oscuro, barra de cristal, luz de estudio violeta y cian, y diseño en tres columnas.

## Qué incluye

- **Foro** con temas de ejemplo: piel, pelo y barba, fitness, estilo, hábitos y mentalidad.
- **Filtros**: por categoría, buscador (atajo `/`) y orden por Tendencia, Nuevos o Top.
- **Votos, nuevos temas y respuestas** en un panel lateral.
- **Reto diario** de 6 hábitos que alimenta el *Glow Score* (anillo de 0 a 100) y se reinicia cada día.
- **Perfil** con nombre de usuario y objetivos.
- Diseño adaptado a móvil.

Todo lo que hace el visitante (votos, temas, respuestas, perfil y hábitos) se guarda en el `localStorage` de su navegador. No hay servidor: para que los temas se compartan entre usuarios hay que conectar un backend.

## Cómo verla

Abre `index.html` en el navegador o sírvela con cualquier servidor estático:

```bash
python3 -m http.server 8000
# http://localhost:8000
```

## Archivos

- `index.html`: la página completa (HTML, CSS y JS en un solo archivo).
- `assets/glow-up.png`: miniatura del antes y después que aparece en el post destacado.
