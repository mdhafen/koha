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
#   Written by Michael Hafen mdhafen@tech.washk12.org on Jan. 2014


=head1 trigger-overdue-fine-notices.pl

Tool to trigger notices for overdues or fines.

=cut

use strict;
use warnings;
use CGI;
use C4::Auth;
use C4::Output;
use C4::Branch;  # GetBranches GetBranchDetail
use C4::Dates qw/format_date/;
use C4::Letters;
use C4::Category;

my $cgi = new CGI;

# getting the template
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "tools/trigger-overdue-fine-notices.tmpl",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { management => 1, tools => 1 },
    }
);

my $dbh = C4::Context->dbh;
my $op        = $cgi->param( 'op' ) || '';
my $branch    = $cgi->param( 'branch' );
my $category  = $cgi->param( 'category' );
my $module    = $cgi->param( 'module' );
my $circ_code = $cgi->param( 'circ-code' );
my $fine_code = $cgi->param( 'fine-code' );

if ( $op eq 'Trigger' ) {
    my $letter;
    my $count = 0;
    my $branches = {};
    if ( $branch ) {
        $branches->{ $branch } = GetBranchDetail($branch);
    }
    else {
        $branches = GetBranches();
    }

    if ( $module eq 'accounts' ) {
        $letter = getletter( 'accounts', $fine_code );

        my @account_columns = qw/date amountoutstanding description barcode title/;
        my $query = "
    SELECT ". join(',',@account_columns[0..$#account_columns-1]) .",
           IF( accounttype IN ('C','W','Pay') AND itemnumber <> 0, title, '' ) AS title
      FROM accountlines
 LEFT JOIN items USING (itemnumber)
 LEFT JOIN biblio USING (biblionumber)
     WHERE accountlines.borrowernumber = ?
       AND amountoutstanding <> 0";
        my $fines_sth = $dbh->prepare( $query );

        my @bind = ();
        $query = "
     SELECT accountlines.*,borrowers.branchcode
       FROM accountlines
 CROSS JOIN borrowers USING ( borrowernumber )";
        if ( $branch || $category ) {
            $query .= "
      WHERE ";
            if ( $branch ) {
                $query .= "borrowers.branchcode = ?";
                push @bind, $branch;
                if ( $category ) {
                    $query .= " AND ";
                }
            }
            if ( $category ) {
                $query .= "borrowers.categorycode = ?";
                push @bind, $category;
            }
        }
        $query .= "
   GROUP BY accountlines.borrowernumber
     HAVING SUM(amountoutstanding) > 0";

        my $sth = $dbh->prepare( $query );
        $sth->execute( @bind );

        while ( my $row = $sth->fetchrow_hashref ) {
            my $this_letter = {};
            %$this_letter = %$letter;
            my $admin_email_address;
            $branch ||= $row->{'branchcode'};
            my $branch_details = $branches->{$branch};
            $admin_email_address = $branch_details->{'branchemail'} || C4::Context->preference('KohaAdminEmailAddress');

            my $fines_content = '';
            $fines_sth->execute( $row->{'borrowernumber'} );
            while ( my $fine = $fines_sth->fetchrow_hashref() ) {
                my @line_info = map { $_ =~ /^date|date$/ ? format_date($fine->{$_}) : $fine->{$_} || '' } @account_columns;
                $fines_content .= join("\t", @line_info) ."\n";
            }

            $this_letter = C4::Letters::parseletter( $this_letter, 'borrowers', $row->{'borrowernumber'} );
            $this_letter = C4::Letters::parseletter( $this_letter, 'branches', $branch );
            $this_letter->{title} =~ s/<<fines\.content>>/$fines_content/g;
            $this_letter->{content} =~ s/<<fines\.content>>/$fines_content/g;

            C4::Letters::EnqueueLetter({
                letter => $this_letter,
                borrowernumber => $row->{'borrowernumber'},
                message_transport_type => 'email',
                from_address => $admin_email_address,
            });
            $count++;
        }
    }
    elsif ( $module eq 'circulation' ) {
        $letter = getletter( 'circulation', $circ_code );

        my @issue_columns = qw/date_due barcode title author/;
        my $query = "
     SELECT ". join(',',@issue_columns) ."
       FROM issues
 CROSS JOIN items USING (itemnumber)
 CROSS JOIN biblio USING (biblionumber)
      WHERE issues.borrowernumber = ?
        AND TO_DAYS(NOW())-TO_DAYS(date_due) > 0";
        my $overdue_sth = $dbh->prepare( $query );

        my @bind = ();
        $query = "
     SELECT issues.*
       FROM issues
 CROSS JOIN borrowers USING (borrowernumber)";
        if ( $branch || $category ) {
            $query .= "
      WHERE ";
            if ( $branch ) {
                $query .= "issues.branchcode = ?";
                push @bind, $branch;
                if ( $category ) {
                    $query .= " AND ";
                }
            }
            if ( $category ) {
                $query .= "borrowers.categorycode = ?";
                push @bind, $category;
            }
        }
        $query .= "
   GROUP BY borrowernumber
     HAVING TO_DAYS(NOW())-TO_DAYS(date_due) > 0";

        my $sth = $dbh->prepare( $query );
        $sth->execute( @bind );

        while ( my $row = $sth->fetchrow_hashref ) {
            my $this_letter = {};
            %$this_letter = %$letter;
            my $items_content = '';
            my $admin_email_address;
            $branch ||= $row->{'branchcode'};
            my $branch_details = $branches->{$branch};
            $admin_email_address = $branch_details->{'branchemail'} || C4::Context->preference('KohaAdminEmailAddress');

            $overdue_sth->execute( $row->{'borrowernumber'} );
            while ( my $issue = $overdue_sth->fetchrow_hashref() ) {
                my @item_info = map { $_ =~ /^date|date$/ ? format_date($issue->{$_}) : $issue->{$_} || '' } @issue_columns;
                $items_content .= join("\t", @item_info) ."\n";
            }

            $this_letter = C4::Letters::parseletter( $this_letter, 'borrowers', $row->{'borrowernumber'} );
            $this_letter = C4::Letters::parseletter( $this_letter, 'branches', $branch );
            $this_letter->{title} =~ s/<<items\.content>>/$items_content/g;
            $this_letter->{content} =~ s/<<items\.content>>/$items_content/g;

            C4::Letters::EnqueueLetter({
                letter => $this_letter,
                borrowernumber => $row->{'borrowernumber'},
                message_transport_type => 'email',
                from_address => $admin_email_address,
            });
            $count++;
        }
    }

    $template->param(
        op => $op,
        emails_sent => $count,
        );

}

my $query;
my @branches;
my @branchLoop = ();
my @circ_letters = ();
my @fine_letters = ();

my $onlymine=(C4::Context->preference('IndependantBranches') &&
              C4::Context->userenv &&
              C4::Context->userenv->{flags} % 2 != 1  &&
              C4::Context->userenv->{branch}?1:0);

my $branches = GetBranches( $onlymine );

foreach my $this_branch ( sort {$branches->{$a}{'branchname'} cmp $branches->{$b}{'branchname'}} keys %$branches ) {
    my %branchRow;
    $branchRow{ 'selected' } = (
        C4::Context->userenv &&
        C4::Context->userenv->{'branch'} eq $this_branch
        );
    $branchRow{ 'label' } = $branches->{$this_branch}->{'branchname'};
    $branchRow{ 'value' } = $this_branch;
    push @branchLoop, \%branchRow;
}

my @categories = C4::Category->all;

$query = "
 SELECT module, code, name
   FROM letter
  WHERE module in ('circulation','accounts')
";

my $sth = $dbh->prepare( $query );
$sth->execute();

while ( my ( $module,$code,$name ) = $sth->fetchrow_array ) {
    if ( $module eq 'circulation' ) {
        push @circ_letters, { 'value' => $code, 'label' => $name };
    }
    elsif ( $module eq 'accounts' ) {
        push @fine_letters, { 'value' => $code, 'label' => $name };
    }
}

$template->param(
    'branchLOOP' => \@branchLoop,
    'category_loop' => \@categories,
    'circ_letter_loop' => \@circ_letters,
    'fine_letter_loop' => \@fine_letters,
    );

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
