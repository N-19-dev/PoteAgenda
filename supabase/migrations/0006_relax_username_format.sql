alter table public.profiles
  drop constraint if exists username_format;

alter table public.profiles
  add constraint username_not_blank check (char_length(trim(username)) > 0);
