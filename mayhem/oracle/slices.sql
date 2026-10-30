select name, ts, dur, depth from slice order by ts;
select t.name as thread_name, p.name as process_name, p.pid from thread t join process p using(upid) where t.tid = 11;
select t.name, c.ts, c.value from counter c join process_counter_track t on c.track_id = t.id order by c.ts;
select count(*) as n_slices, sum(dur) as total_dur from slice;
