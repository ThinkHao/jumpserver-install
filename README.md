# jumpserver-install
基于官方文档结合自己的理解，整理而成的jumpserver一键安装脚本
## 简介
Jumpserver 开源堡垒机为“FIT2CLOUD 飞致云”旗下子品牌。作为全球首款完全开源、符合 4A 规范的运维安全审计系统，Jumpserver 通过软件订阅服务或者软硬件一体机的方式，向企业级用户交付多云环境下更好用的堡垒机。
## How to use it
```
git clone https://github.com/thinkhao/jumpserver-install.git
cd jumpserver-install
chmod a+x ./install.sh
./install.sh
```
## 注意
如果脚本运行过程出现yum锁被占用的情况，多半是PackageKit占用导致，将其进程kill掉
`kill $(ps aux | grep PackageKit | awk '{print $2}')`
再次运行脚本即可
（后续有时间再尝试解决这个问题）
