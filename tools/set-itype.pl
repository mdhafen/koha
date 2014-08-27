#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA
#
#   Written by Michael Hafen mdhafen@tech.washk12.org on Nov. 2008


=head1 set-itype.pl

This script sets the item level itype where it isn't set by examining the call number

=cut

use strict;
use CGI;
use C4::Auth;
use C4::Output;
use C4::Biblio;  # GetBiblio
use C4::Items;  # AddItem GetItemnumberFromBarcode
use C4::Koha;  # getitemtypeinfo GetItemTypes
use C4::Branch;  # GetBranches

my $cgi = new CGI;

# getting the template
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "tools/set-itype.tmpl",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { management => 1, tools => 1 },
    }
);

my $dbh = C4::Context->dbh;
my $op       = $cgi->param( 'op' );
my $branch   = $cgi->param( 'branch' ) || C4::Context->userenv->{'branch'};
my $search   = $cgi->param( 'search' );
my $itype    = $cgi->param( 'itype' );
my $oldtype  = $cgi->param( 'oldtype' );
my $backport = $cgi->param( 'backport' );

my $itemtypes = GetItemTypes;
my ( $items_set, $bibs_set ) = ( 0, 0 );

$itype = '' unless ( $itemtypes->{$itype}{itemtype} );
unless ( $itemtypes->{$oldtype}{itemtype} ) {
    $template->param( BAD_OLDTYPE => $oldtype );
    $oldtype = '';
}

$template->param( NO_BRANCH => 1 ) unless ( $branch );
$template->param( NO_ITYPE => 1 ) unless ( $op ne 'Set' || $itype );

if ( $op eq 'Set' && $search && $itype ) {
    my $query = "
SELECT i.itemnumber, i.biblioitemnumber, i.biblionumber, i.itemcallnumber,
       bi.itemtype
FROM items AS i
CROSS JOIN biblioitems AS bi USING ( biblioitemnumber )
WHERE homebranch = ". $dbh->quote( $branch );

    if ( $oldtype ) {
	$query .= "
  AND itype = ". $dbh->quote( $oldtype );
    } else {
	$query .= "
  AND ( itype = '' OR itype IS NULL )";
    }

    my $sth = $dbh->prepare( $query );
    $sth->execute;

    while ( my @row = $sth->fetchrow_array ) {
	my ( $itemnumber, $biblioitem, $biblio, $callnum, $itemtype ) = @row;

	next unless ( $callnum =~ /^$search/i );

	my $item = { 'itype' => $itype };
	ModItem( $item, $biblio, $itemnumber );
	$items_set++;

	unless ( $itemtype ) {
	    my $framework = GetFrameworkCode( $biblio );
	    $framework = '' unless ( $framework );
	    my ( $itypetag, $itypefield ) = GetMarcFromKohaField( "biblioitems.itemtype", $framework );
	    my $record = GetMarcBiblio( $biblio );

	    if ( my $koha_field = $record->field( $itypetag ) ) {
		$koha_field->update( $itypefield => $itype );
	    } else {
		my $new_field = new MARC::Field( $itypetag, '0', '0',
						 $itypefield => $itype );
		$record->add_fields( $new_field );
	    }

	    &ModBiblio( $record, $biblio, $framework );
	    $bibs_set++;
	}
    }

    $template->param(
	OP => $op,
	ITEMS_SET => $items_set,
	BIBS_SET => $bibs_set,
	);
}
elsif ( $op eq 'Backport' && $backport ) {
    my $query = "
SELECT i.homebranch, GROUP_CONCAT(i.itype) as itypes, bi.biblionumber, bi.itemtype
  FROM items AS i
 CROSS JOIN biblioitems AS bi USING ( biblioitemnumber )
 WHERE ( bi.itemtype = '' OR bi.itemtype IS NULL )
GROUP BY i.biblioitemnumber having homebranch = ". $dbh->quote( $branch );

    my $sth = $dbh->prepare( $query );
    $sth->execute;

    while ( my @row = $sth->fetchrow_array ) {
	my ( $hbranches, $itypes, $biblio, $itemtype ) = @row;

        next if ( index($itypes,',') != -1 );
        next unless ( $itypes );

	unless ( $itemtype ) {
	    my $framework = GetFrameworkCode( $biblio );
	    $framework = '' unless ( $framework );
	    my ( $itypetag, $itypefield ) = GetMarcFromKohaField( "biblioitems.itemtype", $framework );
	    my $record = GetMarcBiblio( $biblio );

	    if ( my $koha_field = $record->field( $itypetag ) ) {
		$koha_field->update( $itypefield => $itypes );
	    } else {
		my $new_field = new MARC::Field( $itypetag, '0', '0',
						 $itypefield => $itypes );
		$record->add_fields( $new_field );
	    }

	    &ModBiblio( $record, $biblio, $framework );
	    $bibs_set++;
	}
    }

    $template->param(
	OP => $op,
	BIBS_SET => $bibs_set,
	);
}

my @itemtypesloop;
foreach my $thisitemtype (sort keys %$itemtypes) {
    my %row =(value => $thisitemtype,
	      description => $itemtypes->{$thisitemtype}->{'description'},
	);
    push @itemtypesloop, \%row;
}

unless ( C4::Context->preference('IndependantBranches') ) {
    my $branches = GetBranches();
    my @branchloop;

    foreach my $thisbranch ( sort keys %$branches ) {
	my %row = (
	    value    => $thisbranch,
	    label    => $branches->{$thisbranch}->{'branchname'},
	    selected => ( $branches->{$thisbranch}->{'branchcode'} eq $branch ),
	    );
	push @branchloop, \%row;
    }
    $template->param(
	branchloop => \@branchloop,
	);
}

$template->param(
    itemtypeloop => \@itemtypesloop,
    ITEM_ITEMTYPES => C4::Context->preference('item-level_itypes'),
    );

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
