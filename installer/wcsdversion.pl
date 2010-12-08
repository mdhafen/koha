use strict;
use warnings;

use C4::Context;

my $dbh = C4::Context->dbh;

if ( @ARGV && $ARGV[0] eq 'run' ) {
    my $DB_version = C4::Context->preference('WCSDVersion') || 0;
    my @strings = split /\|/, $DB_version;
    $DB_version = shift @strings;
    $DB_version += 0;
    my %revisions = map { $_ => 1 } @strings;
    my ( $rev, $version_string );

    my $WCSD_version = '1.00.00.001';
    if ( $DB_version < TransformToNum($WCSD_version) ) {
	$version_string = '1.0000001';

	$rev = 'wcsd_nuib';
	unless ( $revisions{ $rev } ) {
	    $dbh->do("");
	    print "Non-Unique Item Barcodes update";
	    $version_string += '|wcsd_nuib';
	    SetVersion( $version_string );
	}
    }
}

sub wcsd_version {
    our $VERSION = '1.00.00.001';
    return $VERSION;
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

exit;
