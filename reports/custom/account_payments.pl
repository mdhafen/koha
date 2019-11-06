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

my $reportname = "account_payments";
my $reporttitle = "Borrower Payments";
my @column_titles = ( "Date", "Patron", "Title", "Barcode", "Amount", "Credit Type", "Credit Description", "Fine Type", "Fine Description" );

my @wheres;

# Handle parameters
$CGI::LIST_CONTEXT_WARN=0;
my @filters = $input->param("Filter");

push @wheres, "al1.date >= ". $dbh->quote(C4::Dates->new( $filters[0] )->output('iso')) if ( $filters[0] );
push @wheres, "al1.date <= ". $dbh->quote(C4::Dates->new( $filters[1] )->output('iso')) if ( $filters[1] );

if ( my @types = $input->param("FineTypes") ) {
    my @t_wheres;
    for ( @types ) {
        ($_ eq 'F') && (push @t_wheres,("al2.accounttype = 'F'","al2.accounttype = 'FU'"));
        ($_ eq 'N') && (push @t_wheres,"al2.accounttype = 'N'");
        ($_ eq 'A') && (push @t_wheres,"al2.accounttype = 'A'");
        ($_ eq 'M') && (push @t_wheres,"al2.accounttype = 'M'");
        ($_ eq 'L') && (push @t_wheres,"al2.accounttype = 'L'");
        ($_ eq 'P') && (push @t_wheres,"al1.accounttype = 'Pay'");
        ($_ eq 'C') && (push @t_wheres,"al1.accounttype = 'C'");
        ($_ eq 'W') && (push @t_wheres,"al1.accounttype = 'W'");
        ($_ eq 'R') && (push @t_wheres,"al1.accounttype = 'REF'");
        ($_ eq 'O') && (push @t_wheres,"al1.accounttype = 'FOR'");
    }
    push @wheres, '('. (join ' OR ', @t_wheres) .')';
}

if ( C4::Context->preference("IndependantBranches") || $filters[2] ) {
    my $branch = ( C4::Context->preference('IndependantBranches') ) ? $userenv->{branch} : $filters[2];
    my $hbranch = C4::Context->preference('HomeOrHoldingBranch') eq 'homebranch' ? 'items.homebranch' : 'items.holdingbranch';
    push @wheres, "( $hbranch = ". $dbh->quote( $branch ) ." OR $hbranch IS NULL )";
    push @wheres, "branchcode = ". $dbh->quote( $branch );
}

my $query = "SELECT al1.date, CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron, CONCAT_WS(' ',biblio.title,biblio.seriestitle) AS title, items.barcode, al1.amount,al1.accounttype AS CreditType, al1.description AS CreditDescription, al2.accounttype AS FineType, al2.description AS FineDescription, al1.borrowernumber FROM accountlines AS al1 LEFT JOIN borrowers USING (borrowernumber) LEFT JOIN items USING (itemnumber) LEFT JOIN biblio USING (biblionumber) LEFT JOIN accountoffsets AS ao ON al1.borrowernumber = ao.borrowernumber AND al1.accountno = ao.offsetaccount LEFT JOIN accountlines AS al2 ON ao.borrowernumber = al2.borrowernumber AND ao.accountno = al2.accountno WHERE al1.amount < 0 ";
if ( @wheres ) {
    $query .= ' AND '. (join ' AND ', @wheres);
}
$query .= " ORDER BY patron";

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
	my @parameters;

	my $today = C4::Dates->today();
	push @parameters, {
	    calendar => 1,
	    label => "Credits Added Since",
	    id => "creditstartdate",
	    value => $today,
	};
	push @parameters, {
	    calendar => 1,
	    label => "Credits Added Before",
	    id => "creditenddate",
	    value => $today,
	};

    my @fine_types_loop = (
        { value => 'F', label => 'Late Fine' },
        { value => 'N', label => 'New Card Fee' },
        { value => 'A', label => 'Account Management Fee' },
        { value => 'M', label => 'Sundry' },
        { value => 'L', label => 'Lost Item' },
        { value => 'P', label => 'Payment' },
        { value => 'C', label => 'Credit' },
        { value => 'W', label => 'Write-off' },
        { value => 'R', label => 'Refund' },
        { value => 'O', label => 'Forgiven' },
    );
	push @parameters, {
	    select_box => 1,
	    select_loop => \@fine_types_loop,
	    label => "Fine/Credit Types",
	    input_name => 'FineTypes',
	    size => 5,
	    multiple => 1,
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
	    DHTMLcalendar_dateformat => C4::Dates->DHTMLcalendar(),
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
    my $total = 0;

	my $sth_col = $dbh->prepare( $query );
	$sth_col->execute();

	while ( my ( @values ) = $sth_col->fetchrow ) {
		my %row;
		my @mapped_values;

        for ( $values[5],$values[7] ) {
            ($_ eq 'F') && ($_ = "Late Fine");
            ($_ eq 'FU') && ($_ = "Late Fine");
            ($_ eq 'N') && ($_ = "New Card Fee");
            ($_ eq 'A') && ($_ = "Account Management Fee");
            ($_ eq 'M') && ($_ = "Sundry");
            ($_ eq 'L') && ($_ = "Lost Item");
            ($_ eq 'Pay') && ($_ = "Payment");
            ($_ eq 'C') && ($_ = "Credit");
            ($_ eq 'W') && ($_ = "Write-off");
            ($_ eq 'REF') && ($_ = "Refund");
            ($_ eq 'FOR') && ($_ = "Forgiven");
        }

		push @mapped_values, (
		    { value => $values[0] }, # Date format?
		    { value => $values[1], link => "/cgi-bin/koha/members/boraccount.pl?borrowernumber=".$values[9] },
		    { value => $values[2] },
		    { value => $values[3] },
		    { value => sprintf("%.2f",$values[4]) },
		    { value => $values[5] },
		    { value => $values[6] },
		    { value => $values[7] },
		    { value => $values[8] },
        );

		$row{ 'values' } = \@mapped_values;
		push @looprow, \%row;
        $total += $values[4];
	}
    push @looprow, {
        'values' => [
            {
                'width' => @$column_titles - 1,
                'value' => 'Total',
                'header' => 1,
            },
            {
                'value' => sprintf( "%.2f", $total * -1),
                'header' => 1,
            }
        ]
    };

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
