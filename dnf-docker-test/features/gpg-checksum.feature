Feature: DNF/Behave test (gpg, check-sum)

Scenario: Add repository with gpgcheck=1 from repofile and control 'repolist' command
 Given I use the repository "test-1"
 When I execute "dnf" command "repolist" with "success"
 Then line from "stdout" should "start" with "test-1 "
 And line from "stdout" should "not start" with "test-1-gpg-file"
 When I execute "dnf" command "config-manager --add-repo http://127.0.0.1/repo/test-1-gpg/test-1-gpg-file.repo" with "success"
 When I execute "dnf" command "repolist test-1-g*" with "success"
 Then line from "stdout" should "not start" with "test-1 "
 And line from "stdout" should "start" with "test-1-gpg-file"

Scenario: GPG key import after package install
 When I execute "bash" command "rpm -q gpg-pubkey --qf '%{name}-%{version}-%{release} --> %{summary}\n'" with "success"
 Then line from "stdout" should "not start" with "gpg-pubkey-2d2e7ca3-56c1e69d --> gpg(DNF Test1 (TESTER) <dnf@testteam.org>)"
 When I execute "dnf" command "-y --disablerepo=test-1 install TestA" with "success"
 Then transaction changes are as follows
   | State        | Packages      |
   | installed    | TestA, TestB  |
 When I execute "bash" command "rpm -q gpg-pubkey --qf '%{name}-%{version}-%{release} --> %{summary}\n'" with "success"
 Then line from "stdout" should "start" with "gpg-pubkey-2d2e7ca3-56c1e69d --> gpg(DNF Test1 (TESTER) <dnf@testteam.org>)"
# Cleaning artifacts from test
 When I execute "dnf" command "-y remove TestA" with "success"
 Then transaction changes are as follows
   | State        | Packages      |
   | removed      | TestA, TestB  |

Scenario: Install signed package with unsigned dependecy from repository with gpgcheck=1
 When I execute "dnf" command "-y --disablerepo=test-1 install TestD" with "fail"
 Then transaction changes are as follows
   | State        | Packages      |
   | absent       | TestD, TestE  |

Scenario: Install signed package with signed dependece with different key from repository with gpgcheck=1
 When I execute "dnf" command "-y --disablerepo=test-1 install TestF" with "fail"
 Then transaction changes are as follows
   | State        | Packages             |
   | absent       | TestF, TestG, TestH  |

Scenario: Install package with incorrect checksum from repository with gpgcheck=1
 Then the file "/var/cache/dnf/expired_repos.json" should contain "[]"
 When I execute "dnf" command "-y --disablerepo=test-1 install TestJ" with "fail"
 Then transaction changes are as follows
   | State        | Packages   |
   | absent       | TestJ      |
 Then the file "/var/cache/dnf/expired_repos.json" should contain "["test-1-gpg-file"]"
 When I execute "dnf" command "makecache" with "success"
 Then the file "/var/cache/dnf/expired_repos.json" should contain "[]"

Scenario: Add repository with gpgcheck=0 and install package with unknown key and signed and unsigned packages
 Given I use the repository "test-1-gpg"
 When I execute "dnf" command "-y install TestF" with "success"
 Then transaction changes are as follows
   | State        | Packages             |
   | installed    | TestF, TestG, TestH  |
 When I execute "dnf" command "-y install TestD" with "success"
 Then transaction changes are as follows
   | State        | Packages      |
   | installed    | TestD, TestE  |
# Cleaning artifacts from test
 When I execute "dnf" command "-y remove TestF TestD" with "success"
 Then transaction changes are as follows
   | State        | Packages                           |
   | removed      | TestD, TestE, TestF, TestG, TestH  |

Scenario: Add repository with without gpgcheck and try to install insigned package (test if gpgcheck is taken from dnf.conf)
 Given I use the repository "test-1"
 When I create a file "/etc/yum.repos.d/gpg.repo" with content: "[gpg]\nname=gpg\nbaseurl=http://127.0.0.1/repo/test-1\nenabled=1"
 Then the path "/etc/yum.repos.d/gpg.repo" should be "present"
 When I execute "dnf" command "-y --disablerepo=test-1 install TestC" with "fail"
 Then transaction changes are as follows
   | State        | Packages   |
   | absent       | TestC      |
 When I execute "dnf" command "-y --disablerepo=test-1 --nogpgcheck install TestC" with "success"
 Then transaction changes are as follows
   | State        | Packages   |
   | installed    | TestC      |

#It is brocken - activate after fix in dnf - if gpgcheck=0 dnf doesn't controle checksum (https://bugzilla.redhat.com/show_bug.cgi?id=1314405)
#Scenario: Install package with incorrect checksum from repository with gpgcheck=0
# Given I use the repository "test-1-gpg"
# Then the file "/var/cache/dnf/expired_repos.json" should contain "[]"
# When I execute "dnf" command "-y install TestJ" with "fail"
# Then transaction changes are as follows
#   | State        | Packages   |
#   | absent       | TestJ      |
# Then the file "/var/cache/dnf/expired_repos.json" should contain "["test-1-gpg"]"
