begin;

alter table public.attempts
    drop constraint if exists attempts_airtime_ms_check;
alter table public.attempts
    add constraint attempts_airtime_ms_check check (airtime_ms >= 120);

alter table public.personal_bests
    drop constraint if exists personal_bests_airtime_ms_check;
alter table public.personal_bests
    add constraint personal_bests_airtime_ms_check check (airtime_ms >= 120);

create or replace function public.leaderboard_snapshot(
    p_candidate_airtime_ms integer default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_leaders jsonb;
    v_current_user jsonb;
    v_candidate_rank bigint;
    v_total_players bigint;
begin
    if p_candidate_airtime_ms is not null
       and p_candidate_airtime_ms < 120 then
        raise exception using errcode = '22023', message = 'invalid_candidate_airtime';
    end if;

    with ranked as (
        select
            p.id as user_id,
            p.handle,
            pb.airtime_ms,
            pb.achieved_at,
            row_number() over (
                order by pb.airtime_ms desc, pb.achieved_at asc, p.handle asc
            ) as leaderboard_rank
        from public.personal_bests pb
        join public.profiles p on p.id = pb.user_id
    ), leaders as (
        select *
        from ranked
        order by airtime_ms desc, achieved_at asc, handle asc
        limit 6
    )
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'user_id', user_id,
                'handle', handle,
                'rank', leaderboard_rank,
                'airtime_ms', airtime_ms,
                'achieved_at', achieved_at
            )
            order by airtime_ms desc, achieved_at asc, handle asc
        ),
        '[]'::jsonb
    )
    into v_leaders
    from leaders;

    if v_user_id is not null then
        select jsonb_build_object(
            'user_id', p.id,
            'handle', p.handle,
            'rank', case
                when pb.airtime_ms is null then null
                else private.rank_for(pb.airtime_ms, pb.achieved_at, p.handle)
            end,
            'airtime_ms', pb.airtime_ms,
            'achieved_at', pb.achieved_at
        )
        into v_current_user
        from public.profiles p
        left join public.personal_bests pb on pb.user_id = p.id
        where p.id = v_user_id;
    end if;

    if p_candidate_airtime_ms is not null then
        v_candidate_rank := private.rank_for(p_candidate_airtime_ms, null, null);
    end if;

    select count(*) into v_total_players from public.personal_bests;

    return jsonb_build_object(
        'leaders', v_leaders,
        'current_user', v_current_user,
        'candidate_rank', v_candidate_rank,
        'total_players', v_total_players
    );
end;
$$;

create or replace function public.submit_attempt(
    p_client_attempt_id uuid,
    p_airtime_ms integer,
    p_preflight_peak_g double precision,
    p_impact_peak_g double precision,
    p_airborne_sample_count integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_existing public.attempts;
    v_attempt public.attempts;
    v_previous_best_ms integer;
    v_best public.personal_bests;
    v_is_personal_best boolean;
begin
    if v_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    if not exists (select 1 from public.profiles where id = v_user_id) then
        raise exception using errcode = '23503', message = 'profile_required';
    end if;

    select * into v_existing
    from public.attempts
    where client_attempt_id = p_client_attempt_id
      and user_id = v_user_id;

    if found then
        select * into v_best
        from public.personal_bests
        where user_id = v_user_id;

        return jsonb_build_object(
            'attempt_id', v_existing.client_attempt_id,
            'personal_best_ms', v_best.airtime_ms,
            'rank', private.rank_for(
                v_best.airtime_ms,
                v_best.achieved_at,
                (select handle from public.profiles where id = v_user_id)
            ),
            'is_personal_best', v_best.attempt_id = v_existing.client_attempt_id,
            'already_processed', true
        );
    end if;

    if p_client_attempt_id is null
       or p_airtime_ms is null
       or p_airtime_ms < 120
       or p_preflight_peak_g is null
       or p_preflight_peak_g < 0
       or p_preflight_peak_g > 100
       or p_preflight_peak_g = 'NaN'::double precision
       or p_impact_peak_g is null
       or p_impact_peak_g < 0
       or p_impact_peak_g > 100
       or p_impact_peak_g = 'NaN'::double precision
       or p_airborne_sample_count is null
       or p_airborne_sample_count <= 0 then
        raise exception using errcode = '22023', message = 'invalid_attempt';
    end if;

    if exists (
        select 1
        from public.attempts
        where user_id = v_user_id
          and created_at > now() - interval '3 seconds'
    ) then
        raise exception using errcode = 'P0001', message = 'submission_rate_limited';
    end if;

    select airtime_ms into v_previous_best_ms
    from public.personal_bests
    where user_id = v_user_id;

    insert into public.attempts (
        client_attempt_id,
        user_id,
        airtime_ms,
        preflight_peak_g,
        impact_peak_g,
        airborne_sample_count
    ) values (
        p_client_attempt_id,
        v_user_id,
        p_airtime_ms,
        p_preflight_peak_g,
        p_impact_peak_g,
        p_airborne_sample_count
    ) returning * into v_attempt;

    v_is_personal_best := v_previous_best_ms is null or p_airtime_ms > v_previous_best_ms;

    insert into public.personal_bests (
        user_id,
        attempt_id,
        airtime_ms,
        achieved_at
    ) values (
        v_user_id,
        v_attempt.client_attempt_id,
        v_attempt.airtime_ms,
        v_attempt.created_at
    )
    on conflict (user_id) do update
        set attempt_id = excluded.attempt_id,
            airtime_ms = excluded.airtime_ms,
            achieved_at = excluded.achieved_at
        where excluded.airtime_ms > public.personal_bests.airtime_ms;

    select * into v_best
    from public.personal_bests
    where user_id = v_user_id;

    return jsonb_build_object(
        'attempt_id', v_attempt.client_attempt_id,
        'personal_best_ms', v_best.airtime_ms,
        'rank', private.rank_for(
            v_best.airtime_ms,
            v_best.achieved_at,
            (select handle from public.profiles where id = v_user_id)
        ),
        'is_personal_best', v_is_personal_best,
        'already_processed', false
    );
end;
$$;

commit;
