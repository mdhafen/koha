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
use C4::Dates qw/format_date format_date_in_iso/;
use C4::Branch;  # GetBranches GetBranchInfo
use C4::Members;  # GetMemberSortValues
use C4::Koha;
use C4::Circulation;

my $accesses_borrowers = 0;  # bool to indicate this report uses the borrowers table

if ( $accesses_borrowers && C4::Context->preference('MembersViaExternal') ) {
    use C4::MembersExternal;
}

# Watch out for:
#  C4::Context->preference('MembersViaExternal')
#  C4::Context->preference("IndependantBranches")

my $input = new CGI;
my $dbh = C4::Context->dbh;
my $hbranch = C4::Context->preference('HomeOrHoldingBranch') eq 'homebranch' ? 'items.homebranch' : 'items.holdingbranch';

my ($template, $borrowernumber, $cookie)
	= get_template_and_user({template_name => "reports/custom_report.tmpl",
				query => $input,
				type => "intranet",
				authnotrequired => 0,
				flagsrequired => {management => 1, tools => 1},
				debug => 0,
				});

my $reportname = "cat_inventory";  # ie "collection_itemnums"
my $reporttitle = "Catalog Inventory";  # ie "Item Number by Branch"
my @columns = ( "items.datelastseen", "items.itemcallnumber", "items.barcode", "CONCAT_WS(' ', biblio.title, biblio.remainderoftitle, biblio.seriestitle) AS fulltitle", "$hbranch", "items.itemnumber" );
my @column_titles = ( "Last Seen", "Call Number", "Barcode", "Title", "Library" );
my @tables = ( "items",  # ie "items"
	       [ # Cross Joined Tables
	         {
	           table => 'biblio',  # Table name
	           using => 'biblionumber',  # Using column
#	           on_l => '',   # Left hand Join On column
#	           on_r => '',   # Right hand Join On column
	         },
	         {
	           table => 'biblioitems',  # Table name
	           using => 'biblioitemnumber',  # Using column
#	           on_l => '',   # Left hand Join On column
#	           on_r => '',   # Right hand Join On column
	         },
	       ],
	       [ # Left Joined Tables
	         {
	           table => 'issues',  # Table name
	           using => 'itemnumber',  # Using column
#	           on_l => '',   # Left hand Join On column
#	           on_r => '',   # Right hand Join On column
	         },
	       ],
	       );

#FIXME build queryfilter
my @filters = $input->param("Filter");
my @options = ( $input->param("Check1") ."", $input->param("Check2") ."" );
my @queryfilter = ();
my @loopfilter = ();

my $where = "itemlost = 0 AND wthdrawn = 0";
my $order = "$columns[0]";
my $page_breaks;
my $set_lost;

if ( $filters[0] ) {
    push @queryfilter, { crit => 'datelastseen', op => '<', filter => $dbh->quote( format_date_in_iso($filters[0]) ), title => "Last Seen", value => $filters[0] };
}

if ( $input->param( "ItemTypes" ) ) {
    my @types_array = $input->param( "ItemTypes" );
    my $itype_field = ( C4::Context->preference('item-level_itypes') )
	? 'items.itype'           # item-level
	: 'biblioitems.itemtype'; # biblio-level
    @types_array = map $dbh->quote( $_ ), @types_array;
    my $types = "(". join( ',', @types_array ) .")";
    push @queryfilter, { crit => $itype_field, op => "IN", filter => $types, title => "Item Category", value => $types };
}

if ( $filters[1] ) {
    for ( $filters[1] ) {
	if    ( $_ eq 'datelastseen' ) { $order = "datelastseen" }
	elsif ( $_ eq 'title' )        { $order = "fulltitle" }
	elsif ( $_ eq 'callnumber' )   { $order = "itemcallnumber" }
    }
}

if ( $options[0] ) {
    push @queryfilter, { crit => 'issues.date_due', op => 'IS', filter => 'NULL', title => 'Copy', value => 'Not On Loan' };
}

if ( $options[1] ) {
    $set_lost = 4;  # Missing
}

#FIXME change $filters[2] to the index in @parameters of the patron branch field
if ( C4::Context->preference("IndependantBranches") || $filters[2] ) {
    #FIXME change $hbranch here to match whatever tracks branch in the query
    my $branch = ( C4::Context->preference("IndependantBranches") ) ? C4::Context->userenv->{branch} : $filters[2];
    push @queryfilter, { crit => $hbranch, op => "=", filter => $dbh->quote( $branch ), title => "School", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
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
	my $results = calculate( \@columns, \@column_titles, \@tables, $where, $order, \@queryfilter, \@loopfilter, $set_lost );
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

	my $today = C4::Dates->today();
	push @parameters, {
	    calendar => 1,
	    label => "Last Seen",
	    id => "lastseen",
	    value => $today,
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

	my @orders = (
	    { value => 'datelastseen', label => 'Date Last Seen' },
	    { value => 'title', label => 'Title' },
	    { value => 'callnumber', label => 'Call Number' },
	    );
	push @parameters, {
	    select_box => 1,
	    select_loop => \@orders,
	    label => "Order result by",
	};

	push @parameters, {
	    check_box => 1,
	    checked => 1,
	    count => 1,
	    label => "Skip Copies On Loan",
	};

	push @parameters, {
	    check_box => 1,
	    checked => 0,
	    count => 2,
	    label => "Set Copies As Missing",
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
	    DHTMLcalendar_dateformat => C4::Dates->DHTMLcalendar(),
	    parameter_loop => \@parameters,
	    sep_loop => \@dels,
	    );

	output_html_with_http_headers $input, $cookie, $template->output;
}

sub calculate {
	my ($columns, $column_titles, $tables, $where, $order, $qfilters, $lfilters, $set_lost) = @_;

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

	my $sth_setlost = $dbh->prepare( "UPDATE items SET itemlost = $set_lost WHERE itemnumber = ?" );

	my $table = shift @$tables;
	my $column = join ',', @$columns;
	my %columns_reverse_hash = map { $_ => $break_index++ } @$columns;

	# FIXME you might want to add DISTINCT here or a GROUP BY below
	my $query = "SELECT $column FROM $table ";
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
	$query .= "$where " if ( $where );
	$query .= "AND " if ( $where && @$qfilters );

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

		    if ( ref $temp eq 'HASH' && %$temp ) { # not empty hash ref
			foreach ( sort keys %external_bor_fields ) {
			    next CALC_MAIN_LOOP if ( $external_bor_fields{$_} ne $temp->{$_} );
			}
		    } else { # non-external patron, compare against @values
			foreach ( sort keys %external_bor_fields ) {
			    my $index = $columns_reverse_hash{ $_ };
			    next CALC_MAIN_LOOP if ( $external_bor_fields{$_} ne $values[ $index ] );
			}
		    }
		}
	    }
	    push @big_loop, \@values;
	}

	# FIXME Sort big_loop here
	#  This is necessary if MembersViaExternal is on and
	#  there are borrowers fields ( ie sort1 or sort2 ) in the order clause

	if ( $accesses_borrowers && $order =~ /sort2/ ) {
	    my $num = 0;  # sort2 is always [0], others might be offset by sort1
	    $num = 1 if ( $$columns[1] eq 'borrowers.sort1' );
	    my $sort_func = sub {
		( uc $$a[ $num+1 ] cmp uc $$b[ $num+1 ] ) ||
		    ( uc $$a[0] cmp uc $$b[0] ) ||
		    ( uc $$a[ $num+3 ] cmp uc $$b[ $num+3 ] ) ||
		    ( uc $$a[ $num+4 ] cmp uc $$b[ $num+4 ] )
	    };
	    @big_loop = sort $sort_func @big_loop;
	}

	if ( $page_breaks ) {
	    $break = 'break';
	    $break_index = 0;
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

	    if ( $set_lost ) {
		$sth_setlost->execute( $values[ $#values ] );
	    }

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
					   'value' => ' ',
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
