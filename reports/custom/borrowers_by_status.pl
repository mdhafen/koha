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
use C4::Members;  # GetMemberSortValues GetBorrowercategoryList
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

my $reportname = "borrowers_by_status";
my $reporttitle = "List Borrowers by Status";
my @column_titles = ( "Patron", "Cardnumber", "Category", "Graduation Date", "Homeroom Teacher", "Gone", "Lost", "Debarred" );
my @queryfilter = ();

my @where = ();

# Handle parameters
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");

if ( $filters[0] ) {
    push @queryfilter, { title => "Graduation Date", op => "=", value => $filters[0] };
    push @where, " borrowers.sort1 = ". $dbh->quote( $filters[0] );
}

if ( $filters[1] ) {
    push @queryfilter, { title => "Homeroom Teacher", op => "=", value => $filters[1] };
    push @where, " borrowers.sort2 = ". $dbh->quote( $filters[1] );
}

if ( $filters[2] ) {
    push @queryfilter, { title => "Patron Category", op => "=", value => $filters[2] };
    push @where, " borrowers.categorycode = ". $dbh->quote( $filters[2] );
}

if ( $input->param('Status1') ) {
    push @queryfilter, { title => "Gone", op => "=", value => "No Address" };
    push @where, " borrowers.gonenoaddress = 1";
}

if ( $input->param('Status2') ) {
    push @queryfilter, { title => "Card", op => "=", value => "Lost" };
    push @where, " borrowers.lost = 1";
}

if ( $input->param('Status3') ) {
    push @queryfilter, { title => "Debarred", op => "=", value => "Yes" };
    push @where, " borrowers.debarred = 1";
}

if ( C4::Context->preference("IndependantBranches") || $filters[3] ) {
    my $branch = ( C4::Context->preference('IndependantBranches') ) ? $userenv->{branch} : $filters[3];
    push @queryfilter, { title => "Library", op => "=", value => $branch };
    push @where, " borrowers.branchcode = ".$dbh->quote( $branch );
}

my $query = 
   "SELECT CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron,
           cardnumber, description, sort1, sort2, gonenoaddress, lost, debarred,
           borrowernumber
      FROM borrowers
CROSS JOIN categories using (categorycode) ";
if ( @where ) {
    $query .= "WHERE ". join ' AND ', @where;
}

my $order = $input->param("Order") || '';
$query .= " ORDER BY ";
for ( $order ) {
    if    ( /bhn/ ) { $query .= "branchcode,sort2,patron"; }
    elsif ( /bn/ )  { $query .= "branchcode,patron"; }
    else            { $query .= "patron"; }
}

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
	my $results = calculate( $query, \@column_titles, $output );
	$results->[0]{loopfilter} = \@queryfilter if ( @queryfilter );
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

	my ( $sort1_values, $sort2_values ) = GetMemberSortValues();
	my ( @sort1_loop, @sort2_loop );
	foreach ( sort @$sort1_values ) {
	    push @sort1_loop, { value => $_, label => $_ } if ( $_ );
	}
	foreach ( sort @$sort2_values ) {
	    push @sort2_loop, { value => $_, label => $_ } if ( $_ );
	}
	push @parameters, {
	    select_box => 1,
	    select_loop => \@sort1_loop,
	    label => "sort1",
	    first_blank => 1,
	};
	push @parameters, {
	    select_box => 1,
	    select_loop => \@sort2_loop,
	    label => "sort2",
	    first_blank => 1,
	};

	my $patron_cats = GetBorrowercategoryList();
	my @patron_cats_loop = ();
	foreach ( @$patron_cats ) {
	    push @patron_cats_loop, { value => $_->{categorycode}, label => $_->{description} };
	}
	push @parameters, {
	    select_box => 1,
	    select_loop => \@patron_cats_loop,
	    label => "Patron Category",
	    first_blank => 1,
	};

        push @parameters, {
            check_box => 1,
            count => 1,
            input_name => "Status1",
            label => "Gone (No Address)",
        };

        push @parameters, {
            check_box => 1,
            count => 2,
            input_name => "Status2",
            label => "Lost Card",
        };

        push @parameters, {
            check_box => 1,
            count => 3,
            input_name => "Status3",
            label => "Debarred",
        };

	my @order_loop;
	push @order_loop, { value => 'bn', label => 'Name' };
	push @order_loop, { value => 'bc', label => 'Cardnumber' };
	push @order_loop, { value => 'bhn', label => 'Homeroom Teacher' };
	push @parameters, {
	    select_box => 1,
	    input_name => 'Order',
	    select_loop => \@order_loop,
	    label => 'Sort By',
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
	    parameter_loop => \@parameters,
	    sep_loop => \@dels,
	    );

	output_html_with_http_headers $input, $cookie, $template->output;
}

sub calculate {
	my ($query, $column_titles, $output) = @_;

	my $dbh = C4::Context->dbh;
	my $itemtypes = GetItemTypes();
	my @loopheader;
	my @looprow;
	my %globalline;
	my @mainloop;
	my @big_loop;

        if ( $output ne 'screen' ) {
            pop @$column_titles;  # discard 'Action' header
        }

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

CALC_MAIN_LOOP:
	while ( my ( @values ) = $sth_col->fetchrow ) {
            push @big_loop, \@values;
	}

	foreach my $data ( @big_loop ) {
            my %row;
            my @mapped_values;

            push @mapped_values,
            { 
                value => $data->[0],
                link => "/cgi-bin/koha/members/moremember.pl?borrowernumber=".$data->[8],
            },
            { value => $data->[1] },
            { value => $data->[2] },
            { value => $data->[3] },
            { value => $data->[4] },
            { value => $data->[5] ? "Gone" : " " },
            { value => $data->[6] ? "Card Lost" : " " },
            { value => $data->[7] ? "Debarred" : " " };

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
