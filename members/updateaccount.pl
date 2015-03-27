#!/usr/bin/perl

#written 2009-03-30 by mdhafen@tech.washk12.org
#page to update information of an account line.

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
use C4::Auth;
use C4::Output;
use C4::Members;
use C4::Accounts;
use C4::Items;
use C4::Branch;

my $input = new CGI;

my ($template, $loggedinuser, $cookie)
    = get_template_and_user({template_name => "members/updateaccount.tmpl",
                             query => $input,
                             type => "intranet",
                             authnotrequired => 0,
                             flagsrequired => { updatecharges => 'edit_lines' },
                             debug => 1,
                            });

my $borrowernumber = $input->param('borrowernumber');
my $accountno = $input->param('accountnumber');

unless ( C4::Context->preference('AccountLinesEditable') ) {
    print $input->redirect( "/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber" );
    exit;
}

unless ( $borrowernumber && $accountno ) {
    #  FIXME should check if $borrowernumber is set before this.
    print $input->redirect( "/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber" );
    exit;
}

my $op = $input->param('button');
my $result = 0;
my ( $desc, $type, $amount, $outstanding ) = ( '', '', 0, 0 );
my $borr = GetMember( 'borrowernumber' => $borrowernumber );

if ( $op ) {
    $desc = $input->param('description');
    $type = $input->param('type');
    $amount = $input->param('amount');
    $outstanding = $input->param('outstanding');

    if ( $op eq 'Delete' ) {
        $result = deleteline( $borrowernumber, $accountno );
        if ( $result ) {
            print $input->redirect( "/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber" );
            exit;
        }
    } elsif ( $desc || $type || $amount || $outstanding ) {
        $result = updateline( $borrowernumber, $accountno, $desc, $amount, $outstanding, $type );
	if ( $result ) {
            print $input->redirect( "/cgi-bin/koha/members/boraccount.pl?borrowernumber=$borrowernumber" );
	}
    }
} else {
    my ( $charge ) = getcharges( $borrowernumber, undef, $accountno );
    $desc = $$charge{ 'description' };
    $type = $$charge{ 'type' };
    $amount = sprintf '%.02f', $$charge{ 'amount' };
    $outstanding = sprintf '%.02f', $$charge{ 'amountoutstanding' };
}

$template->param(
    op => $op,
    borrowernumber => $borrowernumber,
    accountnumber => $accountno,
    description => $desc,
    type => $type,
    amount => $amount,
    outstanding => $outstanding,
    error => !$result,
    );

# Borrower information for template
if ( $borr->{'category_type'} eq 'C') {
    my  ( $catcodes, $labels ) =  GetborCatFromCatType( 'A', 'WHERE category_type = ?' );
    my $cnt = scalar(@$catcodes);
    $template->param( 'CATCODE_MULTI' => 1) if $cnt > 1;
    $template->param( 'catcode' => $catcodes->[0] ) if $cnt == 1;
}

$template->param( adultborrower => 1 ) if ( $borr->{'category_type'} eq 'A' );
my ($picture, $dberror) = GetPatronImage($borr->{'cardnumber'});
$template->param( picture => 1 ) if $picture;
$template->param(
    finesview => 1,
    firstname => $borr->{'firstname'},
    surname  => $borr->{'surname'},
    cardnumber => $borr->{'cardnumber'},
    categorycode => $borr->{'categorycode'},
    category_type => $borr->{'category_type'},
    categoryname  => $borr->{'description'},
    address => $borr->{'address'},
    address2 => $borr->{'address2'},
    city => $borr->{'city'},
    zipcode => $borr->{'zipcode'},
    phone => $borr->{'phone'},
    email => $borr->{'email'},
    branchcode => $borr->{'branchcode'},
    branchname => GetBranchName($borr->{'branchcode'}),
    is_child        => ($borr->{'category_type'} eq 'C'),
    );

output_html_with_http_headers $input, $cookie, $template->output;
