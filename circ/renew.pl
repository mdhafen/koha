#!/usr/bin/perl


#copied from reserves/renewscript.pl written 18/1/2000 by chris@katipo.co.nz
#page to renew items with their barcode


# Copyright 2000-2002 Katipo Communications
#
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

use strict;
use CGI;
use C4::Auth qw/:DEFAULT get_session/;
use C4::Context;
use C4::Output;
use C4::Circulation;
use C4::Items;
use C4::Biblio;
use C4::Dates qw/format_date/;
use C4::Members;

my $input = new CGI;

#Set Up User_env
# And assures user is loggedin  and has correct accreditations.

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "circ/renew.tmpl",
        query           => $input,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { circulate => 1 },
    }
);


# Set up the item stack ....
my @inputloop;
foreach ( $input->param ) {
    (next) unless (/ri-(\d*)/);
    my %renew_input;
    my $counter = $1;
    (next) if ( $counter > 20 );
    my $barcode        = $input->param("ri-$counter");
    my $duedate        = $input->param("dd-$counter");
    my $borrowernumber = $input->param("bn-$counter");

    # decode barcode
    $barcode = barcodedecode( $barcode ) if ( C4::Context->preference('itemBarcodeInputFilter') );

    $renew_input{counter}        = $counter;
    $renew_input{barcode}        = $barcode;
    $renew_input{duedate}        = $duedate;
    $renew_input{borrowernumber} = $borrowernumber;
    $inputloop[ $counter ] = \%renew_input;
    $counter++;
}

my $sessionID = $input->cookie("CGISESSID") ;
my $session = get_session($sessionID);
my ( $soundok, $sounderror );
my @soundederrors = @{ $session->param( 'soundederrors' ) } if ( $session->param( 'soundederrors' ) );
my %soundederrors;
for ( @soundederrors ) { $soundederrors{ $_ } = 1; }
my $branch = C4::Context->userenv->{'branch'};
my $overduecharges = ( C4::Context->preference('finesMode') && C4::Context->preference('finesMode') ne 'off' );
my $calendar = C4::Calendar->new( branchcode => $branch );
#dropbox: get last open day (today - 1)
my $dropboxdate = $calendar->addDate( C4::Dates->new(), -1 );
my $dropboxmode = $input->param('dropboxmode');
my $stickyduedate = $input->param('stickyduedate') || $session->param( 'stickyduedate' );
my $duedatespec = $input->param('newduedate') || $session->param( 'stickyduedate' );
my $datedue;
if ( $duedatespec ) {
    $datedue = C4::Dates->new( $duedatespec );
}
my $override_limit = $input->param("override_limit") || 0;
my $barcode = $input->param('barcode');
$barcode = barcodedecode( $barcode ) if ( $barcode && C4::Context->preference('itemBarcodeInputFilter') );

#
# renew items
#
my @messages;

# check status before renewing issue
if ( $barcode ) {
    my $itemno = GetItemnumberFromBarcode( $barcode );
    my $itemissue = ( $itemno ) ? GetItemIssue( $itemno ) : 0;
    my $borrowernumber = ( $itemissue && defined( $itemissue->{borrowernumber} ) ) ? $itemissue->{borrowernumber} : 0;

    my ( $renewokay, $error ) = CanBookBeRenewed( $borrowernumber, $itemno, $override_limit );
    if ( $renewokay ) {
	AddRenewal( $borrowernumber, $itemno, $branch, $datedue );

	# Simple Patron Checks
	my ($borrower) = C4::Members::GetMemberDetails( $borrowernumber, 0 );
	if ( $borrower->{borrowernumber} != $session->param( 'borrowernumber' ) ) {
	    $session->clear( 'soundederrors' );
	    @soundederrors = ();
	    %soundederrors = ();
	    $session->param( 'borrowernumber', $borrower->{borrowernumber} );
	}
	my $flags = $borrower->{'flags'};
	foreach my $flag ( sort keys %$flags ) {
	    my %flaginfo;
	    if ( $flag eq 'CHARGES' ) {
		unless ( $soundederrors{ CHARGES } ) {
		    $sounderror = 1;
		    $soundederrors{ CHARGES } = 1;
		}
		$flaginfo{charges} = 1;
		$flaginfo{msg} = $flag;
		$flaginfo{chargeamount} = $flags->{ $flag }->{amount};
	    }
	    elsif ( $flag eq 'WAITING' ) {
		unless ( $soundederrors{ WAITING } ) {
		    $sounderror = 1;
		    $soundederrors{ WAITING } = 1;
		}
		$flaginfo{waiting} = 1;
		$flaginfo{msg}     = $flag;
	    }
	    elsif ( $flag eq 'ODUES' ) {
		unless ( $soundederrors{ ODUES } ) {
		    $sounderror = 1;
		    $soundederrors{ ODUES } = 1;
		}
		$flaginfo{overdue}  = 1;
		$flaginfo{msg} = $flag;
	    }
	    push( @messages, \%flaginfo ) if ( %flaginfo );
	}
	$soundok = 1 unless ( $sounderror );

	foreach my $ri ( @inputloop ) {
	    $$ri{counter}++;  # prepare for unshift below
	}
	my %renew_input;
	$itemissue = GetItemIssue( $itemno );
	my $newduedate = $itemissue->{date_due};
	$renew_input{counter}        = 0;
	$renew_input{barcode}        = $barcode;
	$renew_input{duedate}        = format_date( $newduedate );
	$renew_input{borrowernumber} = $borrowernumber;
	unshift @inputloop, \%renew_input;
    } else {
	push @messages, { norenew => 1, msg => $error };
	$sounderror = 1;
    }
}

my @riloop;
my $count = 0;
foreach my $ri ( @inputloop ) {
    last if ( $count > 8 );

    my ( $borrower ) = GetMemberDetails( $$ri{borrowernumber}, 0 );
    $$ri{borcnum}        = $borrower->{'cardnumber'};
    $$ri{borfirstname}   = $borrower->{'firstname'};
    $$ri{borsurname}     = $borrower->{'surname'};
    $$ri{bortitle}       = $borrower->{'title'};
    $$ri{bornote}        = $borrower->{'borrowernotes'};

    my $biblio = GetBiblioFromItemNumber(GetItemnumberFromBarcode($$ri{barcode}));
    # fix up item type for display
    $biblio->{'itemtype'} = C4::Context->preference('item-level_itypes') ? $biblio->{'itype'} : $biblio->{'itemtype'};
    $$ri{itembiblionumber} = $biblio->{'biblionumber'};
    $$ri{itemtitle}        = $biblio->{'title'};
    $$ri{itemauthor}       = $biblio->{'author'};
    $$ri{itemtype}         = $biblio->{'itemtype'};
    $$ri{itemnote}         = $biblio->{'itemnotes'};
    $$ri{ccode}            = $biblio->{'ccode'};
    $$ri{itemnumber}       = $biblio->{'itemnumber'};

    if ( $biblio->{'remainderoftitle'} ) {
	$$ri{itemtitle} .= " ". $biblio->{'remainderoftitle'};
    }

    $count++;
    push @riloop, $ri;
}

$session->param('soundederrors', [ keys %soundederrors ] );
$template->param(
    overduecharges => $overduecharges,
    dropboxmode => $dropboxmode,
    dropboxdate	=> $dropboxdate->output(),
    AllowRenewalLimitOverride => C4::Context->preference("AllowRenewalLimitOverride"),
    DHTMLcalendar_dateformat=>C4::Dates->DHTMLcalendar(),
    stickyduedate => $stickyduedate,
    messages => \@messages,
    sounderror => $sounderror,
    soundok => $soundok,
    riloop => \@riloop,
    );

# set return date if stickyduedate
if ( $stickyduedate && ! $input->param( 'stickyduedate' ) ) {
    $session->clear( 'stickyduedate' );
    $template->param(
	stickyduedate => '',
	duedatespec => '',
	);
} elsif ($stickyduedate) {
    $session->param( 'stickyduedate', $duedatespec );
    $template->param(
        newduedate => $duedatespec,
    );
}

output_html_with_http_headers $input, $cookie, $template->output;
