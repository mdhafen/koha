#!/usr/bin/perl

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
#
#   Written by Michael Hafen mdhafen@washk12.org on Mar. 2008


=head1 external-member-sync.pl

This script get patron lists which are pulled from the Koha database and from an external database, and compares the two.

=cut

use strict;
use CGI;
use C4::Auth;
use C4::Output;
use C4::Branch;  # GetBranches
use C4::Reserves;  # GetReservesFromBorrowernumber
use C4::Members;  # MoveMemberToDeleted DelMember AddMember ModMember GetMemberIssuesAndFines GetborCatFromCatType
use C4::MembersExternal;  # GetMemberDetails_External ListMembers_External

my $cgi = new CGI;

# getting the template
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "tools/external-member-sync.tmpl",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { management => 1, tools => 1 },
    }
);

my $dbh = C4::Context->dbh;
my $op     = $cgi->param( 'op' );
my $branch = $cgi->param( 'branch' );
my $category = $cgi->param('category');

if ( $op eq 'Sync' and C4::Context->preference('MembersViaExternal') ) {
#warn "Getting lists...";
    my ( $dbhash, $dirhash ) = ListMembers_External( $category, $branch );
    my ( %deleted, %added, %existing );
    my ( $numdeleted, $numadded, $numchanged ) = ( "0", "0", "0" );
    my ( $total );
    my @report;

    my $branch_update = $dbh->prepare( "UPDATE borrowers SET branchcode = ? WHERE cardnumber = ?" );

    # Check for differences borrowers
    #  Check for patrons not in external, and in category
#warn "checking for deletes...";
    if ( %$dirhash ) {  # to make sure the directory isn't empty.
	foreach (sort keys %$dbhash) {
	    next if ( $$dbhash{$_}{categorycode} ne $category );
	    next if ( $$dirhash{$_} );

	    my $allow_delete = 1;

	    my $borrnum = $$dbhash{$_}{borrowernumber};
	    my ( $issues, undef, $fines ) = GetMemberIssuesAndFines( $borrnum );
	    my ( @reserves ) = GetReservesFromBorrowernumber( $borrnum );

	    # this prevents a delete when a patron has changed branches
	    my $bordata = GetMemberDetails_External( $_ );
	    if ( %$bordata && ( $$bordata{'branchcode'} != $branch ) ) {
		$allow_delete = 0;
		$branch_update->execute( $$bordata{'branchcode'}, $_ );
#		warn "Trying to change branch of $_ to $$bordata{branchcode}";
		push @report, {
		    name => $$bordata{'surname'} .', '. $$bordata{'firstname'},
		    cardnumber => $$bordata{'cardnumber'},
		    moved => 1,
		};
	    }

	    # this prevents a delete when a patron has copies checked out
	    if ( $issues ) {
		$allow_delete = 0;
		push @report, {
		    name => $$bordata{'surname'} .', '. $$bordata{'firstname'},
		    cardnumber => $_,
		    issues => 1,
		};
	    }

	    # this prevents a delete when a patron has fines
	    if ( $fines != 0 ) {
		$allow_delete = 0;
		push @report, {
		    name => $$bordata{'surname'} .', '. $$bordata{'firstname'},
		    cardnumber => $_,
		    fines => 1,
		};
	    }

	    # this prevents a delete when a patron has reserves outstanding
	    if ( @reserves ) {
		$allow_delete = 0;
		push @report, {
		    name => $$bordata{'surname'} .', '. $$bordata{'firstname'},
		    cardnumber => $_,
		    reserves => 1,
		}
	    }

	    if ( $allow_delete ) {
		$deleted{ $_ } = 1;
	    }
	}
    }
    foreach (sort keys %$dirhash) {
	if ( $$dbhash{ $_ } ) {
	    $existing{ $_ } = 1;
	} else {
	    $added{ $_ } = 1;
	}
	$total++;
    }

    undef $dbhash;  # free memory
    undef $dirhash;

    # DB Queries
    my $get = $dbh->prepare( "SELECT borrowernumber, cardnumber, surname, firstname, othernames, branchcode, categorycode FROM borrowers WHERE cardnumber = ?" );

    # Handle deleted borrowers
#warn "Deleting...";
    foreach my $cardnumber ( sort keys %deleted ) {
	$get->execute( $cardnumber );
	my ( @fields ) = $get->fetchrow;
	$get->finish;

	MoveMemberToDeleted( $fields[0] );
	DelMember( $fields[0] );

	$numdeleted++;
	push @report, {
	    name => $fields[2] .', '. $fields[3],
	    cardnumber => $cardnumber,
	    deleted => 1,
	};
    }

    # Handle new borrowers
#warn "Adding...";
    foreach my $cardnumber ( sort keys %added ) {
	my @fields;

	$get->execute( $cardnumber );
	( @fields ) = $get->fetchrow;
	$get->finish;

	if ( @fields ) {
	    # Cardnumber exists already.  Assume patron changed branches.
	    # This should be an update
	    $existing{ $cardnumber } = 1;
	} else {
	    my $attribs = GetMemberDetails_External( $cardnumber, $category );
	    foreach my $attr ( keys %$attribs ) {
		$$attribs{$attr} =~ s/\s*$//;
	    }
	    $$attribs{categorycode} = $category;
	    AddMember( %$attribs );

	    push @report, {
		name => $$attribs{surname} .', '. $$attribs{firstname},
		cardnumber => $cardnumber,
		added => 1,
	    };
	    $numadded++;
	}
    }

    # Check all others for updates.  This could take a while.
#warn "Starting update check...";
    foreach my $cardnumber ( sort keys %existing ) {
	my ( $diff, @fields );
	my $attribs = GetMemberDetails_External( $cardnumber );
	$get->execute( $cardnumber );
	my $values = $get->fetchrow_hashref;

	foreach ( keys %$attribs ) {
	    $$attribs{ $_ } =~ s/\s*$//; # this is because of stupid secretaries
	}
	unless ( $$attribs{ categorycode } ) {
	    $$attribs{ categorycode } = $category;
	}

	$diff = 1 if ( $$attribs{ 'cardnumber' } ne $$values{ 'cardnumber' } );
	$diff = 1 if ( $$attribs{ 'surname' } ne $$values{ 'surname' } );
	$diff = 1 if ( $$attribs{ 'firstname' } ne $$values{ 'firstname' } );
	$diff = 1 if ( $$attribs{ 'othernames' } ne $$values{ 'othernames' } );
	$diff = 1 if ( $$attribs{ 'branchcode' } ne $$values{ 'branchcode' } );
	$diff = 1 if ( $$attribs{ 'categorycode' } ne $$values{ 'categorycode' } );

	if ( $diff ) {
	    $$attribs{borrowernumber} = $$values{borrowernumber};
	    unless ( $$attribs{ 'categorycode' } ) {
		delete $$attribs{ 'categorycode' };  # foreign key constraint
	    }

	    ModMember( %$attribs );
#warn "Updated $$attribs{cardnumber}";

	    push @report, {
		name => $$attribs{surname} .', '. $$attribs{firstname},
		cardnumber => $cardnumber,
		changed => 1,
	    };
	    $numchanged++;
	}
    }

    $template->param(
		     op => $op,
		     num_deleted => $numdeleted,
		     num_added => $numadded,
		     num_changed => $numchanged,
		     total => $total,
		     report => \@report,
		     );
} else {
#get Branches
    my @branches;
    my @select_branch;
    my %select_branches;

    my $onlymine=(C4::Context->preference('IndependantBranches') &&
		  C4::Context->userenv &&
		  C4::Context->userenv->{flags} !=1  &&
		  C4::Context->userenv->{branch}?1:0);

    my $branches = GetBranches( $onlymine );
    my $default;


    foreach my $branch ( sort keys %$branches ) {
	push @select_branch, $branch;
	$select_branches{$branch} = $branches->{$branch}->{'branchname'};
	$default = C4::Context->userenv->{'branch'} if ( C4::Context->userenv && C4::Context->userenv->{'branch'} );
    }
    my $CGIbranch = CGI::scrolling_list(-id    => 'branch',
					-name   => 'branch',
					-values => \@select_branch,
					-labels => \%select_branches,
					-size   => 1,
					-override => 1,
					-multiple =>0,
					-default => $default,
        );

    my @typeloop;
    foreach (qw(C A S P I)){
	my $action="WHERE category_type=?";
	my ( $categories, $labels ) = GetborCatFromCatType( $_, $action );
	my @categoryloop;
	foreach my $cat ( @$categories ){
	    push @categoryloop,{'categorycode' => $cat,
				'categoryname' => $labels->{$cat},
	    };
	}
	my %typehash;
	$typehash{'typename'} = $_;
	$typehash{'categoryloop'} = \@categoryloop;
	push @typeloop,{'typename' => $_,
			'categoryloop' => \@categoryloop};
    }

    $template->param(
	'branchCGI' => $CGIbranch,
	'typeloop' => \@typeloop,
	);
}

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
