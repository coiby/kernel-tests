Name:           ad_hoc_server
Version:        1.0
Release:        2%{?dist}
Summary:        Server to allow the setup and teardown of IBSS connections.
License:        GPLv2
Source0:        %{name}.py
Source1:        %{name}.service
Source2:        %{name}.sysconf

BuildArch:      noarch
BuildRequires:  python3
BuildRequires:  python3-devel

Requires:       python3
Requires:       python3-flask
Requires:       python3-gunicorn
Requires:       NetworkManager >= 1.0.0
Requires:       NetworkManager-wifi
Requires:       iw

Provides:       python3-%{name}

%description
A server that allows for the remote setup and teardown of IBSS connections through a REST API.

%install
install -D -m 0644 %{SOURCE0} %{buildroot}/%{python3_sitelib}/%{name}.py
install -D -m 0644 %{SOURCE1} %{buildroot}/%{_unitdir}/%{name}.service
install -D -m 0644 %{SOURCE2} %{buildroot}/%{_sysconfdir}/sysconfig/%{name}

%post
systemctl start %{name}.service
systemctl enable %{name}.service

%preun
systemctl stop %{name}.service
systemctl disable %{name}.service

%files
%{python3_sitelib}/%{name}.py
%{python3_sitelib}/__pycache__/*
%{_unitdir}/%{name}.service
%{_sysconfdir}/sysconfig/%{name}

%changelog
* Fri Dec 02 2016 Ken Benoit <kbenoit@redhat.com> - 1.0-2
- Added sysconf file.
- Moved REST API port number to sysconf file.
- Fixed description of System object in ad_hoc_server.py.
- Corrected uninstall process for RPM.

* Fri Nov 18 2016 Ken Benoit <kbenoit@redhat.com> - 1.0-1
- Initial RPM release.
