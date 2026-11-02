-- Gezi paylaşımı ve profil (Oguz, 2026-11-02: Supabase ücretsiz katman).
-- Kapsam: Apple ile giriş, basit profil, herkese açık gezi ve gezilerde
-- arama. Yorum, beğeni, mesajlaşma yok.
--
-- Bu dosya GitHub'daki "Supabase" işiyle bir kez çalıştırılır
-- (.github/workflows/supabase.yml); elle çalıştırmaya gerek yok.

-- Profil: ad ve simge (emoji). Herkes görebilir (paylaşılan gezide
-- "kimin gezisi" yazar), yalnızca sahibi değiştirir.
create table if not exists public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    name text not null default '' check (char_length(name) <= 40),
    emoji text not null default '🧭' check (char_length(emoji) <= 8),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "Profiller herkese açık" on public.profiles;
create policy "Profiller herkese açık" on public.profiles
    for select to anon, authenticated using (true);

drop policy if exists "Kendi profilini ekler" on public.profiles;
create policy "Kendi profilini ekler" on public.profiles
    for insert to authenticated with check ((select auth.uid()) = id);

drop policy if exists "Kendi profilini değiştirir" on public.profiles;
create policy "Kendi profilini değiştirir" on public.profiles
    for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);

-- Paylaşılan gezi: uygulamadaki gezinin herkese açık kopyası (şehirler,
-- günler, yerler; kişisel notlar, uçuş ve konaklama bilgisi yok).
-- Satır varsa gezi herkese açıktır; paylaşım kaldırılınca satır silinir.
create table if not exists public.shared_trips (
    id uuid primary key default gen_random_uuid(),
    owner uuid not null default auth.uid() references public.profiles (id) on delete cascade,
    -- Uygulamadaki gezinin kimliği: aynı gezi yeniden paylaşılınca güncellenir.
    local_id uuid not null,
    title text not null check (char_length(title) between 1 and 80),
    cities text[] not null default '{}',
    country_codes text[] not null default '{}',
    days integer not null default 0 check (days between 0 and 400),
    place_count integer not null default 0 check (place_count >= 0),
    -- Kapak fotoğrafı için ilk şehrin İngilizce Wikipedia başlığı.
    cover_title text check (char_length(cover_title) <= 200),
    -- Uygulamanın yazdığı arama metni (küçük harf, aksansız: başlık ve şehirler).
    search_text text not null default '' check (char_length(search_text) <= 2000),
    data jsonb not null check (octet_length(data::text) < 300000),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (owner, local_id)
);

create index if not exists shared_trips_created_at on public.shared_trips (created_at desc);
create index if not exists shared_trips_owner on public.shared_trips (owner);

alter table public.shared_trips enable row level security;

drop policy if exists "Paylaşılan geziler herkese açık" on public.shared_trips;
create policy "Paylaşılan geziler herkese açık" on public.shared_trips
    for select to anon, authenticated using (true);

drop policy if exists "Kendi gezisini paylaşır" on public.shared_trips;
create policy "Kendi gezisini paylaşır" on public.shared_trips
    for insert to authenticated with check ((select auth.uid()) = owner);

drop policy if exists "Kendi paylaşımını günceller" on public.shared_trips;
create policy "Kendi paylaşımını günceller" on public.shared_trips
    for update to authenticated using ((select auth.uid()) = owner) with check ((select auth.uid()) = owner);

drop policy if exists "Kendi paylaşımını kaldırır" on public.shared_trips;
create policy "Kendi paylaşımını kaldırır" on public.shared_trips
    for delete to authenticated using ((select auth.uid()) = owner);

-- Güncelleme zamanı kendiliğinden.
create or replace function public.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
    for each row execute function public.touch_updated_at();

drop trigger if exists shared_trips_touch on public.shared_trips;
create trigger shared_trips_touch before update on public.shared_trips
    for each row execute function public.touch_updated_at();

-- Uygulamanın kullanacağı yetkiler (satırları yukarıdaki kurallar süzer).
grant select on public.profiles, public.shared_trips to anon, authenticated;
grant insert, update on public.profiles to authenticated;
grant insert, update, delete on public.shared_trips to authenticated;

-- Hesabı silme (App Store kuralı: hesap açılan uygulamada hesap silinebilmeli).
-- Kullanıcı yalnızca kendini siler; profili ve paylaşımları da silinir.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null then
        raise exception 'Giriş yapılmamış';
    end if;
    delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
