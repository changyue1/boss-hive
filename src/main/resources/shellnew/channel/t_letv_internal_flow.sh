#!/usr/bin/env bash
#站内渠道流量统计
source ~/.bash_profile;
source ../util/date_util.sh
source ../util/mysql_util.sh
source ../util/disk_util.sh

BASEDIR=`dirname $0`
cd ${BASEDIR}

yesterday=`date -d "1 days ago" +"%Y%m%d"`

if [ "$#" -eq 1 ]; then
    yesterday=$1
fi

db_ip=10.183.196.100
db_port=3306
db_user=boss_stat_w
db_pass=6b9b3#2137F
db_name=boss_stat

file=`pwd`/data/t_letv_internal_flow_${yesterday}.txt

log=`pwd`/logs/t_letv_internal_flow_${yesterday}.log

#引入UDF
udf="add jar /home/zhaochunlong/shell/udf/boss-hive-1.0.jar;
create temporary function splitUrl as 'com.letv.boss.stat.hive.UrlQuerySplitUDF';"
#新增还是续费判定条件
nox="case when b.neworxufei in (0, 1) then b.neworxufei else -1 end"


#查询http上报的ref流量
function httpRef {
    terminal=$1
    if [ ${terminal} -eq 112 ]; then
        product=" dt = '${yesterday}' and product = 1 and cur_url != '-' and cur_url != ''"
        terminalName="PC端"
    fi
    if [ ${terminal} -eq 113 ]; then
        product=" and product = 0 and p2 in ('04', '05', '06') and cur_url != '-' and cur_url != ''"
        terminalName="M站"
    fi

    echo "开始查询${terminalName}数据"

    sql1="select uid, splitUrl(cur_url) as query, letv_cookie from data_raw.tbl_pv_hour where ${product}"

    sql2="select m.uid, m.query['ref'] as ref, m.letv_cookie from (${sql1}) m
     where m.query['ref'] is not null and m.query['ref'] not like '%http:%' and m.query['ref'] != 'click'"

    sql3="select userid, money, neworxufei from dm_boss.t_new_order_4_data
     where dt = '${yesterday}' and terminal = ${terminal} and status = 1 and orderpaytype != -1"

    result="'${yesterday}', a.ref, ${nox} AS neworxufei, '${terminal}',
     count(distinct a.letv_cookie) as pageUv,
     count(distinct b.userid) as payUv,
     sum(coalesce(b.money, 0)) as income"

    sql="${udf} select ${result} from (${sql2}) a left outer join (${sql3}) b on (a.uid = b.userid) group by a.ref, ${nox}"

    print "${sql}"

    hive -e "${sql}" >> ${file}
}

#查询JsSdk上报的ref流量
function jssdkRef {
    terminal=$1

}

#入口方法
function main {
    echo "开始计算${yesterday}日的站内渠道流量收入" > ${log}

    echo "开始查询Http上报的PC端Ref流量" >> ${log}
    httpRef 112 >> ${log}
    echo "查询Http上报的PC端Ref流量完成" >> ${log}

    echo "开始查询Http上报的M站Ref流量完成" >> ${log}
    httpRef 113 >> ${log}
    echo "查询Http上报的PC端Ref流量完成" >> ${log}

    echo "开始导入数据到mysql中" >> ${log}
    delete ${db_ip} ${db_port} ${db_user} ${db_pass} ${db_name} "t_letv_channel_flow" "dt = '${yesterday}'" >> ${log}
    columns="dt, channel, is_new, terminal, page_uv, pay_uv, income"
    insert ${db_ip} ${db_port} ${db_user} ${db_pass} ${db_name} "t_letv_channel_flow" ${file} "${columns}" >> ${log}
    echo "导入到mysql中完成" >> ${log}
}

#执行main方法
main
