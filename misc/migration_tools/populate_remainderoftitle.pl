#!/usr/bin/perl

#  Do it the Koha way, set your environment yourself!
#BEGIN {
#$ENV{KOHA_CONF} = "/usr/local/koha3/etc/koha-conf.xml";
#$ENV{DOCUMENT_ROOT} = "/usr/local/koha3/intranet/htdocs";
#push @INC, '/usr/local/koha3/lib';
#}

unless ( $ENV{KOHA_CONF} ) die "KOHA_CONF isn't set.";

use C4::Biblio;
use C4::Items;
use C4::Context;

my $dbh = C4::Context->dbh;

#my $branch = shift @ARGV;
#die "No branch code given" unless ($branch);

my $bibs_sth = $dbh->prepare( "SELECT biblionumber FROM biblio WHERE remainderoftitle IS NULL or remainderoftitle = ''" );
my $update_sth = $dbh->prepare( "UPDATE biblio SET remainderoftitle = ? WHERE biblionumber = ?" );

$bibs_sth->execute();
while ( my ( $biblionumber ) = $bibs_sth->fetchrow ) {
	my $framework = GetFrameworkCode( $biblionumber ) || '';

	my ( $rottag, $rotfield ) = GetMarcFromKohaField( "biblio.remainderoftitle", $framework );

	# Get biblio marc
	my $biblio = GetMarcBiblio( $biblionumber );

	# pull remainderoftitle from marc
	my $remainderoftitle = $biblio->subfield( $rottag, $rotfield ) || '';

	# update database
	$update_sth->execute( $remainderoftitle, $biblionumber ) if ( $remainderoftitle );
}
