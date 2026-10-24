
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

### 8.7. Segunda ronda de decisiones (24/10/2026)
* **Luz:** la nave ilumina solo para su piloto; **las balas iluminan su túnel para todos**, igual que los destellos de impactos y explosiones, los misiles y el resplandor de la Sobrecarga.
* **Ruido:** dos indicadores con icono propio: **disparo** (mira) y **choque** (estallido). Los choques fuertes de naves y **los choques entre asteroides** también suenan; estos últimos solo se oyen de cerca (1800 px).
* **Explosivos y asteroides:** la Carga Explosiva (09) y el misil **esculpen** los asteroides: el cráter tiene borde irregular y, si la roca se parte, los trozos se separan; los fragmentos diminutos se desintegran. Las balas normales no les hacen nada. El misil, por su radio, alcanza varios asteroides.
* **Controles del misil:** clic derecho lo lanza (si tienes uno); se guía con el ratón; clic izquierdo lo detona donde esté.
* **Sobrecarga:** su caja aguanta tres balas; la Sobrecarga liberada deriva despacio y, al cogerla, la caja reaparece 45 s después en otro sitio.

### 8.8. Ajustes tras la primera prueba (24/10/2026)
* **Power-ups:** el doble — **10** en el mapa base (+2 por cada jugador por encima de 5). Una **flecha alrededor de la nave** (del color del power-up) apunta al más cercano.
* **Ruido de asteroides:** solo suena el choque entre **dos asteroides grandes**.
* **Recarga:** **3 s** (antes 5).
* **Choque fuerte:** resta **0.5** (antes 1).
* **Menú de Escape:** volumen general / efectos / ambiente, controles reasignables (moverse, disparar, misil) y pantalla (ventana o completa); se guarda en el dispositivo.
* **Sonido:** efectos de Kenney (CC0, ver `games/lurk/lurk/assets/sfx/CREDITS.txt`); los ruidos lejanos se oyen amortiguados desde su dirección; ambiente espacial generado por código; zumbido del motor propio.

### 8.9. Versión 0.2.0 (24/10/2026)
**Ajustes**
* **Balas propias:** se dibujan siempre desde la simulación local (sin saltos ni retraso); el servidor solo confirma o termina cada bala. El servidor guarda menos entradas en cola (menos latencia).
* **Choques:** por debajo del **25 %** de la velocidad máxima no hacen daño; por encima, igual que antes.
* **Nada dentro de las rocas:** gemas, power-ups y la caja nunca quedan dentro de un asteroide (las rocas, al moverse, los empujan fuera).
* **Radar:** cada eco aparece con su **icono** (y flecha si está fuera de la pantalla), como un ruido.
* **Sobrecarga:** visible desde mucho más lejos (5000 px); dura **15 s**. Su **caja** ilumina alrededor y se ve a través de la niebla.
* **El Redentor:** mientras lo guías **no hay niebla** en toda la pantalla; gira más rápido y su movimiento se predice en el cliente (sin saltos).
* **Power-ups según lo que ya tienes:** si un power-up del mapa no te serviría (permanente que ya tienes, Kit con la vida llena, Armadura al máximo), **para ti es otro** de la reserva (cambio individual: cada jugador puede ver uno distinto en el mismo sitio).
* **Disparos:** un 10 % más lentos y un 50 % más grandes. **Gemas:** suenan al recogerlas.

**Novedades**
* **Tienda de gemas** (Tab, reasignable): las gemas son la moneda de la partida y **no se pierden al morir**. Se elige el power-up exacto: **5** Kit · **10** Visor, Radar, Escudo, Armadura, Espectro, Psiónico · **15** Redentor, Arma Pesada, Carga Explosiva · **20** Sobrecarga, que aparece cerca, a la vista, con un glitch. La partida sigue mientras la tienda está abierta.
* **Rocas que dan gemas:** pulverizar un asteroide suelta **1-4 gemas** según su tamaño; partirlo, 1.
* **Asteroides brillantes** (~4 %): iluminan su entorno (también a través de la niebla, para todos); cualquier explosión los hace añicos y sueltan **12 gemas**.
* **Modo sigilo** (Shift izquierdo; alternar o mantener, a elegir en el menú): **mitad de velocidad**, más control y menos derrape, llama y motor discretos. **Sin sigilo**, el motor deja un **rastro de ruido** (icono propio) que oyen los rivales a menos de 900 px.
* **Disparar te expone:** durante **1,5 s** todos los jugadores ven tu nave a través de la niebla (además de la flecha de 3 s).

### 8.10. Versión 0.3.0 (24/10/2026)
* **Tienda:** la tecla la abre y cierra siempre (antes, tras comprar, se quedaba abierta). Se cierra sola al morir.
* **El Redentor:** mientras lo guías, la pantalla pasa a una **vista táctica de contornos rojos** con glitch, la cámara se **aleja un 25 %**, el misil deja una **estela de fuego rojo** que se disipa, y tu nave se queda quieta mirando hacia donde estaba.
* **Al morir:** niebla total (no se ve nada de lo que pasa, ni alrededor de tu nave destruida; solo las estrellas del fondo).
* **Contorno de asteroides** tenue justo más allá de tu visión (más tiempo de reacción a toda velocidad).
* **Gemas al morir:** **3 + 2 por cada mejora** que llevabas (cada efecto activo, cada misil y cada bloque de +3 de armadura).
* **Estrellas del fondo** visibles también en la niebla.
* La **llama** parpadea con la invulnerabilidad del respawn.
* Gemas y power-ups **siempre dentro del mapa**.
* **Registro** (arriba a la izquierda) con iconos: *X killed Y* · *X crashed* · *X exploded* · *X joined* · *X left*. La IA se llama **Clustark Ship**.
* **Radar:** la onda verde muestra los **contornos verdes** de lo que hay en pantalla a su paso, y se apagan antes de la siguiente.
* La **barra de recarga** empieza vacía (antes aparecía con un tercio ya cargado).
