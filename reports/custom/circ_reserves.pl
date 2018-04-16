#!/usr/bin/perl

# Copyright 2009 Michael Hafen
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

# Report template created by Michael Hafen (mdhafen@tech.washk12.org) for WCSD
# This is designed for Koha3
# This is designed to use a single template file for any report created with it.

use strict;
use CGI;
use C4::Auth;
use C4::Context;
use C4::Output;
use C4::Branch;  # GetBranches GetBranchInfo
use C4::Members;  # GetMemberSortValues
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

my $reportname = "circ_reserves";
my $reporttitle = "Titles on Hold";
my @column_titles = ( "Patron", "Patron Branch", "Title", "Call Number(s)", "Date Placed", "Priority", "Copies Available" );

#FIXME build queryfilter
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");
my @queryfilter = ();
my $branch;
my $where = "( found <> 'F' OR found IS NULL )";

if ( C4::Context->preference("IndependantBranches") || $filters[0] ) {
    my $hbranch = 'reserves.branchcode';
    $branch = ( C4::Context->preference("IndependantBranches") ) ? C4::Context->userenv->{branch} : $filters[0];
    push @queryfilter, { title => "School", op => "=", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
    $where .= " AND $hbranch = ". $dbh->quote($branch);
}

my $query = "SELECT CONCAT( borrowers.surname, ', ', borrowers.firstname ) AS borrower, branchname, CONCAT_WS(' ', biblio.title, biblio.remainderoftitle ) AS title, GROUP_CONCAT( DISTINCT itemcallnumber SEPARATOR ',' ) AS callnumbers, MIN(reservedate) AS reservedate, MIN(priority) AS priority, ( SELECT COUNT(*) FROM items WHERE biblionumber = reserves.biblionumber AND items.onloan IS NULL". ( $branch ? " AND homebranch = ". $dbh->quote($branch) : "" ) ." AND COALESCE(items.itemlost,0) = 0 AND COALESCE(items.restricted,0) = 0 AND COALESCE(items.wthdrawn,0) = 0 ) AS available, reserves.biblionumber FROM reserves CROSS JOIN borrowers USING (borrowernumber) CROSS JOIN biblio USING (biblionumber) CROSS JOIN biblioitems USING (biblionumber) CROSS JOIN branches ON borrowers.branchcode = branches.branchcode LEFT JOIN items ON reserves.biblionumber = items.biblionumber". ( $branch ? " AND homebranch = ". $dbh->quote($branch) : "" ) ." WHERE $where";

my $group = "reserves.biblionumber,reserves.borrowernumber";
my $order = "title";

for ( $filters[0] ) {
    if ( /title/i ) { $order = "title,priority" }
    if ( /borrower/i ) { $order = "borrower,title" }
    if ( /date/i ) { $order = "reservedate DESC,title,priority" }
}

$query .= " GROUP BY $group ORDER BY $order";

# Rest of params
my $do_it=$input->param('do_it');
my $output = $input->param("output");
# rfc822 references 65 characters as limit for body of header fields
# substr here is to prevent header overflow attacks against browsers
my $basename = substr( $input->param("basename"), 0, 65 );
my $sep = $input->param( "sep" );
#my $mime = $input->param("MIME");
my $mime = 'application/vnd.sun.xml.calc';  # There is really only one option

my $userenv = C4::Context->userenv;

$template->param(
		 do_it => $do_it,
		 reportname => $reportname,
		 reporttitle => $reporttitle,
		 );

if ($do_it) {
	my $results = calculate( $query, \@column_titles );
    $results->[0]{'loopfilter'} = \@queryfilter if ( @queryfilter );
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
	# FIXME  Fill in other dropdowns

	my @parameters;


	my @order_loop;
	push @order_loop, { value => 'title', label => 'Title' };
	push @order_loop, { value => 'borrower', label => 'Patron' };
	push @order_loop, { value => "date", label => 'Date Placed' };
	push @parameters, {
	    select_box => 1,
	    select_loop => \@order_loop,
	    label => 'Sort By',
	};

	unless ( C4::Context->preference("IndependantBranches") ) {
	    my $branches = GetBranches();
	    my @branchloop;
	    my $branchfilter = C4::Context->userenv->{'branch'};

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
	    parameter_loop => \@parameters,
	    sep_loop => \@dels,
	    );

	output_html_with_http_headers $input, $cookie, $template->output;
}

sub calculate {
	my ( $query, $column_titles ) = @_;

	my $dbh = C4::Context->dbh;
	my @looprow;
	my @loopheader;
	my %globalline;
	my @mainloop;
	my $grantotal = 0;

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

CALC_MAIN_LOOP:
	while ( my ( @values ) = $sth_col->fetchrow ) {
	    my %row;
	    my @mapped_values;

	    foreach ( @values[ 0 .. $#$column_titles ] ) {
		push @mapped_values, { value => $_ };
	    }
	    $mapped_values[4]{value} = C4::Dates->new( $values[4], 'iso' )->output();
	    $mapped_values[2]{link} = "/cgi-bin/koha/reserve/request.pl?biblionumber=". $values[6];
	    $row{ 'values' } = \@mapped_values;
	    push @looprow, \%row;
	    $grantotal++;
	}

	foreach ( @$column_titles ) {
	    push @{ $loopheader[0]->{ 'values' } }, { 'coltitle' => $_ };
	}

	# the header of the table
	$globalline{loopheader} = \@loopheader;

	# FIXME comment out these seven lines to remove the total row
	# the foot (totals)
#	push @looprow, {
#			 'values' => [
#				       {
#					   'width' => @$column_titles - 1,
#					   'value' => '&nbsp;',
#					   'header' => 1,
#				       },
#				       {
#					   'value' => $grantotal,
#					   'header' => 1,
#				       }
#				     ]
#		       };

	# the core of the table
	$globalline{looprow} = \@looprow;

	push @mainloop, \%globalline;

	return \@mainloop;
}
