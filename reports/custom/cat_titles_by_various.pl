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
use C4::Koha;  # GetAuthorisedValues
use C4::Circulation;

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
my $itype = C4::Context->preference('item-level_itypes') ? 'items.itype' : 'biblioitems.itemtype';

my $reportname = "cat_titles_by_various";  # ie "collection_itemnums"
my $reporttitle = "Titles By Various Criteria";  # ie "Item Number by Branch"
my @column_titles = ( "Title", "Author", "Library", "Call Number", "Barcode", "Item Type", "Copy Notes" );

#FIXME build queryfilter
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");
my @options = ( scalar $input->param( "Option1" ) );
my @queryfilter = ();

my @wheres;
my $order = "title";
my $group = "";
my $page_breaks = "";

{
my ( $crit, $op, $filt, $title, $val );
for ( $filters[0] ) {
    if ( $_ =~ /itemnote/ ) {
        ( $crit, $op, $filt, $title, $val ) = ( "items.itemnotes", "LIKE", $dbh->quote( "%". $filters[1] ."%" ), "Copy Notes", $filters[1] ) if ( $filters[1] );
    }
    elsif ( $_ =~ /itemcall/ ) {
        ( $crit, $op, $filt, $title, $val ) = ( "items.itemcallnumber", "LIKE", $dbh->quote( $filters[1] ."%" ), "Call Number", $filters[1] ) if ( $filters[1] );
    }
    elsif ( $_ =~ /awards/ ) {
        if ( $filters[1] ) {
            ( $crit, $op, $filt, $title, $val ) = ( "biblioitems.marcxml", "LIKE", $dbh->quote( "%<datafield tag=\"586\"%<subfield code=\"a\">". $filters[1] ."%" ), "Awards", $filters[1] );
        }
    }
    elsif ( $_ =~ /itemtype/ ) {
        ( $crit, $op, $filt, $title, $val ) = ( "$itype", "=", $dbh->quote( $filters[2] ), "Item Type", $filters[2] );
    }
    elsif ( $_ =~ /location/ ) {
        ( $crit, $op, $filt, $title, $val ) = ( 'items.location', '=', $dbh->quote( $filters[3] ), "Shelving Location", $filters[3] );
    }
}
if ( $crit ) {
    push @wheres, "$crit $op $filt";
    push @queryfilter, { title => $title, op => $op, value => $val };
}
}

for ( $filters[4] ) {
    if    ( $_ eq 'title' )      {$order = "title"}
    elsif ( $_ eq 'callnumber' ) {$order = "itemcallnumber"}
    else  {$order = "title"}
}

#FIXME change $filters[2] to the index in @parameters of the patron branch field
if ( C4::Context->preference("IndependantBranches") || $filters[5] ) {
    #FIXME change $hbranch here to match whatever tracks branch in the query
    my $branch = ( C4::Context->preference("IndependantBranches") ) ? C4::Context->userenv->{branch} : $filters[5];
    push @wheres, "$hbranch = ". $dbh->quote( $branch );
    push @queryfilter, { title => "School", op => "=", value => GetBranchInfo( $branch )->[0]->{'branchname'} };
}

my $query;
if ( $options[0] ) {
	$group = "biblioitems.biblioitemnumber,biblio.biblionumber";
	$query =
    "SELECT CONCAT_WS(' ', biblio.title,biblio.remainderoftitle) AS title,
            biblio.author, GROUP_CONCAT( DISTINCT $hbranch) AS branch, GROUP_CONCAT(DISTINCT items.itemcallnumber) AS itemcallnumber, GROUP_CONCAT(DISTINCT items.barcode) AS barcode,
            GROUP_CONCAT(DISTINCT $itype) AS itype, GROUP_CONCAT(DISTINCT items.itemnotes) AS itemnotes, MAX(items.itemnumber) AS itemnumber, items.biblionumber
       FROM items
 CROSS JOIN biblio USING (biblionumber)
 CROSS JOIN biblioitems USING (biblioitemnumber)";
} else {
	$query =
    "SELECT CONCAT_WS(' ',biblio.title,biblio.remainderoftitle) AS title,
            biblio.author, $hbranch, items.itemcallnumber, items.barcode,
            $itype, items.itemnotes, items.itemnumber, items.biblionumber
       FROM items
 CROSS JOIN biblio USING (biblionumber)
 CROSS JOIN biblioitems USING (biblioitemnumber)";
}
if ( @wheres ) {
    $query .= " WHERE ". join ' AND ', @wheres;
}
if ( $group ) {
    $query .= " GROUP BY $group";
}
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
				if ( $$cell{coltitle} =~ m|<a\s[^>]+>([^<]+)</a>| ) {
					$$cell{coltitle} = $1;
				}
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

	my @criteria = (
	    { value => 'itemnote', label => 'Copy Notes' },
	    { value => 'itemcall', label => 'Call Number' },
	    { value => 'awards', label => 'Award' },
	    { value => 'itemtype', label => 'Item Type' },
        { value => 'location', label => 'Shelving Location' },
	);
	push @parameters, {
	    select_box => 1,
	    select_loop => \@criteria,
	    label => "Criteria",
	    onchange => 'onchange=\'{
  var s_value = this.options[ this.selectedIndex ].value;
  var ids = [ "input_1", "input_2", "input_3" ];
  for ( var i = 0, l = ids.length; i < l; i++ ) {
    var s_block = document.getElementById(ids[i]);
    s_block.style.display = "none";
  }
  if ( s_value == "itemtype" ) {
    s_id = "input_2";
  } else if ( s_value == "location" ) {
    s_id = "input_3";
  } else {
    s_id = "input_1";
  }
  var s_block = document.getElementById(s_id);
  s_block.style.display = "list-item";
}\'',
	};

	push @parameters, {
	    input_box => 1,
	    label => "Search For",
	    li_id => 'input_1',
	};

	my $itemtypes = GetItemTypes();
	my @itemtypeloop;
	foreach my $thisitype ( sort keys %$itemtypes ) {
	    my %row = (
		value => $thisitype,
		label => $$itemtypes{ $thisitype }{'description'},
		);
	    push @itemtypeloop, \%row;
	}
	push @parameters, {
	    select_box => 1,
	    select_loop => \@itemtypeloop,
	    label => "Item Type",
	    first_blank => 1,
	    style => "display:none",
	    li_id => 'input_2',
	};

	my $locations = GetAuthorisedValues('LOC');
	my @locationsloop;
	foreach my $loc ( sort {$a->{'lib'} cmp $b->{'lib'} } @$locations ) {
	    my %row = (
		value => $loc->{'authorised_value'},
		label => $loc->{'lib'},
		);
	    push @locationsloop, \%row;
	}
	push @parameters, {
	    select_box => 1,
	    select_loop => \@locationsloop,
	    label => "Shelving Location",
	    first_blank => 1,
	    style => "display:none",
	    li_id => 'input_3',
	};

	push @parameters, {
	    check_box => 1,
	    label => "Show Only One Copy",
	    input_name => 'Option1',
	};

	my @order_loop;
	push @order_loop, { value => 'title', label => 'Title' };
	push @order_loop, { value => 'callnumber', label => 'Call Number' };
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
	my ($query, $column_titles, $qfilters) = @_;

	my $dbh = C4::Context->dbh;
	my @looprow;
	my @loopheader;
	my %globalline;
	my @mainloop;
	my $grantotal = 0;
	my @big_loop;
	my $break;
	my $break_index;

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

CALC_MAIN_LOOP:
	while ( my ( @values ) = $sth_col->fetchrow ) {
	    push @big_loop, \@values;
	}

	if ( $page_breaks ) {
	    $break = '__break__';
	    $break_index = $page_breaks - 1;
	}

	foreach my $data ( @big_loop ) {
	    my %row;
	    my @mapped_values;
        my @values = @$data;

	    if ( $break && $break ne $values[ $break_index ] ) {
            if ( $break ne '__break__' ) {
                $row{ 'break' } = 1;
            }
            $break = $values[ $break_index ];
	    }

	    foreach ( @values[ 0 .. $#$column_titles ] ) {
		push @mapped_values, { value => $_ };
	    }
	    $mapped_values[4]->{ 'link' } = "/cgi-bin/koha/cataloguing/additem.pl?op=edititem&biblionumber=". $values[8] ."&itemnumber=". $values[7];
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
