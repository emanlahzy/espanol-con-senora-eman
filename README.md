# Español con señora Eman — paquete de despliegue

## Incluye
- `index.html`: sitio LTR en español con apoyo árabe, 6 temas, registro, prueba de 10 preguntas, certificado SVG y panel de profesora.
- `supabase_setup.sql`: tablas, funciones de registro, participación oficial única, prácticas y lista privada de estudiantes.
- `README.md`: instrucciones de configuración y pruebas.

## Qué hace la política del cuestionario
La primera entrega del cuestionario queda como participación oficial, independientemente de la nota. El estudiante puede repetir el cuestionario para practicar; cada intento posterior se almacena como práctica y no aumenta el contador oficial. La base de datos aplica un índice único parcial para una sola participación oficial por estudiante.

**Límite de identidad:** el registro usa nombre + escuela + clase normalizados. Esto evita duplicados accidentales, pero no verifica identidad real: otro estudiante podría escribir los mismos datos o un estudiante podría cambiar la ortografía. Para control fuerte, asigna códigos individuales o exige inicio de sesión por alumno. No guardes datos sensibles.

## Configuración de Supabase
1. Crea un proyecto en https://supabase.com/.
2. Abre SQL Editor y ejecuta todo `supabase_setup.sql`.
3. Ve a Project Settings → API (o Connect) y copia Project URL y la clave pública `anon`/publishable. **Nunca coloques la `service_role` key en el navegador.**
4. En `index.html`, reemplaza:
   - `PEGA_AQUI_LA_URL_DE_SUPABASE` por Project URL.
   - `PEGA_AQUI_LA_CLAVE_PUBLICA_ANON` por la clave pública anon/publishable.
5. Crea la cuenta de la profesora en Authentication → Users (Add user).
6. Copia el UUID de esa cuenta y ejecuta en SQL Editor:
   ```sql
   insert into public.teacher_users(user_id)
   values ('UUID-DE-LA-CUENTA-DE-LA-PROFESORA');
   ```
   No compartas la contraseña. Activa confirmación de correo o política de acceso apropiada para tu escuela.
7. Despliega `index.html` en HTTPS usando Netlify, Cloudflare Pages, GitHub Pages u otra estática. Para la configuración más sencilla, sube el archivo como `index.html` a Netlify Drop. Para una actualización futura, conserva los archivos en un repositorio privado.
8. En Supabase Authentication → URL Configuration, configura el Site URL y las Redirect URLs para el dominio publicado. El inicio de sesión por contraseña no necesita redirección para este flujo, pero configura la URL del sitio correctamente.

## Privacidad y seguridad
- La clave `anon` es pública por diseño; las funciones SQL y los permisos son la barrera de seguridad. No pongas claves privadas en `index.html`.
- La función pública de registro permite que cualquiera registre un nombre escrito. El contador cuenta primeras participaciones oficiales, no simples visitas anónimas.
- El sistema evita doble participación oficial en la base de datos para la identidad normalizada. No es una verificación fuerte de identidad sin códigos/cuentas de alumnos.
- La lista de alumnos solo se devuelve por `teacher_student_roster()` a una cuenta cuyo UUID esté en `teacher_users`.
- Revisa la política de privacidad aplicable a menores y las reglas de la escuela antes de recopilar datos. Añade CAPTCHA/rate limiting si el enlace se publica ampliamente.
- Para mejorar el modelo de amenazas, un desarrollo profesional debería mover la lógica de calificación al servidor: en este paquete el navegador envía la puntuación y respuestas, así que un usuario técnico podría manipular el resultado. Para certificados de alta confianza, valida las respuestas en una Edge Function o función SQL y genera el certificado tras validar las respuestas en servidor.

## Pruebas recomendadas tras configurar
1. Abre el sitio en un navegador móvil y uno de escritorio.
2. Registra un estudiante nuevo; comprueba que aparezca en el panel tras iniciar sesión como profesora.
3. Registra de nuevo la misma combinación nombre/escuela/clase; debe recuperar el mismo registro.
4. Completa una prueba: el contador oficial debe aumentar solo una vez.
5. Repite el cuestionario: el resultado debe aparecer como práctica y el contador no debe aumentar.
6. Inicia sesión como una cuenta que NO esté en `teacher_users`: el panel debe rechazar la consulta de lista.
7. Descarga y comparte el certificado con 10/10.
8. Comprueba en el dashboard de Supabase que los datos están guardados.

## Estado de las pruebas en este paquete
- Se incluye lógica de interfaz y SQL para las funciones descritas.
- No es posible probar la conexión real, la autenticación ni la persistencia sin credenciales de un proyecto Supabase configurado.
- No se ha publicado un enlace público desde este entorno; el paquete queda preparado para configuración y despliegue.
