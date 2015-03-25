#!/usr/bin/perl

use strict;
use warnings;

use C4::Context;

my $dbh = C4::Context->dbh;

# Revision block template...
#
#	$rev = '';
#	unless ( $revisions{ $rev } ) {
#	    $dbh->do("");
#	    print "\n";
#	    $version_changed = 1;
#	}
#	$version_string .= "|$rev";
#
#

if ( @ARGV && $ARGV[0] eq 'run' ) {
    my $DB_version = C4::Context->preference('WCSDVersion') || 0;
    my @strings = split /\|/, $DB_version;
    $DB_version = shift @strings;
    $DB_version += 0;
    my %revisions = map { $_ => 1 } @strings;
    my ( $rev, $version_string );
    my $version_changed = 0;

    my $WCSD_version = '1.00.00.001';
    if ( $DB_version <= TransformToNum($WCSD_version) ) {
	$version_string = '1.0000001';

	$rev = 'wcsd_nuib';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("ALTER TABLE items DROP KEY `itembarcodeidx`, ADD KEY `itembarcodeidx` (`barcode`)");
	    print "Non-Unique Item Barcodes update\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_bes';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("CREATE TABLE `borrowers_external_structure` (
  `externalid` int(11) NOT NULL auto_increment,
  `liblibrarian` varchar(255) NOT NULL default '',
  `kohafield` varchar(40) default NULL,
  `attrib` varchar(255) default NULL,
  `dblink` varchar(64) default NULL,
  `categorycode` varchar(10) NOT NULL default '',
  PRIMARY KEY  (`externalid`),
  KEY `bes_k_kohafield` (`kohafield`),
  KEY `bes_k_attrib` (`attrib`),
  KEY `bes_k_categorycode` (`categorycode`),
  CONSTRAINT `bes_fk_categorycode` FOREIGN KEY (`categorycode`) REFERENCES `categories` (`categorycode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8");
	    print "MembersFromExternal feature mapping table\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_nbcoppsp';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO `systempreferences` ( variable, value,
 explanation, options, type ) VALUES( 'NoBorrowerContactOnPrintPage', 1,
 'If ON, patrons mailing and email addresses are not listed on the Print Page screen',
NULL, 'YesNo' )");
	    print "NoBorrowerContactOnPrintPage System Preference\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_alesp';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO `systempreferences` ( variable, value,
 explanation, options, type ) VALUES ( 'AccountLinesEditable', 0,
 'If ON Patron account lines can be changed in the staff client', NULL, 'YesNo' )");
	    print "AccountLinesEditable System Preference\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_ahdifsp';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO `systempreferences` ( variable, value,
 explanation, options, type ) VALUES ( 'AllowHoldDateInFuture', '0',
 'If set a date field is displayed on the Hold screen of the Staff Interface, allowing the hold date to be set in the future.',
 '', 'YesNo' )");
	    $dbh->do("INSERT INTO `systempreferences` ( variable, value,
 explanation, options, type ) VALUES ( 'OPACAllowHoldDateInFuture', '0',
 'If set, along with the AllowHoldDateInFuture system preference, OPAC users can set the date of a hold to be in the future.',
 '', 'YesNo' )");

	    print "AllowHoldDateInFuture and OPACAllowHoldDateInFuture System Preferences\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_besf';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("alter table borrowers_external_structure add column filter varchar(64) default null after dblink");
	    print "Adding filter column to borrowers_external_structure table\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_smlfir';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("ALTER TABLE `branches` MODIFY COLUMN branchip mediumtext default NULL");
	    print "Extend branches branchip field to allow for multiple ip addresses\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_rot';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("ALTER TABLE `biblio` ADD COLUMN `remainderoftitle` mediumtext AFTER `title`");
	    print "Add remainderoftitle column to biblio table\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_ibiftws';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("UPDATE `systempreferences` SET options = 'whitespace|trim-whitespace|T-prefix|cuecat' WHERE variable = 'itemBarcodeInputFilter'");
	    print "Changing itemBarcodeInputFilter System Preference to add trim-whitespace option\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'sedc_crpi';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO `systempreferences` ( variable, value,
 explanation, options, type ) VALUES ( 'CircRestrictPreviouslyIssued', 0,
 'If set, when a title is checked out warn the staff if the patron has checked out this title before.',
 '', 'YesNo' )");
	    print "Add System Preference for CircRestrictPreviouslyIssued\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";
    }

    $WCSD_version = '1.00.00.002';
    if ( $DB_version <= TransformToNum($WCSD_version) ) {
	$version_string = '1.0000002';

	$rev = 'wcsd_aeub';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO `systempreferences` ( variable, value,
 explanation, options, type ) VALUES ( 'AllowEditUsedBiblio', 1,
 'If set to OFF librarians are not allowed to edit biblios also used by another library.  Otherwise they are allowed to edit any biblio as usual.',
 '', 'YesNo' )");
	    print "Add System Preference for AllowEditUsedBiblio\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";
    }

    $WCSD_version = '1.00.00.003';
    if ( $DB_version <= TransformToNum($WCSD_version) ) {
	$version_string = '1.0000003';

	$rev = 'wcsd_apclt';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO `creator_layouts` ( barcode_type,start_label,
 printing_type,layout_name,guidebox,font,font_size,units,callnum_split,
 text_justify,format_string,layout_xml,creator ) VALUES ( 'CODE39',1,'BAR',
 'Generic Patron Card',0,'TR',10,'POINT',0,'L','barcode',
 '<opt guide_box=\"0\" page_side=\"F\" units=\"POINT\">
 <barcode print=\"1\" text_print=\"1\" type=\"CODE39\" />
 <text>&lt;surname&gt; , &lt;firstname&gt;</text>
 <text font=\"TR\" font_size=\"11\" llx=\"0\" lly=\"25\" text_alignment=\"C\" />
</opt>','Patroncards' )");
	    $dbh->do("INSERT INTO `creator_templates` ( profile_id,
 template_code,template_desc,page_width,page_height,label_width,label_height,
 top_text_margin,left_text_margin,top_margin,left_margin,cols,rows,col_gap,
 row_gap,units,creator ) VALUES ( 0,'Avery 5160','Default template',8.5,11,
 2.625,1,0,0,0.5,0.1875,3,10,0.125,0,'INCH','Patroncards' )");
	    print "Add a basic template and layout for patron cards\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_afmfrot';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO `fieldmapping` ( field,fieldcode,subfieldcode ) VALUES ( 'subtitle', 245, 'b' ), ( 'additionaltitles', 740, 'a' ), ( 'additionaltitles', 740, 'p' )");
	    print "Adding MARC keyword mappings for Subtitle and Additional Titles\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_hwi';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO `systempreferences` ( variable, value,
 explanation, options, type ) VALUES ( 'HideWithdrawnItems', 1,
 'If set to ON items which are marked withdrawn will not be displayed in the OPAC in the search results or biblio details pages.',
 '', 'YesNo' )");
	    print "Add System Preference for HideWithdrawnItems\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";

	$rev = 'wcsd_aan';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO letter (module,code,name,title,content) VALUES ('accounts','FINE','Outstanding Patron Fines','Outstanding Library Fines','Dear <<borrowers.firstname>> <<borrowers.surname>>,
According to our current records, your account with the library has an outstanding balance.  Please contact the library as soon as possible.
<<branches.branchname>>
<<branches.branchaddress1>> <<branches.branchaddress2>> <<branches.branchaddress3>>
phone: <<branches.branchphone>>
fax: <<branches.branchfax>>
email: <<branches.branchemail>>

If you have registered a password with the library, you may use it with your library card number to see what fines and/or credits you have on your account.  The following fines need to be payed:

<<fines.content>>')");
	    print "Adding a sample notice for the account module with the FINE code\n";

            my $letters = $dbh->selectall_arrayref("SELECT * FROM letter WHERE module = 'reserves' AND code = 'PLACED'",{ Slice=>{}},);
            unless ( @$letters ) {
                $dbh->do("INSERT INTO letter (module,code,name,title,content) VALUES ('reserves','PLACED','Hold Placed','A hold has been placed','Dear Librarian,

A hold has been placed as of <<reserves.reservedate>>:

Patron: <<borrowers.firstname>> <<borrowers.surname>>
Title: <<biblio.title>>
Author: <<biblio.author>>')");
                print "Adding a sample notice for the reserves module with the code PLACED while I'm at it, which is used by opac code to notify the librarian of holds placed.\n";
            }

	    $version_changed = 1;
	}
	$version_string .= "|$rev";
    }

    $WCSD_version = '1.00.00.004';
    if ( $DB_version <= TransformToNum($WCSD_version) ) {
	$version_string = '1.0000004';

	$rev = 'wcsd_uaup';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("INSERT INTO permissions( module_bit, code, description ) VALUES
   (10, 'make_invoice', 'Add Charges to a borrowers account'),
   (10, 'make_credit', 'Add Payments to a borrowers account')");
	    print "Add more granular user permissions for updating a borrowers account.\n";
	    $version_changed = 1;
	}
	$version_string .= "|$rev";
    }

    # New revisions go here.

    if ( $version_changed ) {
	SetVersion( $version_string );
    }

    exit;
}

sub wcsd_version {
    our $VERSION = '1.00.00.004';
    return $VERSION;
}

sub wcsd_revision {
    our $REVISION = 'wcsd_uaup';
    return $REVISION;
}

1;

=item TransformToNum

  Transform the Koha version from a 4 parts string
  to a number, with just 1 .

=cut

sub TransformToNum {
    my $version = shift;
    # remove the 3 last . to have a Perl number
    $version =~ s/(.*\..*)\.(.*)\.(.*)/$1$2$3/;
    return $version;
}

=item SetVersion

    set the DBversion in the systempreferences

=cut

sub SetVersion {
    my $version = TransformToNum(shift);
    if ( C4::Context->preference('WCSDVersion') ) {
      my $finish = $dbh->prepare( "UPDATE systempreferences SET value=? WHERE variable='WCSDVersion'" );
      $finish->execute( $version );
    } else {
      my $finish = $dbh->prepare( "INSERT into systempreferences (variable,value,explanation) values ('WCSDVersion',?,'The WCSD revision level of the database. WARNING: Do not change this value manually, it is maintained by the webinstaller')" );
      $finish->execute( $version );
    }
}
