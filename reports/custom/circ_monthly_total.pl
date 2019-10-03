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

# Report template created by Michael Hafen (mdhafen@tech.washk12.org) for WCSD
# This is designed for Koha3
# This is designed to use a single template file for any report created with it.

use strict;
use CGI;
use POSIX; qw/strftime/;
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

my $reportname = "circ_monthly_total";
my $reporttitle = "Monthly Circulation Totals";
my @column_titles = ( "Month", "Circulations" );
my @queryfilter;

my @where;
my $columns = 'year(issuedate) AS year,month(issuedate) AS month,count(*) AS Checkouts';
my $group = 'month(issuedate),year(issuedate)';
my $order = 'year(issuedate) DESC, month(issuedate) DESC';

# Handle parameters
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");

if ( C4::Context->preference("IndependantBranches") || $filters[0] ) {
	my $branch = ( C4::Context->preference('IndependantBranches') ) ? $userenv->{branch} : $filters[0];
	my $hbranch = C4::Context->preference('HomeOrHoldingBranch') eq 'homebranch' ? 'items.homebranch' : 'items.holdingbranch';
	push @where, "$hbranch = ". $dbh->quote( $branch );
	push @queryfilter, { op => '=', title => 'School', value => GetBranchInfo( $branch )->[0]->{'branchname'} };
}

if ( $input->param("ItemTypes") ) {
	my @types_array = map $dbh->quote($_), $input->param("ItemTypes");
	push @where, "itype IN (". join( ',', @types_array ) .")";
	unshift @column_titles, 'Item Type';
	$columns = 'itemtypes.description AS itemtype,'. $columns;
	$group = 'itype,'. $group;
	$order = 'itype,'. $order;
	push @queryfilter, { op => "IN", title => "Item Type", value => join( ',', @types_array ) };
}

my $query = "SELECT $columns FROM (SELECT * FROM issues UNION SELECT * FROM old_issues) AS all_issues LEFT JOIN items USING (itemnumber) LEFT JOIN itemtypes ON (itype = itemtype)";
if ( @where ) {
	$query .= " WHERE ". join( ' AND ', @where );
}
$query .= " GROUP BY ". $group;
$query .= " ORDER BY ". $order;

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
	my $results = calculate( $query, \@column_titles, \@queryfilter );
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

	unless ( C4::Context->preference("IndependantBranches") ) {
		my $branches = GetBranches();
		my @branchloop;
		my $branchfilter = $userenv->{'branch'};

		foreach my $thisbranch ( sort keys %$branches ) {
			my %row = (
				value	 => $thisbranch,
				label	 => $branches->{$thisbranch}->{'branchname'},
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

	my $itemtypes = GetItemTypes;
	my @itemtypesloop;
	foreach my $thisitype ( sort keys %$itemtypes ){
		my %row = (
			   value => $thisitype,
			   label => $itemtypes->{$thisitype}->{description},
			   );
		push @itemtypesloop, \%row;
	}
	push @parameters, {
		select_box => 1,  # other options: checkbox, text, calendar
		select_loop => \@itemtypesloop,
		label => "Item Types",
		input_name => 'ItemTypes',
		first_blank => 1,
		size => 5,
		multiple => 1,
	};

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
	my ($query, $column_titles, $qfilters) = @_;

	my $dbh = C4::Context->dbh;
	my @loopheader;
	my @looprow;
	my %globalline;
	my @mainloop;

	my $date_index = ( $column_titles->[0] eq 'Item Type' ) ? 1 : 0;

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

CALC_MAIN_LOOP:
	while ( my ( @values ) = $sth_col->fetchrow ) {
		my %row;
		my @mapped_values;

		my $date = strftime qq(%b %Y), 1, 1, 1, 1, $values[$date_index+1] - 1, $values[$date_index] - 1900;

		push @mapped_values,
			{ value => $date },
			{ value => $values[$date_index+2] };

		if ( $date_index ) {
			unshift @mapped_values, { value => $values[0] }
		}

		$row{ 'values' } = \@mapped_values;
		push @looprow, \%row;
	}

	foreach ( @$column_titles ) {
		push @{ $loopheader[0]->{ 'values' } }, { 'coltitle' => $_ };
	}

	# the filters used
	$globalline{loopfilter} = $qfilters;

	# the header of the table
	$globalline{loopheader} = \@loopheader;

	# the core of the table
	$globalline{looprow} = \@looprow;

	push @mainloop, \%globalline;

	return \@mainloop;
}
