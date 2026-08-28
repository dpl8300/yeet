begin;

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
        limit 10
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

commit;
