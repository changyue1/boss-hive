#!/bin/sh
#source ~/.bashrc #很重要,不然hive指令不执行

source ~/.bash_profile;
BASEDIR=`dirname $0`
cd $BASEDIR

#分隔符
yesterday=`date -d last-day +%Y%m%d`
#如果脚本传入指定日期参数,覆盖默认的设置
if [ "$#" -eq 1 ]; then
   yesterday=$1
fi

echo "正在导入${yesterday}的埋点PV和UV数据"
 
#埋点统计
hive -e "
set hive.groupby.skewindata=true;
set hive.jobname.length=10;
add jar /home/zhaochunlong/boss_stat/common_stat/hook_stat/boss-hive-1.0-SNAPSHOT.jar;
create temporary function filter_url as 'com.letv.boss.stat.hive.FilterCashierUrlUDF';
select ${yesterday}, 112, tt1.ref, tt1.pv, tt1.uv, coalesce(tt2.pay_pv,0), coalesce(tt2.pay_uv,0), coalesce(tt2.new_order_count, 0), coalesce(tt2.xufei_order_count, 0), coalesce(tt2.new_income, 0), coalesce(tt2.xufei_income, 0), tt2.pay_uv from (
select filter_url(cur_url) as ref, count(1) as pv, count(distinct session_id) as uv from dwb.dwb_megatron_pv_hour
where dt = '${yesterday}' and prod = 'vipCashier' and country = 'cn' and platform = '0' and (cur_url like '%zhifu.le.com/tobuy/pro%' or cur_url like '%zhifu.le.com/tobuy/regular%') and filter_url(cur_url) <> 'NULL'
group by filter_url(cur_url)
) tt1 left join (
select * from (
select t1.ref, count(1) as pay_pv, count(distinct t2.userid) as pay_uv, 
count(case when t2.neworxufei = '0' then 1 end) as new_order_count, count(case when t2.neworxufei = '1' then 1 end) as xufei_order_count, 
coalesce(sum(case when t2.neworxufei = '0' then t2.money end), 0) as new_income, coalesce(sum(case when t2.neworxufei = '1' then t2.money end), 0) as xufei_income from 
(select distinct uid, filter_url(cur_url) as ref from dwb.dwb_megatron_pv_hour
where dt = '${yesterday}' and prod = 'vipCashier' and country = 'cn' and platform = '0' and (cur_url like '%zhifu.le.com/tobuy/pro%' or cur_url like '%zhifu.le.com/tobuy/regular%') and filter_url(cur_url) <> 'NULL') t1
inner join
(select userid, neworxufei, money from dm_boss.t_new_order_4_data where dt='${yesterday}' and status='1' and terminal='112' and orderpaytype in ('0', '2') and viptype!='-1' and ordertype not in (0,1,1001)) t2
on t1.uid = t2.userid group by t1.ref
) tmp) tt2 on tt1.ref = tt2.ref order by tt2.pay_uv desc
" > ./data/query_hook_data.${yesterday}
