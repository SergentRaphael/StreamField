-- À coller une seule fois dans Supabase → SQL Editor → New query → Run.
-- Crée la table où chaque compte StreamField garde ses playlists et favoris.

create table if not exists public.user_data (
  user_id    uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_data enable row level security;

-- Chacun ne peut lire et modifier QUE ses propres données.
drop policy if exists "lire ses donnees" on public.user_data;
drop policy if exists "ajouter ses donnees" on public.user_data;
drop policy if exists "modifier ses donnees" on public.user_data;

create policy "lire ses donnees" on public.user_data
  for select to authenticated using (auth.uid() = user_id);
create policy "ajouter ses donnees" on public.user_data
  for insert to authenticated with check (auth.uid() = user_id);
create policy "modifier ses donnees" on public.user_data
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update on public.user_data to authenticated;
