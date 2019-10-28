#!/usr/bin/perl

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

# Report template created by Michael Hafen (michael.hafen@washk12.org) for WCSD
# This is designed for Koha3
# This is designed to use a single template file for any report created with it.

use strict;
use CGI;
use C4::Auth;
use C4::Context;
use C4::Output;
use C4::Dates qw/format_date format_date_in_iso/;
use C4::Branch;  # GetBranches GetBranchInfo
use C4::Koha;
use C4::Circulation;

# Watch out for:
#  C4::Context->preference("IndependantBranches")

my $input = new CGI;
my $dbh = C4::Context->dbh;

my ($template, $borrowernumber, $cookie)
	= get_template_and_user({template_name => "reports/custom_report.tmpl",
				query => $input,
				type => "intranet",
				authnotrequired => 0,
				flagsrequired => {reports => 1},
				debug => 0,
				});

my $userenv = C4::Context->userenv;

my $reportname = "circ_all_issues";
my $reporttitle = "All Checkouts";
my @column_titles = ( "Checkout Date", "Number of Renewals", "Date Returned", "Date Due", "Homeroom Teacher", "Borrower", "Borrowers School", "Title", "Call Number", "Barcode", "Replacement Price", "Copy notes" );

my (@wheres_i_i,@wheres_i_o,@wheres_o);

# Handle parameters
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");

if ( $filters[0] ) {
    my $date = $dbh->quote(format_date_in_iso($filters[0]));
    push @wheres_i_i, "issuedate > $date";
    push @wheres_i_o, "issuedate > $date";
}
if ( $filters[1] ) {
    my $date = $dbh->quote(format_date_in_iso($filters[1]));
    push @wheres_i_i, "issuedate < $date";
    push @wheres_i_o, "issuedate < $date";
}

if ( C4::Context->preference("IndependantBranches") || $filters[2] ) {
    my $branch = ( C4::Context->preference('IndependantBranches') ) ? $userenv->{branch} : $filters[2];
    my $branch = $dbh->quote( $branch );
    push @wheres_i_i, "branchcode = $branch";
    push @wheres_i_o, "branchcode = $branch";
}

my $query = "SELECT issuedate, COALESCE(all_issues.renewals,0) AS renewals, COALESCE(returndate,'') AS returndate, date_due, borrowers.sort2, CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron, branches.branchname, CONCAT_WS(' ',biblio.title,biblio.seriestitle) AS title, items.itemcallnumber, items.barcode, items.replacementprice, COALESCE(items.itemnotes,'') AS itemnotes, borrowernumber, biblionumber, itemnumber FROM (SELECT issuedate,renewals,returndate,date_due,borrowernumber,itemnumber FROM issues". ( @wheres_i_i ? " WHERE ". join(' AND ', @wheres_i_i ) : "" ) ." UNION ALL SELECT issuedate,renewals,returndate,date_due,borrowernumber,itemnumber FROM old_issues". ( @wheres_i_o ? " WHERE ". join(' AND ', @wheres_i_o ) : "" ) .") AS all_issues LEFT JOIN borrowers USING (borrowernumber) LEFT JOIN items USING (itemnumber) LEFT JOIN biblio USING (biblionumber) LEFT JOIN branches ON borrowers.branchcode = branches.branchcode";
if ( @wheres_o ) {
    $query .= ' WHERE '. (join ' AND ', @wheres_o);
}
$query .= " ORDER BY issuedate,patron";

# Rest of params
my $do_it=$input->param('do_it');
my $output = $input->param("output");
# rfc822 references 65 characters as limit for body of header fields
# substr here is to prevent header overflow attacks against browsers
my $basename = substr( $input->param("basename"), 0, 65 );
my $sep = $input->param( "sep" );
#my $mime = $input->param("MIME");
my $mime = 'application/vnd.sun.xml.calc';  # There is really only one option

$template->param(
		 do_it => $do_it,
		 reportname => $reportname,
		 reporttitle => $reporttitle,
		 );

if ($do_it) {
	my $results = calculate( $query, \@column_titles );
	if ($output eq "screen"){
		$template->param(mainloop => $results);
		output_html_with_http_headers $input, $cookie, $template->output;
	} else {
		my $filename = "$basename.csv";
		$filename = "$basename.tsv" if ( $sep =~ m/tab/ );
		print $input->header(-type => $mime,
					 -attachment=>"$filename",
					 -name=>"$filename" );
		my @headers = @{ $$results[0]->{loopheader} };
		my @lines = @{ $$results[0]->{looprow} };
		for ( $sep ) {
			if    ( m/tab/ ) { $sep = "\t"; }
			elsif ( m/\\/  ) { $sep = "\\"; }
			elsif ( m/\//  ) { $sep = "\/"; }
			elsif ( m/,/   ) { $sep = ",";  }
			elsif ( m/\#/  ) { $sep = "#";  }
			else             { $sep = ";";  }
		}

		foreach my $line ( @headers ) {
			foreach my $cell ( @{ $line->{values} } ) {
				print $$cell{coltitle}.$sep;
				print $sep x ( $$cell{width} - 1 ) if ( $$cell{width} );
			}
			print "\n";
		}
		foreach my $line ( @lines ) {
			foreach my $cell ( @{ $line->{values} } ) {
				print $$cell{value}.$sep;
				print $sep x ( $$cell{width} - 1 ) if ( $$cell{width} );
			}
			print "\n";
		}
	}
} else {
	my @parameters;

	my @datearr = localtime(time());
	my ( $year, $month, $day ) = ( ( 1900 + $datearr[5] ), ( $datearr[4] + 1 ), $datearr[3] );
	$year--;
	if ( $month == 2 && $day == 29 ) {
	    $day--;
	}
	my $datefrom = format_date( $year.'-'.sprintf("%0.2d", $month).'-'.sprintf("%0.2d", $day) );

	push @parameters, {
	    calendar => 1,
	    label => "Checked out between",
	    id => "startdate",
	    value => $datefrom,
	};
	my $today = C4::Dates->today();
	push @parameters, {
	    calendar => 1,
	    label => "and",
	    id => "enddate",
	    value => $today,
	};

	unless ( C4::Context->preference("IndependantBranches") ) {
	    my $branches = GetBranches();
	    my @branchloop;
	    my $branchfilter = $userenv->{'branch'};

	    foreach my $thisbranch ( sort keys %$branches ) {
		my %row = (
		    value    => $thisbranch,
		    label    => $branches->{$thisbranch}->{'branchname'},
		    selected => ( $branches->{$thisbranch}->{'branchcode'} eq $branchfilter ),
		    );
		push @branchloop, \%row;
	    }
	    push @parameters, {
		select_box => 1,
		select_loop => \@branchloop,
		label => "Library",
		first_blank => 1,
	    };
	}

	my @dels = ( ";", "tabulation", "\\", "\/", ",", "\#" );
	foreach my $limiter ( @dels ) {
	    my $selected = ( $limiter eq C4::Context->preference("delimiter") );
	    $limiter = { value => $limiter, selected => $selected };
	}

	$template->param(
	    DHTMLcalendar_dateformat => C4::Dates->DHTMLcalendar(),
	    parameter_loop => \@parameters,
	    sep_loop => \@dels,
	    );

	output_html_with_http_headers $input, $cookie, $template->output;
}

sub calculate {
	my ($query, $column_titles) = @_;

	my $dbh = C4::Context->dbh;
	my $itemtypes = GetItemTypes();
	my @loopheader;
	my @looprow;
	my %globalline;
	my @mainloop;
	my %big_hash;

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

	while ( my ( @values ) = $sth_col->fetchrow ) {
		my %row;
		my @mapped_values;

		push @mapped_values, (
		    { value => $values[0] }, # Date format?
		    { value => $values[1] },
		    { value => $values[2] },
		    { value => $values[3] },
		    { value => $values[4] },
		    { value => $values[5], link => "/cgi-bin/koha/members/moremember.pl?borrowernumber=".$values[12] },
		    { value => $values[6] },
		    { value => $values[7], link => "/cgi-bin/koha/catalogue/detail.pl?biblionumber=".$values[13] },
		    { value => $values[8] },
		    { value => $values[9], link => "/cgi-bin/koha/catalogue/moredetail.pl?biblionumber=".$values[13]."&amp;itemnumber=".$values[14]."#item".$values[14] },
		    { value => $values[10] },
		    { value => $values[11] },
        );

		$row{ 'values' } = \@mapped_values;
		push @looprow, \%row;
	}

	foreach ( @$column_titles ) {
	    push @{ $loopheader[0]->{ 'values' } }, { 'coltitle' => $_ };
	}

	# the header of the table
	$globalline{loopheader} = \@loopheader;

	# the core of the table
	$globalline{looprow} = \@looprow;

	push @mainloop, \%globalline;

	return \@mainloop;
}
