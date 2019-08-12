#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# Check if user is root
if [ $(id -u) != "0" ]; then
    echo "Error: You must be root to run this script！"
    exit 1
fi

. include/main.sh

CurPWD=$(cd "$(dirname "$0")"; pwd)
DOCKER_IP=`echo '172.17.0.0/16'`

config_firewall() {
	echo -e "\033[31m 1. 防火墙 Selinux PackageKit 设置 \033[0m"
	if [ "$(systemctl status firewalld | grep running)" != "" ]
	then
	firewall-cmd --zone=public --add-port=80/tcp --permanent
	firewall-cmd --zone=public --add-port=2222/tcp --permanent
	firewall-cmd --permanent --add-rich-rule="rule family="ipv4" source address="$DOCKER_IP" port protocol="tcp" port="8080" accept"
	firewall-cmd --reload
	fi

	if [ "$(getenforce)" != "Disabled" ]
	then
	sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
	setenforce 0
	#setsebool -P httpd_can_network_connect 1
	fi
}

kill_PM() {
	#sed -i 's/enabled=1/enabled=0/g' /etc/yum/pluginconf.d/langpacks.conf
	#PACKAGEKIT=$(ps aux | grep PackageKit | awk '{print $2}' | sed -n '1p')
	#if [ $PACKAGEKIT != "" ]
	#then
	#kill -9 $PACKAGEKIT
	#fi
	
	if ps aux | grep "yum" | grep -qv "grep"; then
            if [ -s /usr/bin/killall ]; then
                killall yum
            else
                kill `pidof yum`
            fi
    	fi
}

config_pip() {
	mkdir -p ~/.pip
	cat > ~/.pip/pip.conf << EOF
[global]
index-url = http://pypi.douban.com/simple
[install]
use-mirrors =true
mirrors =http://pypi.douban.com/simple/
trusted-host =pypi.douban.com
EOF
}

PIP_INSTALL() {
	pip install $1 -i http://pypi.douban.com/simple/ --trusted-host pypi.douban.com > /dev/null 2>&1
	if [ $? -eq 0 ]
	then
	Echo_Green "$1 success to install"
	else
	Echo_Red "$1 fail to install"
	exit 1
	fi
}

config_env() {
	echo -e "\033[31m 2. 部署环境 \033[0m"
	ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
	yum -y install kde-l10n-Chinese
	localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8
	export LC_ALL=zh_CN.UTF-8
	echo 'LANG="zh_CN.UTF-8"' > /etc/locale.conf
	yum -y install wget gcc epel-release git
	yum install -y https://centos7.iuscommunity.org/ius-release.rpm
	yum install -y yum-utils device-mapper-persistent-data lvm2
	yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
	yum makecache fast
	rpm --import https://mirrors.aliyun.com/docker-ce/linux/centos/gpg
	echo -e "[nginx-stable]\nname=nginx stable repo\nbaseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/\ngpgcheck=1\nenabled=1\ngpgkey=https://nginx.org/keys/nginx_signing.key" > /etc/yum.repos.d/nginx.repo
	rpm --import https://nginx.org/keys/nginx_signing.key
	yum -y install redis mariadb mariadb-devel mariadb-server mariadb-shared nginx docker-ce
	systemctl start redis mariadb
	yum -y install python36u python36u-devel python36u-pip
	cd /opt
	if [ -s /usr/bin/python3.6 ]
	then
	python3.6 -m venv /opt/py3
	else
	Echo_Red "Python3.6 is not installed correctly, please install python3.6 manully"
	exit 1
	fi
	source /opt/py3/bin/activate
	cp $CurPWD/res/autoenv.tar.gz /opt/autoenv.tar.gz
	cd /opt
	rm -rf /opt/autoenv
	tar xzvf /opt/autoenv.tar.gz
	echo 'source /opt/autoenv/activate.sh' >> ~/.bashrc
	source ~/.bashrc
}

config_yum_online() {
	cd /etc/yum.repos.d/
	mkdir backup
	mv *.repo ./backup
	wget http://mirrors.aliyun.com/repo/Centos-7.repo
#sed -i 's/$releasever/7/g' /etc/yum.repos.d/Centos-7.repo
	yum clean all
	yum makecache
	yum update -y
}

download_compoents() {
	echo -e "\033[31m 3. 下载组件 \033[0m"
	cd /opt
	if [ ! -d "/opt/jumpserver" ]
	then
	tar xzvf $CurPWD/res/jumpserver$JUMP_VER.tar.gz -C /opt/
	mv /opt/jumpserver$JUMP_VER /opt/jumpserver
	#echo "source /opt/py3/bin/activate" > /opt/jumpserver/.env
	fi
	if [ ! -f "/opt/luna.tar.gz" ]
	then
	wget https://demo.jumpserver.org/download/luna/1.4.8/luna.tar.gz
	tar xf luna.tar.gz
	chown -R root:root luna
	fi
	yum -y install $(cat /opt/jumpserver/requirements/rpm_requirements.txt)
	pip install --upgrade pip setuptools -i http://pypi.douban.com/simple/ --trusted-host pypi.douban.com
	#pip install -r /opt/jumpserver/requirements/requirements.txt -i http://pypi.douban.com/simple/ --trusted-host pypi.douban.com
	for module in `cat /opt/jumpserver/requirements/requirements.txt`
	do
	PIP_INSTALL $module
	done
	curl -sSL https://get.daocloud.io/daotools/set_mirror.sh | sh -s http://f1361db2.m.daocloud.io
	systemctl restart docker
	docker ps | grep jms
	if [ $? -nq 0 ]
	then
	docker pull jumpserver/jms_coco:1.4.8
	docker pull jumpserver/jms_guacamole:1.4.8
	fi
	rm -rf /etc/nginx/conf.d/default.conf
	wget -O /etc/nginx/conf.d/jumpserver.conf https://demo.jumpserver.org/download/nginx/conf.d/jumpserver.conf
	systemctl restart nginx
	systemctl enable nginx
}

make_configrations() {
	echo -e "\033[31m 4. 处理配置文件 \033[0m"
	if [ "$DB_PASSWORD" = "" ]
	then
	DB_PASSWORD=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 24`
	echo "DB_PASSWORD=$DB_PASSWORD" >> ~/.bashrc
	fi
	if [ "$SECRET_KEY" = "" ]
	then
	SECRET_KEY=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 50`
	echo "SECRET_KEY=$SECRET_KEY" >> ~/.bashrc
	fi
	if [ "$BOOTSTRAP_TOKEN" = "" ]
	then
	BOOTSTRAP_TOKEN=`cat /dev/urandom | tr -dc A-Za-z0-9 | head -c 16`
	echo "BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN" >> ~/.bashrc
	fi
	if [ "$Server_IP" = "" ]
	then
	Server_IP=`ip addr | grep inet | egrep -v '(127.0.0.1|inet6|docker)' | awk '{print $2}' | tr -d "addr:" | head -n 1 | cut -d / -f1`
	echo "Server_IP=$Server_IP" >> ~/.bashrc
	fi
	if [ ! -d "/var/lib/mysql/jumpserver" ]
	then
	mysql -uroot -e "create database jumpserver default charset 'utf8';grant all on jumpserver.* to 'jumpserver'@'127.0.0.1' identified by '$DB_PASSWORD';flush privileges;"
	fi
	if [ ! -f "/opt/jumpserver/config.yml" ]
	then
	cp /opt/jumpserver/config_example.yml /opt/jumpserver/config.yml
	sed -i "s/SECRET_KEY:/SECRET_KEY: $SECRET_KEY/g" /opt/jumpserver/config.yml
	sed -i "s/BOOTSTRAP_TOKEN:/BOOTSTRAP_TOKEN: $BOOTSTRAP_TOKEN/g" /opt/jumpserver/config.yml
	sed -i "s/# DEBUG: true/DEBUG: false/g" /opt/jumpserver/config.yml
	sed -i "s/# LOG_LEVEL: DEBUG/LOG_LEVEL: ERROR/g" /opt/jumpserver/config.yml
	sed -i "s/# SESSION_EXPIRE_AT_BROWSER_CLOSE: false/SESSION_EXPIRE_AT_BROWSER_CLOSE: true/g" /opt/jumpserver/config.yml
	sed -i "s/DB_PASSWORD: /DB_PASSWORD: $DB_PASSWORD/g" /opt/jumpserver/config.yml
	fi
}

start_jumpserver() {
	echo -e "\033[31m 5. 启动 Jumpserver \033[0m"
	cd /opt/jumpserver
	./jms start -d
	docker run --name jms_coco -d -p 2222:2222 -p 5000:5000 -e CORE_HOST=http://$Server_IP:8080 -e BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN jumpserver/jms_coco:1.4.8
	docker run --name jms_guacamole -d -p 8081:8081 -e JUMPSERVER_SERVER=http://$Server_IP:8080 -e BOOTSTRAP_TOKEN=$BOOTSTRAP_TOKEN jumpserver/jms_guacamole:1.4.8
	echo -e "\033[31m 你的数据库密码是 $DB_PASSWORD \033[0m"
	echo -e "\033[31m 你的SECRET_KEY是 $SECRET_KEY \033[0m"
	echo -e "\033[31m 你的BOOTSTRAP_TOKEN是 $BOOTSTRAP_TOKEN \033[0m"
	echo -e "\033[31m 你的服务器IP是 $Server_IP \033[0m"
	echo -e "\033[31m 请打开浏览器访问 http://$Server_IP 用户名:admin 密码:admin \033[0m"
}

config_autostart() {
	echo -e "\033[31m 6. 配置自启 \033[0m"
	systemctl enable nginx
	if [ ! -f "/usr/lib/systemd/system/jms.service" ]
	then
	wget -O /usr/lib/systemd/system/jms.service https://demo.jumpserver.org/download/shell/1.4.8/centos/jms.service
	chmod 755 /usr/lib/systemd/system/jms.service
	systemctl enable jms
	fi
	if [ ! -f "/opt/start_jms.sh" ]
	then
	wget -O /opt/start_jms.sh https://demo.jumpserver.org/download/shell/1.4.8/centos/start_jms.sh
	fi
	if [ ! -f "/opt/stop_jms.sh" ]
	then
	wget -O /opt/stop_jms.sh https://demo.jumpserver.org/download/shell/1.4.8/centos/stop_jms.sh
	fi
	if [ "$(cat /etc/rc.local | grep start_jms.sh)" == "" ]
	then
	echo "sh /opt/start_jms.sh" >> /etc/rc.local
	chmod +x /etc/rc.d/rc.local
	fi
	echo -e "\033[31m 启动停止的脚本在 /opt 目录下, 如果自启失败可以手动启动 \033[0m"
}

# Begin to install jumpserver
action=$1
JUMP_VER=$2
[ -z $1 ] && action=install
[ -z $2 ] && JUMP_VER=`echo '-1.4.10'`
case "${action}" in
    install)
		config_firewall
		kill_PM
		config_pip
		config_yum_online
		config_env
		download_compoents
		make_configrations
		start_jumpserver
		config_autostart
        ;;
    *)
        echo "Arguments error! [${action}]"
        echo "Usage: $(basename $0) install"
        ;;
esac

exit
