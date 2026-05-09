Name:     dirless-cli
Version:  %{pkg_version}
Release:  1
Summary:  Enroll Linux nodes with Dirless — AWS IAM Identity Center to native Linux identities
License:  Apache-2.0
URL:      https://dirless.com
Source0:  dirless-cli

# Fully static musl binary — no shared library dependencies.
AutoReqProv: no

%description
dirless-cli enrolls Linux nodes with Dirless, mapping AWS IAM Identity Center
users to native Linux identities without LDAP or a directory service.

%install
install -Dm 0755 %{SOURCE0} %{buildroot}%{_bindir}/dirless-cli

%files
%{_bindir}/dirless-cli
