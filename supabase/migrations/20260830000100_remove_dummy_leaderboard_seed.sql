begin;

do $$
declare
    tagged_seed_count integer;
    unexpected_tagged_count integer;
    deleted_seed_count integer;
begin
    select count(*)
    into tagged_seed_count
    from auth.users
    where raw_user_meta_data->>'seed_batch' = 'leaderboard_1000_v1';

    select count(*)
    into unexpected_tagged_count
    from auth.users
    where raw_user_meta_data->>'seed_batch' = 'leaderboard_1000_v1'
      and email not like 'seed-user-%@dummy.yeet.invalid';

    if unexpected_tagged_count <> 0 then
        raise exception
            'Refusing to remove seed batch: % tagged users have unexpected email addresses',
            unexpected_tagged_count;
    end if;

    delete from auth.users
    where raw_user_meta_data->>'seed_batch' = 'leaderboard_1000_v1'
      and email like 'seed-user-%@dummy.yeet.invalid';

    get diagnostics deleted_seed_count = row_count;

    if deleted_seed_count <> tagged_seed_count then
        raise exception
            'Expected to remove % tagged seed users, removed %',
            tagged_seed_count,
            deleted_seed_count;
    end if;
end;
$$;

commit;
