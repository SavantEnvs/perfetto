select t.tid, t.name, s.ts, s.dur, s.priority from sched s join thread t using(utid) where t.tid != 0 order by s.ts;
select count(*) as n_sched, sum(dur) as busy_ns from sched s join thread t using(utid) where t.tid != 0;
