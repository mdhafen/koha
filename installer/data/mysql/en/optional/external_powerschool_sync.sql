CREATE DATABASE isdkoha_powerschool
	DEFAULT CHARACTER SET utf8
	DEFAULT COLLATE utf8_general_ci
GO

DROP TABLE "Students"
GO

CREATE TABLE "Students"  ( 
	"First_Name"    	varchar(15) NULL,
	"SchoolID"      	int(11) NULL,
	"Student_Number"	int(11) NOT NULL DEFAULT '0',
	"Home_Phone"    	varchar(30) NULL,
	"City"          	varchar(50) NULL,
	"Zip"           	varchar(10) NULL,
	"Last_Name"     	varchar(20) NULL,
	"Street"        	varchar(60) NULL,
	"Home_Room"     	varchar(60) NULL,
	"Gender"        	varchar(2) NULL,
	"dob"           	date NULL,
	"Student_Web_ID"	varchar(20) NULL,
	"GuardianEmail" 	varchar(100) NULL,
	PRIMARY KEY("Student_Number")
)
GO

 
