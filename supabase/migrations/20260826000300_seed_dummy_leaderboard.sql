begin;

-- Development/demo leaderboard seed.
--
-- The generated auth users have no identity row and no usable password, so they
-- cannot sign in. Every row is deterministic and tagged with seed_batch, making
-- this migration safe to re-run and the data easy to identify later.

create temporary table yeet_leaderboard_seed_v1
on commit drop
as
with seed_words as (
    select
        array[
            'air', 'sky', 'cloud', 'lunar', 'solar', 'neon', 'turbo', 'swift',
            'wild', 'brave', 'chill', 'happy', 'lucky', 'epic', 'cosmic', 'fuzzy',
            'tiny', 'giant', 'rapid', 'quiet', 'rogue', 'vivid', 'golden', 'silver',
            'pixel', 'sonic', 'urban', 'alpine', 'ocean', 'ember', 'electric', 'zero'
        ]::text[] as adjectives,
        array[
            'ace', 'fox', 'wolf', 'bear', 'hawk', 'kite', 'comet', 'rocket',
            'jumper', 'toss', 'catch', 'phone', 'orbit', 'pulse', 'spark', 'bolt',
            'breeze', 'storm', 'wave', 'peak', 'trail', 'drift', 'flip', 'dash',
            'moon', 'star', 'void', 'hero', 'ninja', 'pilot', 'rider', 'yeti'
        ]::text[] as nouns
), generated as (
    select
        g as seed_number,
        words.adjectives[1 + ((g - 1) / 32)]
            || '_'
            || words.nouns[1 + mod(g - 1, 32)]
            || lpad(mod(g * 73, 100)::text, 2, '0') as handle,
        mod(g * 7919 + 137, 1000) as score_position,
        md5('yeet-leaderboard-seed-user-v1:' || g) as user_hash,
        md5('yeet-leaderboard-seed-attempt-v1:' || g) as attempt_hash
    from generate_series(1, 1000) as series(g)
    cross join seed_words as words
), scored as (
    select
        *,
        case
            -- A small, aspirational elite tier matching the product mock.
            when score_position < 6 then
                (array[3280, 3170, 3040, 2980, 2910, 2870])[score_position + 1]
            -- Top 5%: 2.22s–2.84s.
            when score_position < 50 then
                round(2840 - ((score_position - 6) * 14.5))::integer
            -- Strong throws: 1.71s–2.19s.
            when score_position < 200 then
                round(2190 - ((score_position - 50) * 3.2))::integer
            -- Main cluster: 1.10s–1.69s.
            when score_position < 550 then
                round(1690 - ((score_position - 200) * 1.7))::integer
            -- Newer players: 0.65s–1.09s.
            when score_position < 900 then
                round(1090 - ((score_position - 550) * 1.25))::integer
            -- Lower tail: 0.29s–0.64s.
            else
                round(640 - ((score_position - 900) * 3.5))::integer
        end as airtime_ms
    from generated
)
select
    seed_number,
    (
        substr(user_hash, 1, 8) || '-'
        || substr(user_hash, 9, 4) || '-'
        || substr(user_hash, 13, 4) || '-'
        || substr(user_hash, 17, 4) || '-'
        || substr(user_hash, 21, 12)
    )::uuid as user_id,
    (
        substr(attempt_hash, 1, 8) || '-'
        || substr(attempt_hash, 9, 4) || '-'
        || substr(attempt_hash, 13, 4) || '-'
        || substr(attempt_hash, 17, 4) || '-'
        || substr(attempt_hash, 21, 12)
    )::uuid as attempt_id,
    handle,
    'seed-user-'
        || lpad(seed_number::text, 4, '0')
        || '@dummy.yeet.invalid' as email,
    airtime_ms,
    now()
        - make_interval(days => mod(seed_number * 37, 180))
        - make_interval(secs => mod(seed_number * 53, 86400)) as achieved_at,
    now()
        - make_interval(days => mod(seed_number * 37, 180))
        - make_interval(secs => mod(seed_number * 53, 86400))
        - make_interval(days => 1 + mod(seed_number * 17, 120)) as joined_at
from scored;

insert into auth.users (
    id,
    instance_id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
)
select
    user_id,
    '00000000-0000-0000-0000-000000000000'::uuid,
    'authenticated',
    'authenticated',
    email,
    '',
    joined_at,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
        'is_dummy', true,
        'seed_batch', 'leaderboard_1000_v1'
    ),
    joined_at,
    joined_at
from yeet_leaderboard_seed_v1
on conflict (id) do nothing;

insert into public.profiles (id, handle, created_at, updated_at)
select user_id, handle, joined_at, joined_at
from yeet_leaderboard_seed_v1
on conflict (id) do update
set
    handle = excluded.handle,
    created_at = excluded.created_at,
    updated_at = excluded.updated_at;

insert into public.attempts (
    client_attempt_id,
    user_id,
    airtime_ms,
    preflight_peak_g,
    impact_peak_g,
    airborne_sample_count,
    created_at
)
select
    attempt_id,
    user_id,
    airtime_ms,
    1.20 + mod(seed_number * 17, 230)::double precision / 100,
    2.00 + mod(seed_number * 29, 480)::double precision / 100,
    greatest(12, round(airtime_ms / 10.0)::integer),
    achieved_at
from yeet_leaderboard_seed_v1
on conflict (client_attempt_id) do update
set
    user_id = excluded.user_id,
    airtime_ms = excluded.airtime_ms,
    preflight_peak_g = excluded.preflight_peak_g,
    impact_peak_g = excluded.impact_peak_g,
    airborne_sample_count = excluded.airborne_sample_count,
    created_at = excluded.created_at;

insert into public.personal_bests (
    user_id,
    attempt_id,
    airtime_ms,
    achieved_at
)
select user_id, attempt_id, airtime_ms, achieved_at
from yeet_leaderboard_seed_v1
on conflict (user_id) do update
set
    attempt_id = excluded.attempt_id,
    airtime_ms = excluded.airtime_ms,
    achieved_at = excluded.achieved_at;

do $$
declare
    seeded_personal_best_count integer;
begin
    select count(*)
    into seeded_personal_best_count
    from public.personal_bests as pb
    join auth.users as users on users.id = pb.user_id
    where users.raw_user_meta_data->>'seed_batch' = 'leaderboard_1000_v1';

    if seeded_personal_best_count <> 1000 then
        raise exception
            'Expected 1000 seeded personal bests, found %',
            seeded_personal_best_count;
    end if;
end;
$$;

commit;

-- To remove this seed batch later, run the following as an admin. Cascades
-- remove the matching profiles, attempts, and personal bests:
--
-- delete from auth.users
-- where raw_user_meta_data->>'seed_batch' = 'leaderboard_1000_v1';
