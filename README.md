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
    * Need package installation of 'createrepo'.

4. Write 'updateinfo.xml' to repository.
    > $ cd /somedirectory  
$ modifyrepo /some/path/updateinfo.xml repodata

5. Add setting yum's repository at '/etc/yum.repos.d/CentOS-Base.repo'.
    > [security]  
name=CentOS-$releasever - Security  
baseurl=file:///somedirectory  

6. Try 'yum check-update'.
    > $ yum --security check-update

When security update found, do again step 2 and 4.

# Tested on

ruby
* 2.3.3
* 2.4.2
