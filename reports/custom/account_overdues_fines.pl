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

my $reportname = "account_overdues_fines";  # ie "collection_itemnums"
my $reporttitle = "Overdue Copies And Fines";  # ie "Item Number by Branch"
my @column_titles = ( "Homeroom Teacher", "Card Number", "Patron", "Description", "Amount Outstanding" );
my @tables = ( "accountlines",  # ie "items"
	       [  # columns
		  "borrowers.sort2",
		  "borrowers.cardnumber",
		  "CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron",
		  "description",
		  "amountoutstanding",
		  "borrowers.cardnumber"
	       ],
	       [ # Joined Tables
	         {
		   join => 'CROSS',
	           table => 'borrowers',  # Table name
	           using => 'borrowernumber',  # Using column
	         },
		 {
		   join => 'LEFT',
		   table => 'items',
		   using => 'itemnumber',
		 },
	       ],
	       "issues",  # Union Table
	       [  # columns
		  "borrowers.sort2",
		  "borrowers.cardnumber",
		  "CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron",
		  "CONCAT_WS( '<br>', CONCAT_WS( ' ', biblio.title, biblio.remainderoftitle ), CONCAT( 'Due: ', date_due ), CONCAT( 'Barcode: ', barcode, ' &nbsp; Call Number: ', itemcallnumber ), CONCAT( '<b>Replacement Price: ', replacementprice, '</b>' ) ) AS description",
		  "NULL",
		  "borrowers.cardnumber"
	       ],
	       [ # Joined Tables
	         {
		   join => 'CROSS',
	           table => 'borrowers',  # Table name
	           using => 'borrowernumber',  # Using column
	         },
	         {
		   join => 'CROSS',
	           table => 'items',  # Table name
	           using => 'itemnumber',  # Using column
	         },
	         {
		   join => 'CROSS',
	           table => 'biblio',  # Table name
	           using => 'biblionumber',  # Using column
	         },
	       ],
	       );

#FIXME build queryfilter
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");
my @queryfilter = ();
my $local_only = 0;
if ( $input->param( 'Options5' ) ) {
    $local_only = 1;
}

push @queryfilter, { crit => 'borrowers.sort1', op => '=', filter => $dbh->quote( $filters[0] ), title => 'sort1', value => $filters[0] } if ( $filters[0] );
push @queryfilter, { crit => 'borrowers.sort2', op => '=', filter => $dbh->quote( $filters[1] ), title => 'sort2', value => $filters[1] } if ( $filters[1] );
push @queryfilter, { crit => 'categorycode', op => '=', filter => $dbh->quote( $filters[2] ), title => 'Patron Category', value => $filters[2] } if ( $filters[2] );
push @queryfilter, { crit => "COALESCE( borrowers.gonenoaddress, 0 )", op => "=", filter => "0", title => 'Not flagged', value => 'Gone' } if ( $input->param( 'Options6' ) );

if ( $filters[3] ) {
    my $s = join ',', map { $dbh->quote($_) } split( /[\s,]+/, $filters[3] );
    push @queryfilter, { crit => "borrowers.cardnumber", op => 'in', filter => "($s)", title => "Card Numbers", value => $filters[3] };
}

#FIXME change $filters[2] to the index in @parameters of the patron branch field
if ( C4::Context->preference("IndependantBranches") || $filters[4] ) {
    my $branch = $filters[4] || C4::Context->userenv->{branch};
    if ( $local_only ) {
	push @queryfilter, { crit => "( ( items.homebranch = ". $dbh->quote( $branch)." OR items.homebranch IS NULL ) AND borrowers.branchcode", op => "=", filter => $dbh->quote( $branch ) ." )", title => "School Only", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
    } else {
	push @queryfilter, { crit => "( borrowers.branchcode = ". $dbh->quote( $branch )." OR items.homebranch", op => "=", filter => $dbh->quote( $branch ) ." )", title => "School", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
    }
}

my @loopfilter = ();

my $where = [ "accountlines.amountoutstanding <> 0" ];
my $order = "sort2,patron";
my $page_breaks = ( $input->param( 'Options' ) ) ? 1 : 0 ;

push @$where, "date_due < CURRENT_DATE()" unless ( $input->param( 'Options2' ) );

if ( $input->param( 'Options3' ) ) {
    $tables[4][3] = "CONCAT_WS( ' &nbsp; ', barcode, CONCAT_WS( ' ', biblio.title, biblio.remainderoftitle ) )";
    $tables[4][4] = "replacementprice";
    splice @{ $tables[4] }, 1, 1;
    splice @{ $tables[1] }, 1, 1;
    splice @column_titles, 1, 1;
}

if ( $input->param( 'Options4' ) ) {
    shift @{ $tables[1] };
    shift @{ $tables[4] };
    shift @column_titles;
    $order = "patron";
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

my $userenv = C4::Context->userenv;

$template->param(
		 do_it => $do_it,
		 reportname => $reportname,
		 reporttitle => $reporttitle,
		 );

if ($do_it) {
	my $results = calculate( \@column_titles, \@tables, $where, $order, \@queryfilter, \@loopfilter );
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
	    checked => 0,  # for checkboxes
	    count => 1,	 #  Note: checkboxes need a counter to work right
	    id => "",  # html tag id, mostly used for javascript and calendar
	    limit => "",  # The id of the paramater if the calendar has a limit
	    limit_op => '>',  # The op for the calendar limit
	    value => '',  # default value, mostly used for calendars
	    onchange => '',  #  javascript
	    #input_name => 'Filter',  # input name
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
	    input_box => 1,
	    label => "Only Show patrons with these Card Numbers",
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

	push @parameters, {
	    check_box => 1,
	    count => 1,
	    input_name => "Options",
	    label => "One Patron Per Page",
	};

	push @parameters, {
	    check_box => 1,
	    count => 2,
	    input_name => "Options2",
	    label => "Show All Checked Out Copies",
	};

	push @parameters, {
	    check_box => 1,
	    count => 3,
	    input_name => "Options3",
	    label => "Concise Check Out Info",
	};

	push @parameters, {
	    check_box => 1,
	    count => 4,
	    input_name => "Options4",
	    label => "Don't Show Homeroom Teacher",
	};

	push @parameters, {
	    check_box => 1,
	    count => 5,
	    input_name => "Options5",
	    label => "Only Students At Your School",
	};

	push @parameters, {
	    check_box => 1,
	    count => 6,
            checked => 1,
	    input_name => "Options6",
	    label => "Exclude students flagged as Gone",
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
	my ($column_titles, $tables, $where, $order, $qfilters, $lfilters) = @_;

	my $dbh = C4::Context->dbh;
	my @wheres;
	my @looprow;
	my @loopheader;
	my %globalline;
	my @mainloop;
	my $grantotal = 0;
	my $subtotal = 0;
	my @big_loop;
	my $break;
	my $break_index;
	my $columns;

	my $table = shift @$tables;
	my $columns = shift @$tables;
	my $column = join ',', @$columns;
	my %columns_reverse_hash = map { $_ =~ /(\w+)$/ => $break_index++ } @$columns;

	# FIXME you might want to add DISTINCT here or a GROUP BY below
	my $query;
	if ( @$tables > 3 ) {
	    $query = "( ";
	}
	$query .= "SELECT $column FROM $table ";
	if ( @$tables ) {
	    if ( my @tab = @{ shift @$tables } ) {
		foreach my $table ( @tab ) {
		    $query .= "$$table{join} JOIN $$table{table} ";
		    if ( $$table{using} ) {
			$query .= "USING ($$table{using}) ";
		    } elsif ($$table{on_l} and $$table{on_r}) {
			$query .= "ON $$table{on_l} = $$table{on_r} ";
		    } else {
			warn "$reportname : don't know how to join table $$table{table}";
		    }
		}
	    }
	}
	$query .= "WHERE ";
	$query .= "$$where[0] " if ( $$where[0] );
	$query .= "AND " if ( $$where[0] && @$qfilters );

	if ( @$qfilters ) {
	    foreach ( @$qfilters ) {
                push @wheres, "$$_{crit} $$_{op} $$_{filter} ";
	    }
	}
	$query .= join "AND ", @wheres;

	if ( @$tables ) {
	    $query .= " ) UNION ( ";

	    $table = shift @$tables;
	    $columns = shift @$tables;
	    $column = join ',', @$columns;

	    $query .= "SELECT $column FROM $table ";
	    if ( @$tables ) {
		if ( my @tab = @{ shift @$tables } ) {
		    foreach my $table ( @tab ) {
			$query .= "$$table{joiin} JOIN $$table{table} ";
			if ( $$table{using} ) {
			    $query .= "USING ($$table{using}) ";
			} elsif ($$table{on_l} and $$table{on_r}) {
			    $query .= "ON $$table{on_l} = $$table{on_r} ";
			} else {
			    warn "$reportname : don't know how to join table $$table{table}";
			}
		    }
		}
	    }
	    $query .= "WHERE ";
	    $query .= "$$where[1] " if ( $$where[1] );
	    $query .= "AND " if ( $$where[1] && @$qfilters );
	    $query .= join "AND ", @wheres;
	    $query .= " ) ";
	}

	$query .= "ORDER BY $order" if ( $order );

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

CALC_MAIN_LOOP:
	while ( my ( @values ) = $sth_col->fetchrow ) {
	    push @big_loop, \@values;
	}

	$break = 'break';
	$break_index = scalar @$column_titles;  # last item in @values

	foreach my $data ( @big_loop ) {
	    my %row;
	    my @mapped_values;
	    my @values = @$data;

	    if ( $break && $break ne $values[ $break_index ] ) {
		if ( $break ne 'break' ) {
		    push @looprow, {
			'class' => 'bottomspace',
			'values' => [
			    {
				'width' => @$column_titles - 1,
				'value' => ' ',
				'header' => 1,
			    },
			    {
				'value' => sprintf( "%.2f", $subtotal ),
				'header' => 1,
			    }
			    ]
		    };
		    $subtotal = 0;
		    if ( $page_breaks ) {
			$row{ 'break' } = 1;
		    }
		}
		$break = $values[ $break_index ];
	    }

	    foreach ( @values[ 0 .. $#$column_titles ] ) {
		push @mapped_values, { value => $_ };
	    }
	    if ( $mapped_values[ $#mapped_values ]{ value } ) {
		$mapped_values[ $#mapped_values ] = { value => sprintf( "%.2f", $mapped_values[ $#mapped_values ]{ value } ) };
	    }
	    $row{ 'values' } = \@mapped_values;
	    push @looprow, \%row;
	    $subtotal += $values[ $#$column_titles ];
	    $grantotal += $values[ $#$column_titles ];
	}
	if ( $break ) {
	    push @looprow, {
		'class' => 'bottomspace',
		'values' => [
		    {
			'width' => @$column_titles - 1,
			'value' => ' ',
			'header' => 1,
		    },
		    {
			'value' => sprintf( "%.2f", $subtotal ),
			'header' => 1,
		    }
		    ]
	    };
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
					   'value' => ' ',
					   'header' => 1,
				       },
				       {
					   'value' => sprintf( "%.2f", $grantotal ),
					   'header' => 1,
				       }
				     ]
		       };

	# the core of the table
	$globalline{looprow} = \@looprow;


	push @mainloop, \%globalline;

	return \@mainloop;
}
