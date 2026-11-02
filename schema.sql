-- =====================================================================
-- SISTEM MUDA-MUDI KELOMPOK PAYANGAN 2 : skema database Supabase
-- Jalankan di Supabase > SQL Editor (sekali saja), lalu jalankan seed.sql
-- =====================================================================

-- 1. Profil pengguna dan peran (admin / pengurus / viewer)
create table if not exists public.profiles (
  id     uuid primary key references auth.users(id) on delete cascade,
  nama   text,
  role   text not null default 'viewer' check (role in ('admin','pengurus','viewer')),
  dibuat timestamptz not null default now()
);

-- Fungsi bantu: peran milik pengguna yang sedang login
create or replace function public.peran() returns text
language sql stable security definer set search_path = public as
$$ select role from public.profiles where id = auth.uid() $$;

-- Setiap pengguna baru otomatis dibuatkan profil dengan peran 'viewer'
create or replace function public.buat_profil() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  insert into public.profiles (id, nama)
  values (new.id, coalesce(new.raw_user_meta_data->>'nama', new.email));
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.buat_profil();

-- 2. Tabel data
create table if not exists public.people (          -- Data Muda-Mudi
  id      text primary key,
  nama    text not null,
  ayah    text not null default '',
  ibu     text not null default '',
  telp    text not null default '',
  alamat  text not null default '',
  rt      text not null default '',
  rw      text not null default '',
  jk      text not null check (jk in ('L','P')),
  lahir   date,
  status  text not null default 'Belum Menikah',
  dibuat  timestamptz not null default now()
);

create table if not exists public.members (         -- Anggota absensi
  id       text primary key,
  nama     text not null,
  kelompok text not null check (kelompok in ('PR','RM','UN')),
  jk       text not null check (jk in ('L','P')),
  telp     text not null default '',
  ref_id   text references public.people(id) on delete set null
);

create table if not exists public.attendance (      -- Absensi per tanggal
  tgl       date not null,
  member_id text not null references public.members(id) on delete cascade,
  kode      text not null check (kode in ('H','I','S','A')),
  primary key (tgl, member_id)
);
create index if not exists attendance_member_idx on public.attendance (member_id);

create table if not exists public.meetings (        -- Libur dan catatan pertemuan
  tgl     date primary key,
  libur   boolean not null default false,
  catatan text not null default ''
);

-- 3. Keamanan (Row Level Security)
alter table public.profiles enable row level security;
drop policy if exists profil_baca on public.profiles;
drop policy if exists profil_ubah on public.profiles;
create policy profil_baca on public.profiles for select to authenticated
  using (id = auth.uid() or public.peran() = 'admin');
create policy profil_ubah on public.profiles for update to authenticated
  using (public.peran() = 'admin') with check (public.peran() = 'admin');

do $$
declare t text;
begin
  foreach t in array array['people','members','attendance','meetings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists baca  on public.%I', t);
    execute format('drop policy if exists tulis on public.%I', t);
    execute format('drop policy if exists ubah  on public.%I', t);
    execute format('drop policy if exists hapus on public.%I', t);
    -- semua yang punya peran boleh melihat
    execute format('create policy baca on public.%I for select to authenticated using (public.peran() is not null)', t);
    -- admin dan pengurus boleh menambah dan mengubah
    execute format('create policy tulis on public.%I for insert to authenticated with check (public.peran() in (''admin'',''pengurus''))', t);
    execute format('create policy ubah on public.%I for update to authenticated using (public.peran() in (''admin'',''pengurus'')) with check (public.peran() in (''admin'',''pengurus''))', t);
    -- hapus: people dan members hanya admin; absensi dan libur boleh pengurus
    execute format('create policy hapus on public.%I for delete to authenticated using (public.peran() %s)', t,
      case when t in ('people','members') then '= ''admin''' else 'in (''admin'',''pengurus'')' end);
  end loop;
end $$;
