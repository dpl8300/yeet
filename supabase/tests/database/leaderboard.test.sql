begin;

create extension if not exists pgtap with schema extensions;
select extensions.plan(29);

select extensions.has_table('public', 'profiles', 'profiles exists');
select extensions.has_table('public', 'attempts', 'attempts exists');
select extensions.has_table('public', 'personal_bests', 'personal_bests exists');

set local role anon;
select extensions.lives_ok(
    $$ select public.leaderboard_snapshot(null) $$,
    'anonymous users can read the public leaderboard snapshot'
);
select extensions.throws_ok(
    $$ select public.set_profile_handle('guest') $$,
    '42501',
    'authentication_required',
    'anonymous users cannot set a handle'
);
select extensions.throws_ok(
    $$ select public.submit_attempt(
        '10000000-0000-0000-0000-000000000001', 1000, 1, 1, 10
    ) $$,
    '42501',
    'authentication_required',
    'anonymous users cannot submit attempts'
);
select extensions.throws_ok(
    $$ insert into public.profiles (id, handle)
       values ('10000000-0000-0000-0000-000000000001', 'guest') $$,
    '42501',
    'permission denied for table profiles',
    'anonymous users cannot write tables directly'
);

reset role;
insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
    (
        '10000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'alpha@example.test', '', now(),
        '{"provider":"apple","providers":["apple"]}', '{}', now(), now()
    ),
    (
        '20000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'bravo@example.test', '', now(),
        '{"provider":"apple","providers":["apple"]}', '{}', now(), now()
    ),
    (
        '30000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'charlie@example.test', '', now(),
        '{"provider":"apple","providers":["apple"]}', '{}', now(), now()
    ),
    (
        '40000000-0000-0000-0000-000000000004',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'delta@example.test', '', now(),
        '{"provider":"apple","providers":["apple"]}', '{}', now(), now()
    ),
    (
        '50000000-0000-0000-0000-000000000005',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'echo@example.test', '', now(),
        '{"provider":"apple","providers":["apple"]}', '{}', now(), now()
    ),
    (
        '60000000-0000-0000-0000-000000000006',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'foxtrot@example.test', '', now(),
        '{"provider":"apple","providers":["apple"]}', '{}', now(), now()
    ),
    (
        '70000000-0000-0000-0000-000000000007',
        '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated', 'golf@example.test', '', now(),
        '{"provider":"apple","providers":["apple"]}', '{}', now(), now()
    );

set local role authenticated;
select set_config(
    'request.jwt.claim.sub',
    '10000000-0000-0000-0000-000000000001',
    true
);
select extensions.throws_ok(
    $$ insert into public.attempts (
        client_attempt_id, user_id, airtime_ms, preflight_peak_g,
        impact_peak_g, airborne_sample_count
    ) values (
        '10000000-0000-0000-0000-000000000099',
        '10000000-0000-0000-0000-000000000001', 1000, 1, 1, 10
    ) $$,
    '42501',
    'permission denied for table attempts',
    'authenticated users cannot write tables directly'
);
select extensions.is(
    (public.set_profile_handle('@Alpha')->>'handle'),
    'alpha',
    'authenticated handle creation normalizes case and leading at-sign'
);
select extensions.throws_ok(
    $$ select public.submit_attempt(
        '10000000-0000-0000-0000-000000000010', 119, 1, 1, 10
    ) $$,
    '22023',
    'invalid_attempt',
    'attempts below the detector bound are rejected'
);
select extensions.lives_ok(
    $$ select public.leaderboard_snapshot(3001) $$,
    'candidate ranks accept airtime above the former detector bound'
);
select extensions.is(
    (public.submit_attempt(
        '10000000-0000-0000-0000-000000000012', 1420, 1.8, 2.4, 142
    )->>'is_personal_best')::boolean,
    true,
    'first accepted attempt becomes the personal best'
);
select extensions.is(
    (public.submit_attempt(
        '10000000-0000-0000-0000-000000000012', 1420, 1.8, 2.4, 142
    )->>'already_processed')::boolean,
    true,
    'retrying an idempotency UUID returns the prior result'
);
select extensions.throws_ok(
    $$ select public.submit_attempt(
        '10000000-0000-0000-0000-000000000013', 1430, 1.8, 2.4, 143
    ) $$,
    'P0001',
    'submission_rate_limited',
    'a new attempt inside three seconds is rate limited'
);

reset role;
update public.attempts
set created_at = now() - interval '10 seconds'
where user_id = '10000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select extensions.is(
    (public.submit_attempt(
        '10000000-0000-0000-0000-000000000014', 1300, 1.7, 2.1, 130
    )->>'personal_best_ms')::integer,
    1420,
    'a lower attempt does not replace the personal best'
);

reset role;
update public.attempts
set created_at = now() - interval '10 seconds'
where user_id = '10000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select extensions.is(
    (public.submit_attempt(
        '10000000-0000-0000-0000-000000000015', 1600, 1.9, 2.6, 160
    )->>'personal_best_ms')::integer,
    1600,
    'a higher attempt replaces the personal best'
);

reset role;
insert into public.profiles (id, handle) values
    ('20000000-0000-0000-0000-000000000002', 'bravo'),
    ('30000000-0000-0000-0000-000000000003', 'charlie');
insert into public.attempts (
    client_attempt_id, user_id, airtime_ms, preflight_peak_g,
    impact_peak_g, airborne_sample_count, created_at
) values
    (
        '20000000-0000-0000-0000-000000000020',
        '20000000-0000-0000-0000-000000000002', 1600, 1.8, 2.2, 160,
        now() - interval '1 minute'
    ),
    (
        '30000000-0000-0000-0000-000000000030',
        '30000000-0000-0000-0000-000000000003', 1800, 1.8, 2.2, 180,
        now() - interval '3 minutes'
    );
update public.personal_bests
set achieved_at = now() - interval '2 minutes'
where user_id = '10000000-0000-0000-0000-000000000001';
insert into public.personal_bests (user_id, attempt_id, airtime_ms, achieved_at) values
    (
        '20000000-0000-0000-0000-000000000002',
        '20000000-0000-0000-0000-000000000020', 1600,
        now() - interval '1 minute'
    ),
    (
        '30000000-0000-0000-0000-000000000003',
        '30000000-0000-0000-0000-000000000030', 1800,
        now() - interval '3 minutes'
    );

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select extensions.is(
    (public.leaderboard_snapshot(null)->'current_user'->>'rank')::integer,
    2,
    'the earlier of two equal scores receives the earlier rank'
);
select set_config('request.jwt.claim.sub', '20000000-0000-0000-0000-000000000002', true);
select extensions.is(
    (public.leaderboard_snapshot(null)->'current_user'->>'rank')::integer,
    3,
    'a later equal score receives the next rank'
);
select extensions.is(
    (public.leaderboard_snapshot(1600)->>'candidate_rank')::integer,
    4,
    'a new candidate ranks after existing equal scores'
);
select extensions.is(
    (public.leaderboard_snapshot(null)->>'total_players')::integer,
    3,
    'the snapshot reports the ranked-player count'
);
select extensions.is(
    public.leaderboard_snapshot(null)->'leaders'->0->>'handle',
    'charlie',
    'the highest personal best appears first'
);
select extensions.is(
    public.leaderboard_snapshot(null)->'leaders'->1->>'handle',
    'alpha',
    'equal personal bests break ties by earliest achievement'
);

reset role;
insert into public.profiles (id, handle) values
    ('50000000-0000-0000-0000-000000000005', 'echo'),
    ('60000000-0000-0000-0000-000000000006', 'foxtrot'),
    ('70000000-0000-0000-0000-000000000007', 'golf');
insert into public.attempts (
    client_attempt_id, user_id, airtime_ms, preflight_peak_g,
    impact_peak_g, airborne_sample_count, created_at
) values
    (
        '50000000-0000-0000-0000-000000000050',
        '50000000-0000-0000-0000-000000000005', 1500, 1.8, 2.2, 150,
        now() - interval '4 minutes'
    ),
    (
        '60000000-0000-0000-0000-000000000060',
        '60000000-0000-0000-0000-000000000006', 1400, 1.8, 2.2, 140,
        now() - interval '5 minutes'
    ),
    (
        '70000000-0000-0000-0000-000000000070',
        '70000000-0000-0000-0000-000000000007', 1300, 1.8, 2.2, 130,
        now() - interval '6 minutes'
    );
insert into public.personal_bests (user_id, attempt_id, airtime_ms, achieved_at) values
    (
        '50000000-0000-0000-0000-000000000005',
        '50000000-0000-0000-0000-000000000050', 1500,
        now() - interval '4 minutes'
    ),
    (
        '60000000-0000-0000-0000-000000000006',
        '60000000-0000-0000-0000-000000000060', 1400,
        now() - interval '5 minutes'
    ),
    (
        '70000000-0000-0000-0000-000000000007',
        '70000000-0000-0000-0000-000000000070', 1300,
        now() - interval '6 minutes'
    );
select extensions.is(
    jsonb_array_length(public.leaderboard_snapshot(null)->'leaders'),
    6,
    'the snapshot returns six leaders'
);
select extensions.is(
    public.leaderboard_snapshot(null)->'leaders'->5->>'handle',
    'golf',
    'all six leaders remain in deterministic score order'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '40000000-0000-0000-0000-000000000004', true);
select extensions.is(
    (public.set_profile_handle('delta')->>'handle'),
    'delta',
    'an additional player can create a profile'
);
select extensions.lives_ok(
    $$ select public.submit_attempt(
        '40000000-0000-0000-0000-000000000040', 4500, 1.8, 2.2, 450
    ) $$,
    'saved attempts accept airtime above the former detector bound'
);

reset role;
delete from auth.users where id = '10000000-0000-0000-0000-000000000001';
select extensions.is(
    (select count(*)::integer from public.profiles
     where id = '10000000-0000-0000-0000-000000000001'),
    0,
    'deleting the auth user cascades to the profile'
);
select extensions.is(
    (select count(*)::integer from public.attempts
     where user_id = '10000000-0000-0000-0000-000000000001'),
    0,
    'deleting the auth user cascades to attempts'
);
select extensions.is(
    (select count(*)::integer from public.personal_bests
     where user_id = '10000000-0000-0000-0000-000000000001'),
    0,
    'deleting the auth user cascades to the personal best'
);

select * from extensions.finish();
rollback;
