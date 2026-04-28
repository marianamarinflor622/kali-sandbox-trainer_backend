-- Usuarios ya creados con "Waiting for verification" en el panel de Auth:
-- marcar correo como confirmado para que puedan iniciar sesión sin enlace.
-- Idempotente.

update auth.users
set
  email_confirmed_at = coalesce(email_confirmed_at, timezone('utc', now())),
  updated_at = timezone('utc', now())
where email_confirmed_at is null;
