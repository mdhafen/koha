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
#   Written by Michael Hafen mdhafen@tech.washk12.org on Oct. 2016


=head1 mass-notice.pl

Tool to send a notice like message to a group of patrons.

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
$CGI::LIST_CONTEXT_WARN=0;

# getting the template
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "tools/mass-notice.tmpl",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { tools => 1 },
    }
);

my $dbh = C4::Context->dbh;
my $op       = $cgi->param( 'op' ) || '';
my $branch   = $cgi->param( 'branch' );
my $subject  = $cgi->param( 'message-subject' );
my $body     = $cgi->param( 'message-body' );
my $select   = $cgi->param( 'patron_select' );
my $category = $cgi->param( 'category' );
my @patrons  = $cgi->param( 'patrons' );

my $query;
my @patron_list;

if ( $op eq 'Send' ) {
    my $letter = {
        'module' => '',
        'code' => '',
        'name' => '',
        'title' => $subject,
        'content' => $body,
    };

    my $count = 0;
    my $branches = {};
    if ( $branch ) {
        $branches->{ $branch } = GetBranchDetail($branch);
    }
    else {
        $branches = GetBranches();
    }

    if ( $subject && $body ) {
        my @account_columns = qw/date amountoutstanding description barcode title/;
        $query = "
    SELECT date, amountoutstanding, description, barcode,
           IF( itemnumber <> 0, title, '' ) AS title
      FROM accountlines
 LEFT JOIN items USING (itemnumber)
 LEFT JOIN biblio USING (biblionumber)
     WHERE accountlines.borrowernumber = ?
       AND amountoutstanding <> 0";
        my $fines_sth = $dbh->prepare( $query );

        my @issue_columns = qw/date_due barcode title author/;
        $query = "
     SELECT date_due, barcode, title, author
       FROM issues
 CROSS JOIN items USING (itemnumber)
 CROSS JOIN biblio USING (biblionumber)
      WHERE issues.borrowernumber = ?
        AND TO_DAYS(NOW())-TO_DAYS(date_due) > 0";
        my $overdue_sth = $dbh->prepare( $query );

        foreach my $borrowernumber ( @patrons ) {
            my $this_letter = {};
            %$this_letter = %$letter;
            my $admin_email_address;
            my $branch_details = $branches->{$branch};
            $admin_email_address = $branch_details->{'branchemail'} || C4::Context->preference('KohaAdminEmailAddress');

            my $fines_content = '';
            $fines_sth->execute( $borrowernumber );
            while ( my $fine = $fines_sth->fetchrow_hashref() ) {
                my @line_info = map { $_ =~ /^date|date$/ ? format_date($fine->{$_}) : $fine->{$_} || '' } @account_columns;
                $fines_content .= join("\t", @line_info) ."\n";
            }

            my $overdue_content = '';
            $overdue_sth->execute( $borrowernumber );
            while ( my $issue = $overdue_sth->fetchrow_hashref() ) {
                my @item_info = map { $_ =~ /^date|date$/ ? format_date($issue->{$_}) : $issue->{$_} || '' } @issue_columns;
                $overdue_content .= join("\t", @item_info) ."\n";
            }

            $this_letter = C4::Letters::parseletter( $this_letter, 'borrowers', $borrowernumber );
            $this_letter = C4::Letters::parseletter( $this_letter, 'branches', $branch );
            $this_letter->{content} =~ s/<<fines\.content>>/$fines_content/g;
            $this_letter->{content} =~ s/<<overdue\.content>>/$overdue_content/g;
            $this_letter->{content} =~ s/<<items\.content>>/$overdue_content/g;

            C4::Letters::EnqueueLetter({
                letter => $this_letter,
                borrowernumber => $borrowernumber,
                message_transport_type => 'email',
                from_address => $admin_email_address,
            });
            $count++;
        }
    }

    $template->param(
        $op => 1,
        emails_sent => $count,
        );

}
elsif ( $op eq 'Search' ) {
    my @bind;
    my $account_select = "SELECT SUM(amountoutstanding) FROM accountlines WHERE accountlines.borrowernumber = borrowers.borrowernumber";
    my $overdues_select = "SELECT count(*) FROM issues WHERE issues.borrowernumber = borrowers.borrowernumber AND TO_DAYS(NOW()) - TO_DAYS(date_due) > 0";
    my $having = "account > 0 OR overdues > 0";

    if ( $select eq 'overdue_today' ) {
        $overdues_select = "SELECT count(*) FROM issues WHERE issues.borrowernumber = borrowers.borrowernumber AND TO_DAYS(NOW()) - TO_DAYS(date_due) = 1";
        $having = "overdues > 0";
    }
    elsif ( $select eq 'due_today' ) {
        $overdues_select = "SELECT count(*) FROM issues WHERE issues.borrowernumber = borrowers.borrowernumber AND TO_DAYS(NOW()) - TO_DAYS(date_due) = 0";
        $having = "overdues > 0";
    }
    elsif ( $select eq 'overdue_fines' ) {
        $account_select = "SELECT SUM(amountoutstanding) FROM accountlines WHERE accounttype IN ('F','FU') AND amountoutstanding > 0 AND accountlines.borrowernumber = borrowers.borrowernumber";
        $having = "account > 0";
    }

    $query = "
     SELECT borrowernumber, surname, firstname, sort2, categories.description,
            ( $account_select ) AS account,
            ( $overdues_select ) AS overdues
       FROM borrowers
 CROSS JOIN categories USING (categorycode)";

    if ( $branch || $category ) {
        $query .= " WHERE ";
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
   GROUP BY borrowers.borrowernumber
     HAVING $having";

    my $sth = $dbh->prepare( $query );
    $sth->execute(@bind);
    while ( my $row = $sth->fetchrow_hashref() ) {
        $row->{'account'} = sprintf( "%.2f", $row->{'account'} );
        push @patron_list, $row;
    }

    $template->param(
        $op => 1,
        branch => $branch,
        message_subject => $subject,
        message_body => $body,
        );
}

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
 SELECT module, code, name, title, content
   FROM letter
  WHERE module in ('circulation','accounts')
";

my $sth = $dbh->prepare( $query );
$sth->execute();

while ( my ( $module,$code,$name,$title,$content ) = $sth->fetchrow_array ) {
    my $this_letter = {
        'value' => $code,
        'label' => $name,
        'subject' => $title,
        'content' => $content
    };
    if ( $module eq 'circulation' ) {
        push @circ_letters, $this_letter;
    }
    elsif ( $module eq 'accounts' ) {
        push @fine_letters, $this_letter;
    }
}

$template->param(
    'branchLOOP' => \@branchLoop,
    'category_loop' => \@categories,
    'circ_letter_loop' => \@circ_letters,
    'fine_letter_loop' => \@fine_letters,
    'patron_list' => \@patron_list,
    );

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
