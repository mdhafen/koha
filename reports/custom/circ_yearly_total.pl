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

my $reportname = "circ_yearly_total";
my $reporttitle = "Yearly Circulation Totals";
my @column_titles = ( "School Year", "Item Type", "Circulations" );

my $where = 'issuedate IS NOT NULL';

# Handle parameters
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");

if ( C4::Context->preference("IndependantBranches") || $filters[0] ) {
    my $branch = ( C4::Context->preference('IndependantBranches') ) ? $userenv->{branch} : $filters[0];
    my $hbranch = C4::Context->preference('HomeOrHoldingBranch') eq 'homebranch' ? 'items.homebranch' : 'items.holdingbranch';
    $where = "$hbranch = ". $dbh->quote( $branch );
}

my $query = "SELECT all_issues.iss_date,all_issues.itype FROM (
  SELECT issues.issuedate AS iss_date,items.itype AS itype
    FROM issues LEFT JOIN items ON (items.itemnumber = issues.itemnumber)
   WHERE $where
UNION ALL
  SELECT old_issues.issuedate AS iss_date,items.itype AS itype
    FROM old_issues LEFT JOIN items ON (items.itemnumber = old_issues.itemnumber)
   WHERE $where
) AS all_issues ORDER BY (all_issues.iss_date)";

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
	# FIXME  Fill in other dropdowns

	my @parameters;

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

CALC_MAIN_LOOP:
	while ( my ( $date,$itype ) = $sth_col->fetchrow ) {
	    my $year;
	    # FIXME this needs to be updated every year.
	    for ( $date ) {
		if    ( $_ gt '2018-05-24' ) { $year = '2018-2019' }
		elsif ( $_ gt '2017-05-24' ) { $year = '2017-2018' }
		elsif ( $_ gt '2016-05-25' ) { $year = '2016-2017' }
		elsif ( $_ gt '2015-05-21' ) { $year = '2015-2016' }
		elsif ( $_ gt '2014-05-22' ) { $year = '2014-2015' }
		elsif ( $_ gt '2013-05-23' ) { $year = '2013-2014' }
		elsif ( $_ gt '2012-05-23' ) { $year = '2012-2013' }
		elsif ( $_ gt '2011-05-25' ) { $year = '2011-2012' }
		elsif ( $_ gt '2010-05-27' ) { $year = '2010-2011' }
		elsif ( $_ gt '2009-05-22' ) { $year = '2009-2010' }
	    }
	    if ( $year ) {
		$big_hash{ $year }{ $itype }++;
		$big_hash{ $year }{ '_total' }++;
	    }
	}

	foreach my $year ( reverse sort keys %big_hash ) {
	    my $year_hash = $big_hash{ $year };
	    foreach my $type ( sort keys %$year_hash ) {
		my %row;
		my @mapped_values;

		push @mapped_values,
		    { value => $year },
		    { value => ( $type eq '_total' ) ? 'Total' : $itemtypes->{$type}{'description'} },
		    { value => $year_hash->{ $type } };

		if ( $type eq '_total' ) {
		    foreach ( @mapped_values ) { $_->{'header'} = 1 };
		}

		$row{ 'values' } = \@mapped_values;
		push @looprow, \%row;
	    }
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
