import { createClient } from "@/utils/supabase/server";

export default async function Page() {
  const supabase = await createClient();

  const { data: profiles, error } = await supabase
    .from("profiles")
    .select("id, created_at")
    .order("created_at", { ascending: false })
    .limit(20);

  return (
    <main className="mx-auto flex min-h-screen max-w-xl flex-col gap-6 p-8 font-sans">
      <h1 className="text-2xl font-semibold">Perfiles (Supabase)</h1>
      <p className="text-sm text-zinc-600 dark:text-zinc-400">
        Sesión gestionada con middleware; RLS solo devuelve filas del usuario
        autenticado.
      </p>
      {error && (
        <p className="rounded border border-red-200 bg-red-50 p-3 text-sm text-red-800 dark:border-red-900 dark:bg-red-950 dark:text-red-200">
          {error.message}
        </p>
      )}
      {!error && (!profiles || profiles.length === 0) && (
        <p className="text-sm text-zinc-600 dark:text-zinc-400">
          No hay filas visibles (inicia sesión o aplica migraciones con{" "}
          <code className="rounded bg-zinc-100 px-1 dark:bg-zinc-800">
            supabase db push
          </code>
          ).
        </p>
      )}
      <ul className="list-inside list-disc space-y-2 text-sm">
        {profiles?.map((row) => (
          <li key={row.id}>
            <span className="font-mono text-xs">{row.id}</span>
            {row.created_at && (
              <span className="ml-2 text-zinc-500">
                {new Date(row.created_at).toLocaleString()}
              </span>
            )}
          </li>
        ))}
      </ul>
    </main>
  );
}
