-- Español con señora Eman: esquema Supabase
-- Ejecuta TODO este archivo en Supabase > SQL Editor > New query.
-- La cuenta de la profesora debe crearse en Authentication > Users.
-- Tras crearla, añade su UUID a teacher_users (ver README).

create extension if not exists pgcrypto;

create table if not exists public.teacher_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  full_name text not null check (length(trim(full_name)) between 2 and 90),
  school text not null check (length(trim(school)) between 2 and 120),
  class_name text not null check (length(trim(class_name)) between 1 and 40),
  identity_key text not null unique,
  created_at timestamptz not null default now(),
  last_activity timestamptz not null default now(),
  official_score smallint check (official_score between 0 and 10),
  official_at timestamptz
);

create table if not exists public.quiz_attempts (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.students(id) on delete cascade,
  score smallint not null check (score between 0 and 10),
  answers jsonb not null default '[]'::jsonb,
  is_official boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index if not exists one_official_attempt_per_student
  on public.quiz_attempts(student_id) where is_official = true;
create index if not exists quiz_attempts_student_created on public.quiz_attempts(student_id, created_at desc);

alter table public.teacher_users enable row level security;
alter table public.students enable row level security;
alter table public.quiz_attempts enable row level security;

-- Sin acceso directo público a tablas. Solo las funciones controladas pueden escribir/leer.
revoke all on public.teacher_users from anon, authenticated;
revoke all on public.students from anon, authenticated;
revoke all on public.quiz_attempts from anon, authenticated;
grant select on public.students, public.quiz_attempts to authenticated;

create or replace function public.is_teacher()
returns boolean language sql stable security definer
set search_path = public, auth
as $$
  select exists(select 1 from public.teacher_users t where t.user_id = auth.uid());
$$;
revoke all on function public.is_teacher() from public;
grant execute on function public.is_teacher() to authenticated;

create or replace function public.register_student(p_name text, p_school text, p_class text)
returns jsonb language plpgsql security definer
set search_path = public, auth
as $$
declare
  v_id uuid;
  v_name text := trim(coalesce(p_name,''));
  v_school text := trim(coalesce(p_school,''));
  v_class text := trim(coalesce(p_class,''));
  v_key text;
  v_score smallint;
  v_official_at timestamptz;
  v_new boolean := false;
begin
  if length(v_name) < 2 or length(v_name) > 90 or length(v_school) < 2 or length(v_school) > 120 or length(v_class) < 1 or length(v_class) > 40 then
    raise exception 'Nombre, escuela o clase no válidos.';
  end if;
  -- Normaliza mayúsculas/espacios para evitar duplicados simples.
  v_key := lower(regexp_replace(v_name, '\s+', ' ', 'g')) || '|' ||
           lower(regexp_replace(v_school, '\s+', ' ', 'g')) || '|' ||
           lower(regexp_replace(v_class, '\s+', ' ', 'g'));
  insert into public.students(full_name, school, class_name, identity_key)
  values(v_name, v_school, v_class, v_key)
  on conflict(identity_key) do nothing
  returning id into v_id;
  if v_id is not null then v_new := true;
  else
    select id, official_score, official_at into v_id, v_score, v_official_at
    from public.students where identity_key = v_key;
  end if;
  update public.students set last_activity = now() where id = v_id;
  select official_score, official_at into v_score, v_official_at from public.students where id = v_id;
  return jsonb_build_object('student_id', v_id, 'is_new', v_new, 'official_score', v_score, 'official_at', v_official_at);
end;
$$;
revoke all on function public.register_student(text,text,text) from public;
grant execute on function public.register_student(text,text,text) to anon, authenticated;

create or replace function public.submit_quiz_result(p_student_id uuid, p_score integer, p_answers jsonb)
returns jsonb language plpgsql security definer
set search_path = public, auth
as $$
declare
  v_official boolean := false;
  v_existing smallint;
  v_answers jsonb;
begin
  if p_score < 0 or p_score > 10 then raise exception 'Puntuación no válida.'; end if;
  if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> 10 then
    raise exception 'Se necesitan exactamente 10 respuestas.';
  end if;
  update public.students set last_activity = now() where id = p_student_id;
  if not found then raise exception 'Estudiante no registrado.'; end if;

  -- La primera entrega de cualquier nota es la oficial; las siguientes son prácticas.
  insert into public.quiz_attempts(student_id, score, answers, is_official)
  values(p_student_id, p_score, p_answers, true)
  on conflict (student_id) where is_official = true do nothing
  returning true into v_official;

  if coalesce(v_official, false) then
    update public.students set official_score = p_score, official_at = now(), last_activity = now()
    where id = p_student_id;
  else
    insert into public.quiz_attempts(student_id, score, answers, is_official)
    values(p_student_id, p_score, p_answers, false);
    select official_score into v_existing from public.students where id = p_student_id;
  end if;
  return jsonb_build_object('official_recorded', coalesce(v_official,false), 'official_score', coalesce((select official_score from public.students where id=p_student_id), v_existing));
end;
$$;
revoke all on function public.submit_quiz_result(uuid,integer,jsonb) from public;
grant execute on function public.submit_quiz_result(uuid,integer,jsonb) to anon, authenticated;

create or replace function public.get_public_participation_count()
returns bigint language sql stable security definer
set search_path = public
as $$ select count(*) from public.quiz_attempts where is_official = true; $$;
revoke all on function public.get_public_participation_count() from public;
grant execute on function public.get_public_participation_count() to anon, authenticated;

create or replace function public.teacher_student_roster()
returns table(
  id uuid, full_name text, school text, class_name text,
  created_at timestamptz, official_at timestamptz, official_score smallint, last_activity timestamptz
) language plpgsql stable security definer
set search_path = public, auth
as $$
begin
  if not public.is_teacher() then raise exception 'Acceso reservado a la profesora.'; end if;
  return query select s.id,s.full_name,s.school,s.class_name,s.created_at,s.official_at,s.official_score,s.last_activity
  from public.students s order by s.created_at desc;
end;
$$;
revoke all on function public.teacher_student_roster() from public;
grant execute on function public.teacher_student_roster() to authenticated;

-- No se crean políticas de lectura pública. El panel usa la función teacher_student_roster.
