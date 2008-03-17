INSERT INTO `borrowers_external_structure`
VALUES
(1,'First name','firstname','stugrp_active.firstname','stugrp_active.suniq = studemo.suniq','ST'),
(2,'Branch','branchcode','stugrp_active.schoolc','stugrp_active.suniq = studemo.suniq','ST'),
(3,'Card Number','cardnumber','stugrp_active.suniq','stugrp_active.suniq = studemo.suniq','ST'),
(4,'Phone','phone','studemo.phnnumber','stugrp_active.suniq = studemo.suniq','ST'),
(5,'City','city','stugrp_active.homecity','stugrp_active.suniq = studemo.suniq','ST'),
(6,'Gender','sex','stugrp_active.gender','stugrp_active.suniq = studemo.suniq','ST'),
(7,'Zip / Postal Code','zipcode','stugrp_active.homezip','stugrp_active.suniq = studemo.suniq','ST'),
(8,'Last Name','surname','stugrp_active.lastname','stugrp_active.suniq = studemo.suniq','ST'),
(9,'Street Address','address','stugrp_active.homeaddr1','stugrp_active.suniq = studemo.suniq','ST'),
(10,'Home Room Teacher','sort2','stugrp_active.advisor','stugrp_active.suniq = studemo.suniq','ST'),
(11,'Date of Birth','dateofbirth','CONVERT( VARCHAR(11), stugrp_active.birthdate, 120 ) AS DateOfBirth','stugrp_active.suniq = studemo.suniq','ST'),
(12,'Login Name','userid','Users.username','Users.username = studemo.ident','ST'),
(13,'Prefered Name','othernames','studemo.nickname','stugrp_active.suniq = studemo.suniq','ST'),
(14,'Graduation Year','sort1','studemo.gradyear','stugrp_active.suniq = studemo.suniq','ST'),
(15,'Login Password','password','Users.password','Users.username = studemo.ident','ST');
