Feature: DNF/Behave test (protected_packages test)

Scenario: Removal of installed protected package
 Given I use the repository "test-1"
 When I execute "dnf" command "install -y TestA" with "success"
 Then transaction changes are as follows
   | State        | Packages      |
   | installed    | TestA, TestB  |

 When I execute "dnf" command "-y remove TestA --setopt=protected_packages=TestA" with "failure"
 Then transaction changes are as follows
   | State        | Packages     |
   | absent       | TestA, TestB |
 And line from "stderr" should "start" with "Error: The operation would result in removing the following protected packages: TestA"

 When I execute "dnf" command "-y remove TestA --setopt=protected_packages=TestA" with "failure"
 Then transaction changes are as follows
   | State        | Packages     |
   | absent       | TestA, TestB |
 And line from "stderr" should "start" with "Error: The operation would result in removing the following protected packages: TestA"

 When I execute "dnf" command "-y remove TestB --setopt=protected_packages=TestA" with "failure"
 Then transaction changes are as follows
   | State        | Packages     |
   | absent       | TestA, TestB |

 When I execute "dnf" command "-y remove dnf" with "failure"
 Then transaction changes are as follows
   | State        | Packages     |
   | absent       | dnf          |
 And line from "stderr" should "start" with "Error: The operation would result in removing the following protected packages: dnf"

 When I create a file "/etc/yum/protected.d/donotremove" with content: "TestA"
 When I execute "dnf" command "-y remove TestA with "failure"
 Then transaction changes are as follows
   | State        | Packages     |
   | absent       | TestA, TestB |
