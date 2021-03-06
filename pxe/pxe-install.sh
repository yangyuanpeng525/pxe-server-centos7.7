#!/bin/bash

#当前执行路径
current_path=`pwd`

#判断用户是否为：root
if [ `env |grep USER | cut -d "=" -f 2` != "root" ];then
   echo "请切换到root用户执行该程序！！！" && exit
fi

if [ $# -le 2 ] || [ $1 == "--help" ];then
  echo "Usage: $0 <dhcp_subnet|eg:192.168.200.0> <dhcp_netmask|eg:255.255.255.0> <tftp_ip|eg:ip_addr>"
  echo ""
  echo "Try $0 --help for more help."
  exit
fi

#配置离线yum源
yum_url=${current_path}/iso/centos7.7/
  
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
  echo "本地离线yum源部署完成"
fi
#-----------------------------------------
#yum安装dhcp
type dhcpd &> /dev/null ||  yum -y install dhcp &> /dev/null
type dhcpd &> /dev/null && echo "dhcp安装成功"

local_gateway=`ip route show | grep -i  'default' | awk '{print $3}'`

cat > /etc/dhcp/dhcpd.conf  <<EOF
subnet ${subnet} netmask ${netmask} { #分配的网段
  range 192.168.4.100  192.168.4.200;    #分配的IP地址范围
  option domain-name-servers 114.114.114.114; #分配的DNS地址
  option routers ${local_gateway};    #分配的网关地址
  default-lease-time 600;  #默认IP地址租用时间
  max-lease-time 7200;   #最大IP地址的租用时间
  next-server ${tftp_ip};  #指定下一个服务器的IP地址，tftp服务器
  filename  "pxelinux.0";   #指定网卡引导文件的名称
}
EOF






