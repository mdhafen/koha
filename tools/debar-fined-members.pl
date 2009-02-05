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
#   Written by Michael Hafen mdhafen@tech.washk12.org on Jan. 2009


=head1 debar-fined-members.pl

Tool to mark members debarred who have more then some amount of fines.

=cut

use strict;
use warnings;
use CGI;
use C4::Auth;
use C4::Output;
use C4::Branch;  # GetBranches
use C4::Members;  # ModMember GetMemberIssuesAndFines

my $cgi = new CGI;

# getting the template
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "tools/debar-fined-members.tmpl",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { management => 1, tools => 1 },
    }
);

my $dbh = C4::Context->dbh;
my $op     = $cgi->param( 'op' ) || '';
my $branch = $cgi->param( 'branch' );
my $amount = $cgi->param( 'amount' );
my $rebar  = $cgi->param( 'rebar' );

if ( $op eq 'Debar' ) {
    my $count = 0;
    my @bind = ( $amount );
    my $query = "
     SELECT accountlines.borrowernumber
       FROM accountlines
 CROSS JOIN borrowers USING ( borrowernumber )";
    if ( $branch ) {
        $query .= "
      WHERE borrowers.branchcode = ?";
        unshift @bind, $branch;
    }
    $query .= "
   GROUP BY accountlines.borrowernumber
     HAVING SUM(amountoutstanding) >= ?";

    my $sth = $dbh->prepare( $query );
    $sth->execute( @bind );

    while ( my ( $borrnum ) = $sth->fetchrow_array ) {
        my %work = ( 'debarred' => 1, 'borrowernumber' => $borrnum );
        ModMember( %work );
        $count++;
    }

    $template->param(
        op => $op,
        debarred => $count,
        );

    if ( $rebar ) {
	my $recount = 0;
	my @bind = ( $amount );
	my $query = "
     SELECT accountlines.borrowernumber
       FROM accountlines
 CROSS JOIN borrowers USING ( borrowernumber )
      WHERE borrowers.debarred > 0";
	if ( $branch ) {
	    $query .= "
        AND borrowers.branchcode = ?";
	    unshift @bind, $branch;
	}
	$query .= "
   GROUP BY accountlines.borrowernumber
     HAVING SUM(amountoutstanding) < ?";

	my $sth = $dbh->prepare( $query );
	$sth->execute( @bind );

	while ( my ( $borrnum ) = $sth->fetchrow_array ) {
	    my %work = ( 'debarred' => 0, 'borrowernumber' => $borrnum );
	    ModMember( %work );
	    $recount++;
	}

	$template->param(
	    rebarred => $recount,
	    );
    }
}

#get Branches
my @branches;
my @branchLoop = ();

my $onlymine=(C4::Context->preference('IndependantBranches') &&
              C4::Context->userenv &&
              C4::Context->userenv->{flags} !=1  &&
              C4::Context->userenv->{branch}?1:0);

my $branches = GetBranches( $onlymine );

foreach my $this_branch ( sort keys %$branches ) {
    my %branchRow;
    $branchRow{ 'selected' } = (
        C4::Context->userenv &&
        C4::Context->userenv->{'branch'} eq $this_branch
        );
    $branchRow{ 'label' } = $branches->{$this_branch}->{'branchname'};
    $branchRow{ 'value' } = $this_branch;
    push @branchLoop, \%branchRow;
}

$template->param(
    'branchLOOP' => \@branchLoop,
    );

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
