Summary: signfiles Package
Name: signfiles
Version: 1
Release: 1
Group: System Environment/Base
License: GPL
BuildArch: noarch
BuildRoot:  %(mktemp -ud %{_tmppath}/%{name}-%{version}-%{release}-XXXXXX)
%description

This is a signfiles test package

%build
touch signfiles-empty.tmp
echo 11111111111111111111 > signfiles-ones.tmp
dd if=/dev/zero of=signfiles-sparse.tmp bs=1 count=0 seek=64M
ln -s signfiles-ones.tmp signfiles-ones-symlink.tmp
ln signfiles-ones.tmp signfiles-ones-hardlink.tmp

%install
mkdir -p %{buildroot}/usr/local/
mv signfiles-*.tmp %{buildroot}/usr/local/

%files
/usr/local/signfiles-empty.tmp
/usr/local/signfiles-ones.tmp
/usr/local/signfiles-sparse.tmp
/usr/local/signfiles-ones-symlink.tmp
/usr/local/signfiles-ones-hardlink.tmp
