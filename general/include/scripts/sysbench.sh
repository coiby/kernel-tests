#!/bin/sh

if uname -r | grep el7; then
	yum -y install yum-utils mariadb-devel postgresql-devel libaio-devel
	wget http://download-node-02.eng.bos.redhat.com/brewroot/packages/sysbench/0.4.12/13.el7ostarch/src/sysbench-0.4.12-13.el7ostarch.src.rpm
	rpmbuild -bp sysbench-0.4.12-13.el7ostarch.src.rpm
	yum-builddep -y  sysbench-0.4.12-13.el7ostarch.src.rpm
	rpmbuild -bb ./sysbench-0.4.12-13.el7ostarch.src.rpm
	rpmbuild --rebuild -bb  ./sysbench-0.4.12-13.el7ostarch.src.rpm
	rpm -ivh /root/rpmbuild/RPMS/$(uname -m)/sysbench-0.4.12-13.el7.$(uname -m).rpm
elif  uname -r | grep el8; then
	wget http://download-node-02.eng.bos.redhat.com/brewroot/packages/sysbench/0.4.12/14.el8ost/src/sysbench-0.4.12-14.el8ost.src.rpm
	rpm -ivh sysbench-0.4.12-14.el8ost.src.rpm
	dnf builddep -y /root/rpmbuild/SPECS/sysbench.spec  --nobest --allowerasing
	dnf -y install  mariadb-devel postgresql-devel libaio-devel --nobest
	rpmbuild -bb /root/rpmbuild/SPECS/sysbench.spec
	rpm -ivh /root/rpmbuild/RPMS/$(uname -m)/sysbench-0.4.12-14.el8.$(uname -m).rpm
else
	wget http://download-node-02.eng.bos.redhat.com/brewroot/packages/sysbench/0.4.12/14.el8ost/src/sysbench-0.4.12-14.el8ost.src.rpm
	rpm -ivh sysbench-0.4.12-14.el8ost.src.rpm
	dnf builddep -y /root/rpmbuild/SPECS/sysbench.spec  --nobest --allowerasing
	dnf -y install  mariadb-devel postgresql-devel libaio-devel automake libtool --nobest --enablerepo=beaker-CRB
	rpmbuild -bb /root/rpmbuild/SPECS/sysbench.spec --noclean
	rpm -ivh /root/rpmbuild/RPMS/$(uname -m)/sysbench-0.4.12-14.el9.$(uname -m).rpm
fi
