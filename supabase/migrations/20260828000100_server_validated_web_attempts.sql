begin;

create or replace function public.submit_validated_attempt(
    p_user_id uuid,
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
begin
    if p_user_id is null then
        raise exception using errcode = '42501', message = 'authentication_required';
    end if;

    perform set_config('request.jwt.claim.sub', p_user_id::text, true);
    return public.submit_attempt(
        p_client_attempt_id,
        p_airtime_ms,
        p_preflight_peak_g,
        p_impact_peak_g,
        p_airborne_sample_count
    );
end;
$$;

revoke execute on function public.submit_attempt(uuid, integer, double precision, double precision, integer)
    from public, anon, authenticated;
revoke execute on function public.submit_validated_attempt(uuid, uuid, integer, double precision, double precision, integer)
    from public, anon, authenticated;
grant execute on function public.submit_validated_attempt(uuid, uuid, integer, double precision, double precision, integer)
    to service_role;

create or replace function public.delete_account_session_is_fresh(
    p_user_id uuid,
    p_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from auth.sessions
        where id = p_session_id
          and user_id = p_user_id
          and created_at >= now() - interval '10 minutes'
    );
$$;

revoke execute on function public.delete_account_session_is_fresh(uuid, uuid)
    from public, anon, authenticated;
grant execute on function public.delete_account_session_is_fresh(uuid, uuid)
    to service_role;

commit;
