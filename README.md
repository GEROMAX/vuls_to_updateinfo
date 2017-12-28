# vuls_to_updateinfo

This script create 'updateinfo.xml' file from [Vuls](https://github.com/future-architect/vuls) report file(xml) so that 'yum --security update' command can be executed on CentOS.

# Usage

1. Execute vuls scan and report(xml).

2. Create 'updateinfo.xml' file.
    > $ /some/path/ruby vuls_to_updateinfo.rb /vuls/report/file.xml

    * It will write 'updateinfo.xml' file at current directory.

3. Create repository for 'yum --security update'.
    > $ mkdir /somedirectory  
$ createrepo /somedirectory  
$ cd /somedirectory  
$ modifyrepo /some/path/updateinfo.xml repodata
    * Need package installation of 'createrepo'.

4. Add setting yum's repository at '/etc/yum.repos.d/CentOS-Base.repo'.
    > [security]  
name=CentOS-$releasever - Security  
baseurl=file:///somedirectory  

5. Try 'yum check-update'.
    > $ yum --security check-update

# Tested on

ruby
* 2.3.3
* 2.4.2
