use DBI;
use strict;
use warnings;

#REMOTE / POWERSCHOOL DATABASE
my $ouser = '';
my $opasswd = '';
my $ohost = '';
my $osid = '';

my @Schools = (304, 116, 750);

#LOCAL DATABASE
my $mhost = '';
my $mdbname = '';
my $mdbuser = '';
my $mdbpass = '';
my $mysql_dbh = DBI->connect("DBI:mysql:database=$mdbname;host=$mhost",
                         $mdbuser, $mdbpass,
                         {'RaiseError' => 1});

#truncate local database table
  eval { $mysql_dbh->do("truncate TABLE Students") };
  print "Dropping foo failed: $@\n" if $@;


my $oracle_dbh = DBI->connect("dbi:Oracle:host=$ohost;sid=$osid", $ouser, $opasswd);

foreach(@Schools)
{
	my $SQL = "SELECT First_Name, SchoolID, Student_Number, Home_Phone, City, Zip,
	Last_Name, Street, ";

	if($_ == 304) #use custom field to get advisor
	{
		$SQL .= "ps_customfields.getcf('Students', id, 'Advisor')"
	}
	else
	{
		$SQL .= "Home_Room";
	}

	$SQL .= ", Gender, TO_CHAR( Students.DOB, 'yyyy-mm-dd' ) AS DOB, Student_Web_ID, GuardianEmail FROM Students WHERE schoolid = $_ and enroll_status = 0";
	my $sth = $oracle_dbh->prepare($SQL);  
	
	$sth->execute();
	
	while ( my ($firstname, $schoolid, $student_number, $home_phone, $city, $zip, $lastname, $street, $home_room, $gender, $dob, $students_web_id, $guardianemail) = $sth->fetchrow()) {
	$mysql_dbh->do("INSERT INTO Students VALUES (".$mysql_dbh->quote($firstname).",$schoolid,$student_number,".$mysql_dbh->quote($home_phone).",".$mysql_dbh->quote($city).",".$mysql_dbh->quote($zip).",".$mysql_dbh->quote($lastname).",".$mysql_dbh->quote($street).",".$mysql_dbh->quote($home_room).",".$mysql_dbh->quote($gender).",".$mysql_dbh->quote($dob).",".$mysql_dbh->quote($students_web_id).",".$mysql_dbh->quote($guardianemail).")");
	}
}
