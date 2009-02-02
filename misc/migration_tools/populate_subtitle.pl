#!/usr/bin/perl

BEGIN {
    # find Koha's Perl modules
    # test carefully before changing this
    use FindBin;
    eval { require "$FindBin::Bin/../kohalib.pl" };
}

use C4::Biblio;
use C4::Items;
use C4::Context;

my $dbh = C4::Context->dbh;

#my $branch = shift @ARGV;
#die "No branch code given" unless ($branch);

my $bibs_sth = $dbh->prepare( "SELECT biblionumber FROM biblio WHERE subtitle IS NULL or subtitle = ''" );
my $update_sth = $dbh->prepare( "UPDATE biblio SET subtitle = ? WHERE biblionumber = ?" );

$bibs_sth->execute();
while ( my ( $biblionumber ) = $bibs_sth->fetchrow ) {
	my $framework = GetFrameworkCode( $biblionumber ) || '';

	my ( $rottag, $rotfield ) = GetMarcFromKohaField( "biblio.subtitle", $framework );

	# Get biblio marc
	my $biblio = GetMarcBiblio( $biblionumber );

	# pull remainderoftitle from marc
	my $subtitle = $biblio->subfield( $rottag, $rotfield ) || '';

	# update database
	$update_sth->execute( $subtitle, $biblionumber ) if ( $subtitle );
}
