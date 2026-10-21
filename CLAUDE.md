# Directrices y Estándares de Desarrollo del Proyecto

## 1. Convenciones de Nomenclatura e Idioma

* **Código Fuente:** Todos los identificadores en el código (variables, funciones, clases, métodos, constantes y nombres de archivos, carpetas) deben escribirse estrictamente en **inglés**. Los comentarios explicativos dentro del código quedan exentos de esta norma y pueden adaptarse según convenga. (Los comentarios estaran en español.)

* **Interfaz de Usuario (UI):** Cualquier texto visible en las interfaces (botones, etiquetas, marcadores de posición, mensajes de estado) debe estar en **inglés**. Esto estandariza la base de la aplicación y simplifica la integración futura de sistemas de internacionalización.

## 2. Diseño de Interfaces (UI/UX)

* **Ausencia de Texto Explicativo Redundante:** Las interfaces no deben incluir bloques de texto con instrucciones de uso para el usuario (por ejemplo, guías de controles, tutoriales textuales o explicaciones de mecánicas evidentes, a menos que el diseño funcional del sistema lo requiera explícitamente). El diseño debe ser intuitivo y autosuficiente.

## 3. Gestión de Formularios y Validación de Requisitos

* **Implementación de Formularios:** Los formularios deben estructurarse siguiendo buenas prácticas de arquitectura, tipado y validación de datos.
* **Protocolo de Clarificación:** Ante cualquier especificación ambigua, incompleta o que contradiga detalles definidos previamente en el proyecto, **se debe interrumpir la generación de código y plantear preguntas específicas** para confirmar los requerimientos antes de proceder.