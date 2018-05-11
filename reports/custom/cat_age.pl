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

my $reportname = "cat_age";
my $reporttitle = "Collection Age by Copyright Year";
my @column_titles = ( "Copyright Date", "Title", "Call Number", "Barcode", "circulations" );

#FIXME build queryfilter
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");
my @types_filter = $input->param( "ItemTypes" );
my @options = ( scalar $input->param("Option1") );
my @queryfilter = ();
my @where = ();

if ( $filters[0] ) {
    push @queryfilter, { op => "<", title => "Copyright Date", value => $filters[0] };
    push @where, "copyrightdate < ". $dbh->quote($filters[0]);
}

if ( @types_filter ) {
    push @queryfilter, { op => "=", title => "Item Type", value => join ',',@types_filter };
    push @where, "itype IN ( ". ( join( ',', map($dbh->quote($_),@types_filter) ) ) ." )";
}

if ( C4::Context->preference("IndependantBranches") || $filters[2] ) {
    my $hbranch = C4::Context->preference('HomeOrHoldingBranch') eq 'homebranch' ? 'i.homebranch' : 'i.holdingbranch';
    my $branch = ( C4::Context->preference("IndependantBranches") ) ? C4::Context->userenv->{branch} : $filters[2];
    push @queryfilter, { op => "=", title => "School", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
    push @where, "$hbranch = ". $dbh->quote( $branch );
}

my @loopfilter = ();

my $order = "copyrightdate,title,barcode";
my $group = "";
my $page_breaks;

$group = "biblionumber,i.biblioitemnumber" if ( $options[0] );

my $query = "SELECT copyrightdate, CONCAT_WS(' ', biblio.title, biblio.remainderoftitle ) AS title, itemcallnumber, barcode, COALESCE((SELECT COUNT(*) FROM old_issues WHERE itemnumber = i.itemnumber GROUP BY itemnumber),0) AS num_issues FROM items AS i CROSS JOIN biblio USING (biblionumber) CROSS JOIN biblioitems USING (biblionumber)";
if ( $group ) {
    $query = "SELECT copyrightdate, CONCAT_WS(' ',biblio.title, biblio.remainderoftitle ) AS title, GROUP_CONCAT(DISTINCT itemcallnumber) as itemcallnumber, GROUP_CONCAT(barcode) as barcode, COALESCE((SELECT COUNT(*) FROM old_issues left join items using (itemnumber) WHERE biblioitemnumber = i.biblioitemnumber GROUP BY biblioitemnumber),0) AS num_issues FROM items AS i CROSS JOIN biblio USING (biblionumber) CROSS JOIN biblioitems USING (biblionumber)";
}
if ( @where ) {
    $query .= " WHERE ". join ' AND ', @where;
}
if ( $group ) { $query .= " GROUP BY $group"; }
$query .= " ORDER BY $order";

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
	my $results = calculate( $query, \@column_titles, $page_breaks, \@queryfilter );
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

	my @datearr = localtime(time());
	my ( $year, $month, $day ) = ( ( 1900 + $datearr[5] ), ( $datearr[4] + 1 ), $datearr[3] );
	push @parameters, {
		input_box => 1,
		label => "Copyright Earlier Than",
		value => $year,
	};

	push @parameters, {
		check_box => 1,
		label => "Show Only One Copy",
		input_name => 'Option1',
	};

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
	my ($query, $column_titles, $page_breaks, $qfilters) = @_;

	my $dbh = C4::Context->dbh;
	my @looprow;
	my @loopheader;
	my %globalline;
	my @mainloop;
	my $grantotal = 0;
	my $break;
	my $break_index;

	if ( $page_breaks ) {
	    $break = 'break';
	    $break_index = 0;
	}

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

CALC_MAIN_LOOP:
	while ( my ( @values ) = $sth_col->fetchrow ) {
	    my %row;
	    my @mapped_values;

	    if ( $break && $break ne $values[ $break_index ] ) {
		$break = $values[ $break_index ];
		if ( $break ne 'break' ) {
		    $row{ 'break' } = 1;
		}
	    }

	    foreach ( @values[ 0 .. $#$column_titles ] ) {
		push @mapped_values, { value => $_ };
	    }
	    $row{ 'values' } = \@mapped_values;
	    push @looprow, \%row;
	    $grantotal++;
	}

	foreach ( @$column_titles ) {
	    push @{ $loopheader[0]->{ 'values' } }, { 'coltitle' => $_ };
	}

	# the filters used
	$globalline{loopfilter} = $qfilters;

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
