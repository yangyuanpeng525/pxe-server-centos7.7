#!/bin/bash

#当前执行路径
current_path=`pwd`
version=centos7.7
wget_test_file=CentOS_BuildTag
email_address=yang.yuanpeng@trs.com.cn

#判断用户是否为：root
if [ `env |grep -e "^USER=" | cut -d "=" -f 2` != "root" ];then
   echo "请切换到root用户执行该程序！！！" && exit 1
fi

#判断是否正确输入参数
if [ $# -le 5 ] || [ $1 == "--help" ];then
  echo -e "Usage: \n/usr/bin/bash $0 <dhcp_subnet|eg:192.168.200.0> <dhcp_netmask|eg:255.255.255.0> <dhcp_begin|eg:192.168.200.1> <dhcp_end|192.168.200.254> <local_gateway|eg:192.168.200.1> <tftp_ip|eg:ip_addr>"
  echo -e "\nFor example:"
  echo "/usr/bin/bash ./pxe-install.sh 192.168.200.0 255.255.255.0 192.168.200.1 192.168.200.254  192.168.200.1 192.168.200.22"
  echo -e "\nTry \`$0 --help\` for more help."
  echo "Mail bug reports and suggestions to <${email_address}>."
  exit 120
fi

#-----------------------------------
#selinux+firewalld
setenforce 0 &> /dev/null 
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
systemctl stop  firewalld.service &> /dev/null  && systemctl disable firewalld.service &> /dev/null
#----------------------------------
#配置离线yum源
yum_url=${current_path}/iso/${version}/
  
#备份已有的yum源文件
ls -d /etc/yum.repos.d/yum_bak &> /dev/null || mkdir -p /etc/yum.repos.d/yum_bak 
mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/yum_bak
yum_file=centos7.7.repo  

cat > /etc/yum.repos.d/${yum_file} <<EOF
[centos7.7-localhost]
name=Centos7.7 - 本地离线yum
baseurl=file://${yum_url}
enabled=1
gpgcheck=0
EOF

if [ `yum clean all &> /dev/null && yum repolist | grep repolist |  awk '{print $2}'` != "0" ];then
  echo "本地离线yum源部署完成."
fi

#-----------------------------------------
#yum安装dhcp
type dhcpd &> /dev/null 
if [ $? != "0" ];then
  yum -y install dhcp &> /dev/null
  if [ $? != "0" ];then
    rpm -ivh ./Packages/dhc*.rpm --force --nodeps &> /dev/null
#    rpm -ivh ./Packages/dhclient-4.2.5-82.el7.centos.x86_64.rpm &> /dev/null
#    rpm -ivh ./Packages/dhcp-common-4.2.5-82.el7.centos.x86_64.rpm &> /dev/null
#    rpm -ivh ./Packages/dhcp-libs-4.2.5-82.el7.centos.x86_64.rpm &> /dev/null
#    rpm -ivh ./Packages/dhcp-4.2.5-82.el7.centos.x86_64.rpm &> /dev/null
  fi
fi
#传入dhcp参数

subnet=$1
netmask=$2
dhcp_begin=$3
dhcp_end=$4
local_gateway=$5
tftp_ip=$6
apache_ip=$6

cat > /etc/dhcp/dhcpd.conf  <<EOF
subnet ${subnet} netmask ${netmask} { #分配的网段
  range ${dhcp_begin} ${dhcp_end};    #分配的IP地址范围
  option domain-name-servers 114.114.114.114; #分配的DNS地址
  option routers ${local_gateway};    #分配的网关地址
  default-lease-time 600;  #默认IP地址租用时间
  max-lease-time 7200;   #最大IP地址的租用时间
  next-server ${tftp_ip};  #指定下一个服务器的IP地址，tftp服务器
  filename  "pxelinux.0";   #指定网卡引导文件的名称
}
EOF
#启动dhcpd，并检查状态
systemctl restart dhcpd &> /dev/null && systemctl enable dhcpd &> /dev/null

#定义检测函数:check_ok_for_server
#需要传参：1、服务名，2、端口（一个）
function check_ok_for_server {
  count=0
  while [ ${count} -lt 10 ]
  do 
    #`2> /dev/null`只忽略错误输出
    yum -y install net-tools &> /dev/null
    systemctl status $1 2> /dev/null | grep 'running' &> /dev/null && netstat -autnlp | grep ":$2" &> /dev/null && break
     let count_down=10-${count}
     echo "Waiting for $1...${count_down}"
     sleep 3
     let count+=1
     if [ ${count} -eq 10 ];then 
       echo "$1服务启动失败,请联系管理员."
       exit 2
     fi
  done 
  echo "$1服务启动成功."
}
check_ok_for_server dhcpd 67
#----------------------------
#启动httpd
yum -y install httpd &> /dev/null && systemctl restart httpd &> /dev/null && systemctl enable httpd &> /dev/null
check_ok_for_server httpd 80
#代理iso文件
mkdir -p /var/www/html/iso &> /dev/null
yum -y install rsync &> /dev/null
ls -d /var/www/html/iso &> /dev/null  && /usr/bin/rsync -av --delete ./iso/${version}/* /var/www/html/iso &> /dev/null
yum -y install wget &> /dev/null 
wget http://${apache_ip}/iso/${wget_test_file} &> /dev/null && echo "Apache访问正常." && rm -rf ./${wget_test_file}*
if [ $? != "0" ];then
  echo -e "Apache访问不正常,请联系管理员.\nhttp://${apache_ip}/iso/"
  exit 3
fi
#tftp
yum -y install tftp-server &> /dev/null && systemctl restart tftp &> /dev/null && systemctl enable tftp &> /dev/null
check_ok_for_server tftp 69
#准备相应文件
/usr/bin/cp -a  ./tftpboot/* /var/lib/tftpboot/ &> /dev/null 
if [ $? != "0" ];then 
  echo "Boot文件安装失败,请联系管理员."
  exit 3
fi

ls /var/lib/tftpboot/pxelinux.cfg/default &> /dev/null && sed -i "s/apache_ip/${apache_ip}/" /var/lib/tftpboot/pxelinux.cfg/default
echo "${version}镜像访问地址:http://${apache_ip}/iso/,可用于PXE安装源."
echo "恭喜你完成PXE服务端的部署,请在${subnet}/${netmask}域中进行PXE网络安装,网络安装服务器内存建议不少于2G."

#交互是否安装ks
while true
do
  read -p "是否继续安装无人值守kickstart:(Y/N)" input
  if [ ! "${input}" ];then
    continue
  fi
  if [ ${input} == "N" ] || [ ${input} == "Y" ];then 
    if [ ${input} == "N" ];then
      echo "安装完成."
      echo "如有疑问，请反馈至邮箱:<${email_address}>,感谢您的使用."
      exit 4
    else break
    fi 
  fi
done

#---------------------------------
#配置ks
/usr/bin/cp -a ./ks.cfg /var/www/html/ &> /dev/null && wget http://${apache_ip}/ks.cfg &> /dev/null && rm -rf ks.cfg.* &> /dev/null
if [ $? != "0" ];then
  echo "ks.cfg文件部署失败，请联系管理员."
  echo 5
fi
sed -i "s#inst.stage2=.*iso/#ks=http://${apache_ip}/ks.cfg#" /var/lib/tftpboot/pxelinux.cfg/default
sed -i "s/apache_ip/${apache_ip}/" /var/www/html/ks.cfg
echo "安装无人值守kickstart安装完成,默认系统最小化安装,root密码为:"\!QAZ2wsx12345678""
echo "如有疑问，请反馈至邮箱:<${email_address}>,感谢您的使用."

