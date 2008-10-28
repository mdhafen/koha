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
# report template v. 3.1.1

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

my ($template, $borrowernumber, $cookie)
	= get_template_and_user({template_name => "reports/custom_report.tmpl",
				query => $input,
				type => "intranet",
				authnotrequired => 0,
				flagsrequired => {reports => 1},
				debug => 0,
				});

my $hbranch = C4::Context->preference('HomeOrHoldingBranch') eq 'homebranch' ? 'items.homebranch' : 'items.holdingbranch';

my $reportname = "circ_stats_noissues";  # ie "collection_itemnums"
my $reporttitle = "Copies With No Check Outs";  # ie "Item Number by Branch"
my @columns = ( "itemcallnumber", "barcode", "title", $hbranch );
my @column_titles = ( "Call Number", "Barcode", "Title", "Branch" );
my @tables = ( "items",
	       [ # Joined Tables
	         {
		   join => "CROSS",
	           table => 'biblio',  # Table name
	           using => 'biblionumber',  # Using column
	         },
		 {
		   join => "LEFT",
		   table => "issues",
		   using => "itemnumber",
		 },
	       ],
	       );

#FIXME build queryfilter
my @filters = $input->param("Filter");
my @queryfilter = ();

push @queryfilter, { crit => "returndate", op => " ", filter => "IS NULL", title => "Not issued After", value => $filters[0] } if ( $filters[0] );

push @queryfilter, { crit => "( issuedate", op => " ", filter => "< ". $dbh->quote( format_date_in_iso( $filters[1] ) ) ." OR issuedate IS NULL )", title => "Not issued Before", value => $filters[1] } if ( $filters[1] );

if ( C4::Context->preference("IndependantBranches") || $filters[2] ) {
    my $branch = $filters[2] || C4::Context->userenv->{branch};
    push @queryfilter, { crit => $hbranch, op => "=", filter => $dbh->quote( $branch ), title => "School", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
}

my @loopfilter = ();

my $where = "itemnumber NOT IN ( SELECT DISTINCT itemnumber FROM old_issues ";
if ( $filters[0] ) {
    $where .= "WHERE issuedate > ". $dbh->quote( format_date_in_iso( $filters[0] ) ) ." ";
}
if ( $filters[1] ) {
    if ( $where =~ /WHERE/ ) {
	$where .= "AND ";
    } else {
	$where .= "WHERE ";
    }
    $where .= "returndate < ". $dbh->quote( format_date_in_iso( $filters[1] ) ) ." ";
}
$where .= ")";

my $order = "$columns[0]";
my $page_breaks;

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

	my ( $dateto, $datefrom );
	my @datearr = localtime(time());
	my ( $year, $month, $day ) = ( ( 1900 + $datearr[5] ), ( $datearr[4] + 1 ), $datearr[3] );
	$dateto = format_date( $year.'-'.sprintf("%0.2d", $month).'-'.sprintf("%0.2d", $day) );

	$month--;
	if ( $month == 0 ) {
	    $month = 12;
	    $year--;
	}
	$datefrom = format_date( $year.'-'.sprintf("%0.2d", $month).'-'.sprintf("%0.2d", $day) );

	push @parameters, {
	    calendar => 1,
	    label => "Between",
	    id => "cal_from",
	    limit => "cal_to",
	    limit_op => '<',  # The op for the calendar limit
	    value => $datefrom,
	};
	push @parameters, {
	    calendar => 1,
	    label => "And",
	    id => "cal_to",
	    limit => "cal_from",
	    limit_op => '>',
	    value => $dateto,
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
	    DHTMLcalendar_dateformat => C4::Dates->DHTMLcalendar(),
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
	my %columns_reverse_hash = map { $_ => $break_index++ } @$columns;

	# FIXME you might want to add DISTINCT here or a GROUP BY below
	my $query = "SELECT $column FROM $table ";
	if ( @$tables ) {
	    if ( ref $$tables[0] eq 'ARRAY' ) {
		my @joins = @{ shift @$tables };
		foreach my $join_info ( @joins ) {
		    $query .= "$$join_info{join} JOIN $$join_info{table} ";
		    if ( $$join_info{using} ) {
			$query .= "USING ($$join_info{using}) ";
		    } elsif ($$join_info{on_l} and $$join_info{on_r}) {
			$query .= "ON $$join_info{on_l} = $$join_info{on_r} ";
		    } else {
			warn "$reportname : don't know how to join table $$join_info{table}";
		    }
		}
	    }
	}
	$query .= "WHERE ";
	$query .= "$where" if ( $where );
	$query .= " AND " if ( $where and @$qfilters );

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

	if ( ref $$tables[0] eq 'SCALAR' ) {
	    #  FIXME  might want to say UNION ALL here
	    $query = "( ". $query ." ) ";
	    $query .= "UNION ( SELECT $column FROM $$tables[0] ";
	    shift @$tables;
	    if ( ref $$tables[1] eq 'ARRAY' ) {
		my @joins = shift @$tables;
		foreach my $join_info ( @joins ) {
		    $query .= "$$join_info{join} JOIN $$join_info{table} ";
		    if ( $$join_info{using} ) {
			$query .= "USING ($$join_info{using}) ";
		    } elsif ($$join_info{on_l} and $$join_info{on_r}) {
			$query .= "ON $$join_info{on_l} = $$join_info{on_r} ";
		    } else {
			warn "$reportname : don't know how to join table $$join_info{table}";
		    }
		}
	    }
	    $query .= "WHERE ";
	    $query .= "$where AND " if ( $where );
	    $query .= join "AND ", @wheres;
	    $query .= " )";
	}

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
