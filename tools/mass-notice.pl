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
use C4::Koha;  # GetItemTypes
use C4::Branch;  # GetBranches GetBranchDetail
use C4::Dates qw/format_date/;
use C4::Letters;
use C4::Category;
use C4::Members qw/GetMember GetMemberSortValues/;

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
my $sort     = $cgi->param( 'sort_select' );
my $sort1    = $cgi->param( 'sort1_filter' );
my $sort2    = $cgi->param( 'sort2_filter' );
my $itype    = $cgi->param( 'itype_filter' );
my $category = $cgi->param( 'category' );
my $send_to  = $cgi->param( 'send_to' );
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

        # items.content below assumes date_due is first field
        my @issue_columns = qw/date_due barcode title author replacementprice/;
        $query = "
     SELECT date_due, barcode, title, author, replacementprice, TO_DAYS(date_due)-TO_DAYS(NOW()) AS days_to_due
       FROM issues
 CROSS JOIN items USING (itemnumber)
 CROSS JOIN biblio USING (biblionumber)
      WHERE issues.borrowernumber = ?";
        my $issues_sth = $dbh->prepare( $query );

        foreach my $borrowernumber ( @patrons ) {
            my $borrower = GetMember('borrowernumber' => $borrowernumber);
            my $to_address = '';
            if ( $send_to eq 'home' ) {
                $to_address = $borrower->{'email'};
            } elsif ( $send_to eq 'work' ) {
                $to_address = $borrower->{'emailpro'};
            } elsif ( $send_to eq 'both' ) {
                $to_address = join ',', grep( {$_} $borrower->{'email'},$borrower->{'emailpro'} );
            }
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
            my $items_content = '';
            $issues_sth->execute( $borrowernumber );
            while ( my $issue = $issues_sth->fetchrow_hashref() ) {
                my @item_info = map { $_ =~ /^date|date$/ ? format_date($issue->{$_}) : $issue->{$_} || '' } @issue_columns;
                if ( $issue->{'days_to_due'} < 0 ) {
                    $overdue_content .= join("\t", @item_info) ."\n";
                    $item_info[0] .= " (overdue!)";
                }
                $items_content .= join("\t", @item_info) ."\n";
            }
            $overdue_content = join("\t", @issue_columns) ."\n" . $overdue_content if ($overdue_content);
            $items_content = join("\t", @issue_columns) ."\n" . $items_content if ($items_content);

            $this_letter = C4::Letters::parseletter( $this_letter, 'borrowers', $borrowernumber );
            $this_letter = C4::Letters::parseletter( $this_letter, 'branches', $branch );
            $this_letter->{content} =~ s/<<fines\.content>>/$fines_content/g;
            $this_letter->{content} =~ s/<<overdue\.content>>/$overdue_content/g;
            $this_letter->{content} =~ s/<<items\.content>>/$items_content/g;

            C4::Letters::EnqueueLetter({
                letter => $this_letter,
                borrowernumber => $borrowernumber,
                message_transport_type => 'email',
                from_address => $admin_email_address,
                to_address => $to_address,
            });
            $count++;
        }
    }

    $template->param(
        $op => 1,
        op => $op,
        emails_sent => $count,
        );

}
elsif ( $op eq 'Search' ) {
    my @bind;
    my $account_select = "SELECT SUM(amountoutstanding) FROM accountlines WHERE accountlines.borrowernumber = borrowers.borrowernumber";
    my $overdues_select = "SELECT count(*) FROM issues WHERE issues.borrowernumber = borrowers.borrowernumber AND TO_DAYS(NOW()) - TO_DAYS(date_due) > 0";
    my $having = "account > 0 OR overdues > 0";
    my $order = 'surname,firstname';

    if ( $select eq 'overdue' ) {
        $overdues_select = "SELECT count(*) FROM issues WHERE issues.borrowernumber = borrowers.borrowernumber AND TO_DAYS(NOW()) - TO_DAYS(date_due) > 0";
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
    elsif ( $select eq 'fines' ) {
        $having = "account > 0";
    }
    elsif ( $select eq 'issues' ) {
        $overdues_select = "SELECT count(*) FROM issues WHERE issues.borrowernumber = borrowers.borrowernumber";
        $having = "overdues > 0";
    }
    elsif ( $select eq 'issues_or_fines' ) {
        $overdues_select = "SELECT count(*) FROM issues WHERE issues.borrowernumber = borrowers.borrowernumber";
    }

    # No-Op for ""
    if ( $sort eq 'sort1' ) {
        $order = 'sort1,surname,firstname';
    }
    elsif ( $sort eq 'sort2' ) {
        $order = 'sort2,surname,firstname';
    }
    elsif ( $sort eq 'sort12' ) {
        $order = 'sort1,sort2,surname,firstname';
    }

    $query = "
     SELECT borrowernumber, surname, firstname, sort1, sort2,
            ( $account_select ) AS account,
            ( $overdues_select ) AS overdues
       FROM borrowers ";

    my @wheres;
    if ( $branch ) {
        push @wheres, "borrowers.branchcode = ?";
        push @bind, $branch;
    }
    if ( $category ) {
        push @wheres, "borrowers.categorycode = ?";
        push @bind, $category;
    }
    if ( $sort1 ) {
        push @wheres, "borrowers.sort1 = ?";
        push @bind, $sort1;
    }
    if ( $sort2 ) {
        push @wheres, "borrowers.sort2 = ?";
        push @bind, $sort2;
    }
    if ( $itype ) {
        push @wheres, "items.itype = ?";
        push @bind, $itype;
    }
    if ( @wheres ) {
        $query .= 'WHERE '. ( join ' AND ',@wheres );
    }

    $query .= "
   GROUP BY borrowers.borrowernumber
     HAVING $having
   ORDER BY $order";

    my $sth = $dbh->prepare( $query );
    $sth->execute(@bind);
    while ( my $row = $sth->fetchrow_hashref() ) {
        $row->{'account'} = sprintf( "%.2f", $row->{'account'} );
        push @patron_list, $row;
    }

    $template->param(
        $op => 1,
        op => $op,
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

my ( $sort1_values, $sort2_values ) = GetMemberSortValues();
my ( @sort1_loop, @sort2_loop );
foreach ( sort @$sort1_values ) {
    push @sort1_loop, { value => $_, label => $_ } if ( $_ );
}
foreach ( sort @$sort2_values ) {
    push @sort2_loop, { value => $_, label => $_ } if ( $_ );
}

my $itemtypes = GetItemTypes();
my @itemtype_loop;
foreach my $thisitype ( sort keys %$itemtypes ) {
    my %row = (
        value => $thisitype,
        label => $$itemtypes{ $thisitype }{'description'},
    );
    push @itemtype_loop, \%row;
}

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
    'send_to' => $send_to,
    'branchLOOP' => \@branchLoop,
    'category_loop' => \@categories,
    'sort1_loop' => \@sort1_loop,
    'sort2_loop' => \@sort2_loop,
    'itype_loop' => \@itemtype_loop,
    'circ_letter_loop' => \@circ_letters,
    'fine_letter_loop' => \@fine_letters,
    'patron_list' => \@patron_list,
    );

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
