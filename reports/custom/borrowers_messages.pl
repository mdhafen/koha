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

my $reportname = "borrowers_messages";
my $reporttitle = "Borrower Messages";
my @column_titles = ( "Patron", "Cardnumber", "Date", "From", "For", "Message", "Action" );

my $where = '';

# Handle parameters
my @filters = $input->param("Filter");

if ( C4::Context->preference("IndependantBranches") || $filters[0] ) {
    my $branch = ( C4::Context->preference('IndependantBranches') ) ? $userenv->{branch} : $filters[0];
    if ( C4::Context->preference('AllowAllMessageDeletion') ) {
        $where = "borrowers.branchcode = ".$dbh->quote( $branch )." OR messages.branchcode = ".$dbh->quote( $branch );
    }
    else {
        $where = "messages.branchcode = ". $dbh->quote( $branch );
    }
}

my $query = 
   "SELECT CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron,
           cardnumber, message_date, messages.branchcode,
           IF( message_type = 'B', 'Borrower', 'Librarian' ), message,
           message_id, borrowernumber
      FROM messages
CROSS JOIN borrowers USING (borrowernumber)";
if ( $where ) {
    $query .= "WHERE $where"
}
$query .= "ORDER BY patron";

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
            { value => $data->[0] },
            { value => $data->[1] },
            { value => $data->[2] },
            { value => $data->[3] },
            { value => $data->[4] },
            { value => $data->[5] };

            if ( $output eq 'screen' ) {
                push @mapped_values, {
                    value => 'Delete',
                    link => "/cgi-bin/koha/circ/del_message.pl?message_id=".$data->[6]."&borrowernumber=".$data->[7],
                }
            }

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
