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
use C4::Branch;  # GetBranches GetBranchInfo
use C4::Members;  # GetMemberSortValues
use C4::Koha;
use C4::Circulation;

my $accesses_borrowers = 1;  # bool to indicate this report uses the borrowers table

if ( $accesses_borrowers && C4::Context->preference('MembersViaExternal') ) {
    use C4::MembersExternal;
}

# Watch out for:
#  C4::Context->preference('MembersViaExternal')
#  C4::Context->preference("IndependantBranches")

my $input = new CGI;
my $dbh = C4::Context->dbh;

my ($template, $borrowernumber, $cookie)
	= get_template_and_user({template_name => "reports/custom_report.tmpl",
				query => $input,
				type => "intranet",
				authnotrequired => 0,
				flagsrequired => {management => 1, tools => 1},
				debug => 0,
				});

my $reportname = "circ_issued";
my $reporttitle = "Checked Out Copies";
my @columns = ( "borrowers.sort2", "issues.date_due", "CONCAT( borrowers.surname, ', ', borrowers.firstname ) AS borrower", "branches.branchname", "biblio.title", "items.itemcallnumber", "items.barcode", "items.replacementprice", "items.itemnotes", "borrowers.cardnumber" );
my @column_titles = ( "Homeroom Teacher", "Date Due", "Borrower", "Borrowers School", "Title", "Call Number", "Barcode", "Replacement Price", "Copy notes" );
my @tables = ( "issues",
	       [ # Cross Joined Tables
	         {
	           table => 'borrowers',
	           using => 'borrowernumber',
	         },
		 {
		     table => 'items',
		     using => 'itemnumber',
		 },
		 {
		     table => 'biblio',
		     using => 'biblionumber',
		 },
		 {
		     table => 'biblioitems',
		     on_l => 'items.biblioitemnumber',
		     on_r => 'biblioitems.biblioitemnumber',
		 },
		 {
		     table => 'branches',
		     on_l => 'borrowers.branchcode',
		     on_r => 'branches.branchcode',
		 },
	       ],
	       [ # Left Joined Tables
	       ],
	       );

#FIXME build queryfilter
my @filters = $input->param("Filter");
my @queryfilter = ();

if ( $filters[0] ) {
    push @queryfilter, { crit => "borrowers.sort1", op => "=", filter => $dbh->quote( $filters[0] ), title => "Graduation Date", value => $filters[0] };
    @columns = ( @columns[0], "borrowers.sort1", @columns[1..$#columns] );
    @column_titles = ( @column_titles[0], "Graduation Date", @column_titles[1..$#column_titles] );
}
if ( $filters[1] ) {
    push @queryfilter, { crit => "borrowers.sort2", op => "=", filter => $dbh->quote( $filters[1] ), title => "Homeroom Teacher", value => $filters[1] };
}

my @types_array = $input->param( "ItemTypes" );
if ( @types_array ) {
    my $itype_field = ( C4::Context->preference('item-level_itypes') )
	? 'items.itype'           # item-level
	: 'biblioitems.itemtype'; # biblio-level
    @types_array = map $dbh->quote( $_ ), @types_array;
    my $types = "(". join( ',', @types_array ) .")";
    push @queryfilter, { crit => $itype_field, op => "IN", filter => $types, title => "Item Category", value => $types };
}

if ( C4::Context->preference("IndependantBranches") ) {
    my $hbranch = C4::Context->preference('HomeOrHoldingBranch') eq 'homebranch' ? 'items.homebranch' : 'items.holdingbranch';
    my $branch = C4::Context->userenv->{branch};
    push @queryfilter, { crit => $hbranch, op => "=", filter => $dbh->quote( $branch ), title => "School", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
}

my @loopfilter = ();

my $where;
my $order = "$columns[0]";

$where = "date_due < NOW()" if ( $filters[3] );  # just overdues
for ( $filters[2] ) {
    if ( /duedate/i ) { $order = "date_due ASC" }
    if ( /borrower/i ) { $order = "Borrower" }
    if ( /itemtype/i ) {
	$order = ( C4::Context->preference('item-level_itypes') )
	    ? 'items.itype'           # item-level
	    : 'biblioitems.itemtype'; # biblio-level
    }
}
my $page_breaks = $input->param("Option1");

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
	my $results = calculate( \@columns, \@column_titles, \@tables, $where, $order, \@queryfilter, \@loopfilter );
	if ($output eq "screen"){
		$template->param(mainloop => $results);
		output_html_with_http_headers $input, $cookie, $template->output;
	} else {
		print $input->header(-type => $mime,
					 -attachment=>"$basename.csv",
					 -name=>"$basename.csv" );
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
				print $$cell{value}.$sep;
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

	my @order_loop;
	push @order_loop, { value => 'borrower', label => 'Patron' };
	push @order_loop, { value => 'duedate', label => 'Due Date' };
	push @order_loop, { value => 'itemtype', label => 'Item Type' };
	push @parameters, {
	    select_box => 1,
	    select_loop => \@order_loop,
	    label => 'Sort By',
	};

	push @parameters, {
	    check_box => 1,
	    input_name => 'Filter',
	    label => 'Only Overdues',
	};

	my @break_loop;
	push @break_loop, { value => '', label => 'No Breaks' };
	push @break_loop, { value => 'patron', label => 'One Student Per Page' };
	push @parameters, {
	    radio_group => 1,
	    radio_loop => \@break_loop,
	    input_name => 'Option1',
	    label => 'Page Breaks',
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
	my ($columns, $column_titles, $tables, $where, $order, $qfilters, $lfilters) = @_;

	my $dbh = C4::Context->dbh;
	my @wheres;
	my @looprow;
	my @loopheader;
	my %globalline;
	my @mainloop;
	my $grantotal = 0;
	my @big_loop;
	my $break;
	my $break_index;

	my $table = shift @$tables;
	my $column = join ',', @$columns;

	my $query = "SELECT DISTINCT $column FROM $table ";
	if ( @$tables ) {
	    if ( my @cross = @{ shift @$tables } ) {
		foreach my $cross_table ( @cross ) {
		    $query .= "CROSS JOIN $$cross_table{table} ";
		    if ( $$cross_table{using} ) {
			$query .= "USING ($$cross_table{using}) ";
		    } elsif ($$cross_table{on_l} and $$cross_table{on_r}) {
			$query .= "ON $$cross_table{on_l} = $$cross_table{on_r} ";
		    } else {
			warn "$reportname : don't know how to join table $$cross_table{table}";
		    }
		}
	    }
	    if ( my @left = @{ shift @$tables } ) {
		foreach my $left_table ( @left ) {
		    $query .= "LEFT JOIN $$left_table{table} ";
		    if ( $$left_table{using} ) {
			$query .= "USING ($$left_table{using}) ";
		    } elsif ($$left_table{on_l} and $$left_table{on_r}) {
			$query .= "ON $$left_table{on_l} = $$left_table{on_r} ";
		    } else {
			warn "$reportname : don't know how to join table $$left_table{table}";
		    }
		}
	    }
	}
	$query .= "WHERE ";
	$query .= "$where AND " if ( $where );

	if ( @$qfilters ) {
	    foreach ( @$qfilters ) {
		if ( $accesses_borrowers && C4::Context->preference('MembersViaExternal') && $$_{crit} =~ m/^borrowers\.(.*?)$/i ) {
		    my %okfields = (
				    borrowernumber => 1,
				    cardnumber => 1,
				    surname => 1,
				    firstname => 1,
				    othernames => 1,
				    branchcode => 1,
				    );
		    #  External fields will have to be handled down in the loop
		    unless ( $okfields{ $1 } ) {
			#  leading and trailing ' will muddle MembersExternal
			$$_{filter} =~ s/^\'(.*)\'$/$1/;
			push @$lfilters, { crit => $$_{crit}, filter => $$_{filter} };
		    } else {
			push @wheres, "$$_{crit} $$_{op} $$_{filter} ";
		    }
		} else {
		    push @wheres, "$$_{crit} $$_{op} $$_{filter} ";
		}
	    }
	}
	$query .= join "AND ", @wheres;

	$query .= "ORDER BY $order" if ( $order );

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

CALC_MAIN_LOOP:
	while ( my ( @values ) = $sth_col->fetchrow ) {
	    #  This block is to handle MembersViaExternal stuff, and
	    #   for other custom loop filters
	    if ( @$lfilters ) {
		my %external_bor_fields;
		foreach ( @$lfilters ) {
		    if ( $accesses_borrowers && C4::Context->preference('MembersViaExternal') && $$_{crit} =~ m/^borrowers\.(.*?)$/i ) {
			$external_bor_fields{ $1 } = $$_{filter};
		    } else {
			# Process other loop filters here
		    }

		}
		if ( %external_bor_fields ) {
		    # FIXME borrowers.cardnumber needs to be last in the columns for this
		    my $cardnumber = $values[ $#values ];
		    my $temp = GetMemberDetails_External( $cardnumber );

		    foreach ( sort keys %external_bor_fields ) {
			next CALC_MAIN_LOOP if ( $external_bor_fields{$_} ne $temp->{$_} );
		    }
		}
	    }
	    push @big_loop, \@values
	}

	# FIXME Sort big_loop here
	#  This is necessary if MembersViaExternal is on and
	#  there are borrowers fields ( ie sort1 or sort2 ) in the order clause

	if ( $accesses_borrowers && $order =~ /sort2/ ) {
	    my $num = 0;  # fields might be offset by sort1
	    $num = 1 if ( $$columns[1] eq 'borrowers.sort1' );
	    my $sort_func = sub { # branch,sort2,borrower,title
		( uc $$a[ $num+3 ] cmp uc $$b[ $num+3 ] ) ||
		    ( uc $$a[0] cmp uc $$b[0] ) ||
		    ( uc $$a[ $num+2 ] cmp uc $$b[ $num+2 ] ) ||
		    ( uc $$a[ $num+4 ] cmp uc $$b[ $num+4 ] )
	    };
	    @big_loop = sort $sort_func @big_loop;
	}

	if ( $page_breaks ) {
	    $break = 'break';
	    foreach my $index ( 0..$#$columns ) {
		if ( $$columns[ $index ] =~ /borrower/ ) {
		    $break_index = $index;
		}
	    }
	}

	foreach my $data ( @big_loop ) {
	    my %row;
	    my @mapped_values;
	    my @values = @$data;

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
	push @looprow, {
			 'values' => [
				       {
					   'width' => @$column_titles - 1,
					   'value' => '&nbsp;',
					   'header' => 1,
				       },
				       {
					   'value' => $grantotal,
					   'header' => 1,
				       }
				     ]
		       };

	# the core of the table
	$globalline{looprow} = \@looprow;


	push @mainloop, \%globalline;

	return \@mainloop;
}
