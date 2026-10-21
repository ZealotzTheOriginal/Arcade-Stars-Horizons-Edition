-- Arcade Stars Horizons Edition: esquema inicial.
-- Ejecutar una vez en Supabase Dashboard -> SQL Editor. Es idempotente.
-- El servidor (Render) escribe con la secret key (rol service_role, ignora RLS).
-- Los clientes solo pueden LEER: nunca escriben directamente en estas tablas.

-- ── Perfiles ─────────────────────────────────────────────
create table if not exists public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  nickname    text not null check (nickname ~ '^[A-Za-z0-9_\- ]{3,16}$'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ── Partidas ─────────────────────────────────────────────
create table if not exists public.matches (
  id         bigint generated always as identity primary key,
  game_id    text not null,
  played_at  timestamptz not null default now()
);

create table if not exists public.match_players (
  match_id   bigint not null references public.matches (id) on delete cascade,
  user_id    uuid   not null references public.profiles (id) on delete cascade,
  score      integer not null default 0,
  is_winner  boolean not null default false,
  primary key (match_id, user_id)
);

create index if not exists match_players_user_idx on public.match_players (user_id);
create index if not exists matches_game_played_idx on public.matches (game_id, played_at desc);

-- ── RLS: lectura pública, escritura solo desde el servidor ──
alter table public.profiles      enable row level security;
alter table public.matches       enable row level security;
alter table public.match_players enable row level security;

drop policy if exists "profiles are readable" on public.profiles;
create policy "profiles are readable" on public.profiles for select using (true);

drop policy if exists "matches are readable" on public.matches;
create policy "matches are readable" on public.matches for select using (true);

drop policy if exists "match players are readable" on public.match_players;
create policy "match players are readable" on public.match_players for select using (true);

-- ── Registro atómico de una partida (solo service_role) ──
create or replace function public.record_match(p_game_id text, p_players jsonb)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_match_id bigint;
begin
  insert into public.matches (game_id) values (p_game_id) returning id into v_match_id;

  insert into public.match_players (match_id, user_id, score, is_winner)
  select v_match_id,
         (p ->> 'user_id')::uuid,
         coalesce((p ->> 'score')::integer, 0),
         coalesce((p ->> 'is_winner')::boolean, false)
  from jsonb_array_elements(p_players) as p
  on conflict (match_id, user_id) do nothing;

  return v_match_id;
end;
$$;

revoke all on function public.record_match(text, jsonb) from public, anon, authenticated;
grant execute on function public.record_match(text, jsonb) to service_role;

-- ── Ranking por juego ────────────────────────────────────
create or replace view public.leaderboard
with (security_invoker = true) as
select m.game_id,
       mp.user_id,
       p.nickname,
       count(*)                          as matches_played,
       count(*) filter (where mp.is_winner) as wins,
       sum(mp.score)                     as total_score
from public.match_players mp
join public.matches  m on m.id = mp.match_id
join public.profiles p on p.id = mp.user_id
group by m.game_id, mp.user_id, p.nickname;
