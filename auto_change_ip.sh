#!/bin/bash
server="your_account@ip"
db_user="root"
db_pwd="123456"

sql_query="SELECT user, host, authentication_string, plugin, account_locked, plugin FROM mysql.user;"
command="docker exec db mysql -u$db_user -p$db_pwd -e \"$sql_query\" -s -N"

# 连接服务器并获取数据
result=$(ssh -T $server $command)

# 获取当前用户列表
users=()
hosts=()
row_index=0
while read -r line; do
    col_index=0
    for item in $line; do
	if [ $col_index -gt 1 ]; then 
	    break  
	fi
	# echo "item: $item row_index: $row_index"
	if [ $col_index == 0 ]; then 
	    users[$row_index]=$item
	fi
	if [ $col_index == 1 ]; then
            hosts[$row_index]=$item
        fi
        ((col_index++))
    done
    ((row_index++))
done <<< "$result"

#echo "ussers: ${users[@]}"
#echo "hosts: ${hosts[@]}"

# 获取要删除的用户
del_user="root"
del_host=""
i=0
for host in ${hosts[@]}; do
    if [[ $host != "localhost" ]]; then
	del_user=${users[i]}
	del_host=$host
        break
    fi
    ((i++))
done

echo "需要删除的账号: user: $del_user host: $del_host"

json=$(curl -sS "https://id.hadron.ad.gt/v1/hadron.json?_it=0&partner_id=359&sync=1&domain=www.whatismyip.com&url=https://www.whatismyip.com/")
#echo $json
# 获取最新的ip地址，需要安装jq库，centos7 yum install epel-release yum install jq
new_ip=$(echo $json | jq -r '.addr')
#echo "new_ip: $new_ip"

new_host=$(echo "$new_ip" | awk -v FS="." '{print $1"."$2"."$3".%"}')
#new_host=$new_ip
echo "新地址 $new_host"

if [ "$del_host" == "$new_host" ]; then
    echo "地址一样，不需要更新, 任务结束"
    exit
fi

echo "进行用户更新..."

sql=""
if [ "$del_host" != "" ]; then
    sql+="drop user '$del_user'@'$del_host';"
fi
sql+="grant all privileges on *.* to '$del_user'@'$new_host' identified by 'root' with grant option; flush privileges;"
escaped_sql=$(printf '%q' "$sql")
command="docker exec db mysql -u$db_user -p$db_pwd -e $escaped_sql -s -N"

# 连接服务器并执行更新语句
result=$(ssh -T $server $command)

echo "更新成功"