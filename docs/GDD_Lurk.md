
---

## 8. Decisiones acordadas (23/10/2026)

Aclaraciones del diseño tras la primera revisión. Prevalecen sobre las secciones anteriores si hay diferencias.

### 8.1. Plataforma y red
* El juego corre **dentro del launcher**, con opción de pantalla completa / ventana (F11 y menú de Escape). Los procesos independientes quedan para más adelante.
* **Servidor autoritativo** (el servidor del arcade en Render): simula la partida a tiempo fijo y envía a cada jugador **solo lo que ve** (la niebla se aplica en el servidor; así no se puede hacer trampa leyendo memoria).
* Se puede **entrar a una partida en curso**. Máximo 30 jugadores por party (pruebas reales con hasta 5).

### 8.2. Mapa
* El mapa más pequeño debe permitir a **5 jugadores acechar en silencio** sin cruzarse constantemente; el respawn debe poder elegir un punto razonablemente lejos de los demás.
* El mapa **crece** con el número de jugadores (por encima de 5).
* Los asteroides **chocan entre sí** (sin romperse) y se mueven despacio. **Las balas no los destruyen; los explosivos sí.**
* Gemas: aproximadamente **1 cada 400×400 px** de mapa.
* Power-ups: **5 en el mapa**, siempre alejados entre sí; **+1 por cada jugador** por encima de 5 (y el mapa crece).

### 8.3. Controles
* **WASD** mueve; **el ratón apunta y dispara**. Solo teclado y ratón (sin mando).
* **Misil (El Redentor):** se controla con el ratón; avanza siempre hacia delante y **gira suavemente** hacia el puntero (difícil de manejar a propósito, pero capaz de dar la vuelta). **Sin límite de tiempo**: se **detona a distancia** donde esté (o al impactar). Mientras tanto la nave queda quieta.

### 8.4. Reglas
* **Munición:** 3 balas; al gastarlas, recarga de 5 s. **No hay recarga manual.**
* **Arma Pesada:** recarga el cargador completo con balas en abanico (3 proyectiles por disparo); al gastarlo y recargar vuelve a balas normales.
* **Armadura de Crucero:** absorbe el daño antes que la vida; se muestra como **celdas extra tras la barra de vida**; acumulable hasta **+9**.
* **Visor Táctico** y demás power-ups: duran **hasta que mueres**.
* **Contenedor:** solo la **Sobrecarga del Reactor** viene dentro de una caja que hay que destruir; el resto aparece listo para recoger.
* **Delación** (disparar / choque fuerte): flecha en la pantalla de los rivales durante **3 s**.
* **Muerte:** no reapareces al instante: pulsas **cualquier tecla o clic** para reaparecer. Al reaparecer, **2 s de invulnerabilidad** (se pierde al disparar).
* **Autoría de las muertes:** si mueres y alguien te dañó en los **5 s anteriores**, la muerte es suya. Si te matas tú solo, nadie puntúa.

### 8.5. Puntuación e IA
* **+10** gema, **+25** power-up, **+100** eliminación. Solo **ranking en vivo** en la partida (no se guarda online).
* IA de dificultad media que **usa power-ups** y es capaz de matar al jugador.

### 8.6. Arte y sonido
* **Vector neon** con arte propio: naves y power-ups con vectores detallados; shaders llamativos (fuego del cohete; la Sobrecarga ilumina el entorno con un efecto de gas y proyecta sombras de los asteroides).
* Sonido: packs de **Kenney (CC0)**. Sin música por ahora; **ambiente espacial** de fondo.
