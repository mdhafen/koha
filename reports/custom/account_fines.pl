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
				flagsrequired => {reports => 1},
				debug => 0,
				});

my $reportname = "account_fines";  # ie "collection_itemnums"
my $reporttitle = "Fines";  # ie "Item Number by Branch"
my @columns = ( "borrowers.sort2", "CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron", "CONCAT_WS(' ',biblio.title,biblio.seriestitle) AS title", "accountlines.description", "accountlines.amountoutstanding", "borrowers.borrowernumber", "borrowers.cardnumber" );
my @column_titles = ( "Homeroom Teacher", "Patron", "Title", "Description", "Amount Outstanding" );
my @tables = ( "accountlines",
	       [ # Cross Joined Tables
	         {
	           table => 'borrowers',  # Table name
	           using => 'borrowernumber',  # Using column
	         },
	       ],
	       [ # Left Joined Tables
	         {
	           table => 'items',  # Table name
	           using => 'itemnumber',  # Using column
	         },
	         {
	           table => 'biblio',  # Table name
	           using => 'biblionumber',  # Using column
	         },
	       ],
	       );

#FIXME build queryfilter
my @filters = $input->param("Filter");
my @queryfilter = ();

push @queryfilter, { crit => 'borrowers.sort1', op => '=', filter => $dbh->quote( $filters[0] ), title => 'sort1', value => $filters[0] } if ( $filters[0] );
push @queryfilter, { crit => 'borrowers.sort2', op => '=', filter => $dbh->quote( $filters[1] ), title => 'sort2', value => $filters[1] } if ( $filters[1] );

#FIXME change $filters[2] to the index in @parameters of the patron branch field
if ( C4::Context->preference("IndependantBranches") || $filters[3] ) {
    #FIXME change $hbranch here to match whatever tracks branch in the query
    my $hbranch = C4::Context->preference('HomeOrHoldingBranch') eq 'homebranch' ? 'items.homebranch' : 'items.holdingbranch';
    my $branch = $filters[3] || C4::Context->userenv->{branch};
    push @queryfilter, { crit => "( borrowers.branchcode", op => "=", filter => $dbh->quote( $branch ) ." OR $hbranch = ". $dbh->quote( $branch ) ." )", title => "School", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
}

my @loopfilter = ();

my $where = "accountlines.amountoutstanding <> 0";
my $order = "$columns[0], Patron";
my $group = "";
my $page_breaks;

if ( $filters[2] ) {
    $columns[4] = 'SUM(accountlines.amountoutstanding)';
    splice @columns,2,2;
    splice @column_titles,2,2;
    push @queryfilter, { crit => '1', op => '>=', filter => '1', title => 'Fine', value => $filters[2] };
    $group = "borrowernumber HAVING SUM(amountoutstanding) >= ";
    $group .= $dbh->quote( $filters[2] );
    $group .= " OR SUM(amountoutstanding) <= ";
    $group .= $dbh->quote( "-$filters[2]" );
}

if ( $input->param("Options") ) {
    $page_breaks = 1;
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
	my $results = calculate( \@columns, \@column_titles, \@tables, $where, $order, $group, \@queryfilter, \@loopfilter );
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

	push @parameters, {
	    input_box => 1,
	    label => "Fines greater than \$",
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
	    label => "One Teacher Per Page",
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
	my ($columns, $column_titles, $tables, $where, $order, $group, $qfilters, $lfilters) = @_;

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
	my ( $subtotal, $sub_break );

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

	$query .= "GROUP BY $group " if ( $group );

	$query .= "ORDER BY $order " if ( $order );

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
		( uc $$a[0] cmp uc $$b[0] ) ||
		    ( uc $$a[ $num+1 ] cmp uc $$b[ $num+1 ] ) ||
		    ( uc $$a[ $num+3 ] cmp uc $$b[ $num+3 ] ) ||
		    ( uc $$a[ $num+4 ] cmp uc $$b[ $num+4 ] )
	    };
	    @big_loop = sort $sort_func @big_loop;
	}

	if ( $page_breaks ) {
	    $break = 'break';
	    $break_index = 0;
	}
	$sub_break = 'break';

	foreach my $data ( @big_loop ) {
	    my %row;
	    my @mapped_values;
	    my @values = @$data;

	    if ( $break && $break ne $values[ $break_index ] ) {
		if ( $break ne 'break' ) {
		    $row{ 'break' } = 1;
		}
		$break = $values[ $break_index ];
	    }

	    if ( $sub_break ne $values[ 1 ] ) {
		if ( $sub_break ne 'break' ) {
		    push @looprow, {
			 'values' => [
				       {
					   'width' => @$column_titles - 1,
					   'value' => 'Subtotal',
					   'header' => 1,
				       },
				       {
					   'value' => sprintf( "%.2f", $subtotal ),
					   'header' => 1,
				       }
				     ]
		       };
		    $subtotal = 0;
		}
		$sub_break = $values[ 1 ];
	    }

	    foreach ( @values[ 0 .. $#$column_titles ] ) {
		push @mapped_values, { value => $_ };
	    }
	    $mapped_values[ $#mapped_values ] = { value => sprintf( "%.2f", $mapped_values[ $#mapped_values ]{value} ) };
	    $mapped_values[ 1 ]{ link } = "/cgi-bin/koha/members/boraccount.pl?borrowernumber=". $values[ $#values - 1 ];

	    $row{ 'values' } = \@mapped_values;
	    push @looprow, \%row;
	    $grantotal+=@values[ $#$column_titles ];
	    $subtotal += @values[ $#$column_titles ];
	}
	#  And last subtotal row
	push @looprow, {
	    'values' => [
		{
		    'width' => @$column_titles - 1,
		    'value' => 'Subtotal',
		    'header' => 1,
		},
		{
		    'value' => sprintf( "%.2f", $subtotal ),
		    'header' => 1,
		}
		]
	};

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
