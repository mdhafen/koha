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
#   Written by Michael Hafen mdhafen@tech.washk12.org on Mar. 2008


=head1 external-member-sync.pl

This script get patron lists which are pulled from the Koha database and from an external database, and compares the two.

=cut

use strict;
use warnings;
use CGI;
use C4::Auth;
use C4::Output;
use C4::Branch;  # GetBranchesLoop GetBranchesWithProperty
use C4::Reserves;  # GetReservesFromBorrowernumber
use C4::Members;  # MoveMemberToDeleted DelMember AddMember ModMember GetMemberIssuesAndFines
use C4::MembersExternal;  # GetMemberDetails_External ListMembers_External GetExternalMappedCategories

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
my $op     = $cgi->param( 'op' ) || '';
my $confirmed = $cgi->param( 'confirmed' ) || '';
my $branch = $cgi->param( 'branch' );
my $category = $cgi->param('category');
my @categories = GetExternalMappedCategories();

if ( $op eq 'Sync' and @categories ) {
#warn "Getting lists...";
    my $historical_branch = GetBranchesWithProperty( 'HIST' );
    if ( @$historical_branch ) {
	$historical_branch = $$historical_branch[0];
    }
    else {
	$historical_branch = 0;
    }

    my ( $dbhash, $dirhash ) = ListMembers_External( $category, $branch );
    my ( %deleted, %added, %existing );
    my ( $numdeleted, $numadded, $numchanged ) = ( "0", "0", "0" );
    my ( $total );
    my @report;

    my $branch_update = $dbh->prepare( "UPDATE borrowers SET branchcode = ? WHERE cardnumber = ?" );
    my $gone_update = $dbh->prepare( "UPDATE borrowers SET gonenoaddress = 1 WHERE cardnumber = ?" );

    # Check for differences borrowers
    #  Check for patrons not in external, and in category
#warn "checking for deletes...";
    if ( $dirhash && %$dirhash ) {  # to make sure the directory isn't empty.
	foreach my $cardnumber (sort keys %$dbhash) {
	    next if ( $$dbhash{$cardnumber}{categorycode} ne $category );
	    next if ( $$dirhash{$cardnumber} );

	    my $allow_delete = 1;

	    my $borrnum = $$dbhash{$cardnumber}{borrowernumber};
	    my ( undef, $issues, $fines ) = GetMemberIssuesAndFines( $borrnum );
	    my ( @reserves ) = GetReservesFromBorrowernumber( $borrnum );
	    $fines += 0;  #  Force to number

	    # this prevents a delete when a patron has changed branches
	    my $bordata = GetMemberDetails_External( $cardnumber );
	    $$bordata{'surname'} ||= '';
	    $$bordata{'firstname'} ||= '';

	    my %this_report = (
		name => $$bordata{'surname'} .', '. $$bordata{'firstname'},
		cardnumber => $$bordata{'cardnumber'},
	    );

	    if ( $bordata && $$bordata{'branchcode'} && ( $$bordata{'branchcode'} != $branch ) ) {
		$allow_delete = 0;
		$branch_update->execute( $$bordata{'branchcode'}, $cardnumber );
		#warn "Trying to change branch of $cardnumber to $$bordata{branchcode}";
		push @report, {
		    name => $$bordata{'surname'} .', '. $$bordata{'firstname'},
		    cardnumber => $$bordata{'cardnumber'},
		    moved => 1,
		};
	    }

	    # this prevents a delete when a patron has copies checked out
	    if ( $issues ) {
		$gone_update->execute( $cardnumber ) if ($allow_delete);
		$allow_delete = 0;
		$this_report{issues} = 1;
	    }

	    # this prevents a delete when a patron has fines
	    if ( $fines != 0 ) {
		$gone_update->execute( $cardnumber ) if ($allow_delete);
		$allow_delete = 0;
		$this_report{fines} = 1;
	    }

	    # this prevents a delete when a patron has reserves outstanding
	    if ( @reserves ) {
		$gone_update->execute( $cardnumber ) if ($allow_delete);
		$allow_delete = 0;
		$this_report{reserves} = 1;
	    }

	    if ( $allow_delete ) { # || $historical_branch ) {
		push @report, \%this_report;
		$deleted{ $cardnumber } = 1;
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
    my $get = $dbh->prepare( "SELECT * FROM borrowers WHERE cardnumber = ?" );

    # Handle deleted borrowers
#warn "Deleting...";
    foreach my $cardnumber ( sort keys %deleted ) {
	$get->execute( $cardnumber );
	my ( @fields ) = $get->fetchrow;
	$get->finish;

	my $action = ( $historical_branch ) ? 'historical' : 'deleted';

	if ( $confirmed ) {
	    if ( $historical_branch ) {
		$branch_update->execute( $$historical_branch{'branchcode'}, $cardnumber );
	    } else {
		MoveMemberToDeleted( $fields[0] );
		DelMember( $fields[0] );
	    }
	}

	$numdeleted++;
	push @report, {
	    name => $fields[2] .', '. $fields[3],
	    cardnumber => $cardnumber,
	    $action => 1,
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
		$$attribs{$attr} =~ s/\s*$// if ( $$attribs{$attr} );
	    }
	    $$attribs{categorycode} = $category;
	    $$attribs{'dateenrolled'} = C4::Dates->today('iso');
	    $$attribs{'dateexpiry'} = GetExpiryDate( $category, $$attribs{'dateenrolled'} );
	    my $mandatory_fields = C4::Context->preference("BorrowerMandatoryField");
	    my @check_fields = split( /\|/, $mandatory_fields );
	    # Mandatory Fields
	    foreach ( 'surname', 'address', 'city', @check_fields ) {
		unless ( exists $$attribs{ $_ } && defined $$attribs{ $_ } ) {
		    $$attribs{ $_ } = '';
		}
	    }

	    if ( $confirmed ) {
		my ( $password, $borrno );
		if ( $$attribs{ 'password' } ) {
		    $password = $$attribs{ 'password' };
		    delete $$attribs{ 'password' };
		}
		$borrno = AddMember( %$attribs );
		if ( $password ) {
		    changepassword( $$attribs{ 'userid' }, $borrno, $password );
		}
	    }

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
	    defined $$attribs{ $_ } &&
		$$attribs{ $_ } &&
		$$attribs{ $_ } =~ s/\s*$//;
	}
	unless ( $$attribs{ categorycode } ) {
	    $$attribs{ categorycode } = $category;
	}

	foreach ( keys %$values ) {
	    if ( exists $$attribs{ $_ } && defined $$attribs{ $_ } ) {
		if ( $_ eq 'password' ) {
		    if ( $$attribs{ $_ } ne $$values{ $_ } && $confirmed ) {
			changepassword( $$values{ 'userid' }, $$values{ 'borrowernumber' }, $$attribs{ 'password' } );
		    }
		    delete $$attribs{ 'password' };
		}
		elsif ( defined $$values{ $_ } ) {
		    $diff = 1 if ( $$attribs{ $_ } ne $$values{ $_ } );
		} else {
		    $diff = 1;
		}
	    } elsif ( exists $$attribs{ $_ } ) {  # value is undefined.  Delete
		delete $$attribs{ $_ };
	    }
	}

	if ( $diff ) {
	    $$attribs{borrowernumber} = $$values{borrowernumber};

	    if ( $confirmed ) {
		ModMember( %$attribs );
#warn "Updated $$attribs{cardnumber}";
	    }

	    push @report, {
		name => $$attribs{surname} .', '. $$attribs{firstname},
		cardnumber => $cardnumber,
		changed => 1,
	    };
	    $numchanged++;
	}
    }

    $template->param(
		     categories => scalar @categories,
		     op => $op,
		     branch => $branch,
		     categorycode => $category,
		     finished => $confirmed,
		     confirm => !$confirmed,
		     num_deleted => $numdeleted,
		     num_added => $numadded,
		     num_changed => $numchanged,
		     total => $total,
		     report => \@report,
		     );
} else {
#get Branches
    my $branches = GetBranchesLoop();

    my @categoryloop;
    foreach my $cat ( @categories ) {
	my $category = &GetBorrowercategory( $cat );
	push @categoryloop, {
	    categorycode => $cat,
	    categoryname => $category->{description},
	};
    }

    $template->param(
	'branchloop' => $branches,
	'categoryloop' => \@categoryloop,
        'categories' => scalar @categories,
	);
}

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
