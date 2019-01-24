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
use C4::Debug;
use C4::Auth;
use C4::Output;
use C4::Branch;  # GetBranchesLoop GetBranchesWithProperty GetBranches
use C4::Reserves;  # GetReservesFromBorrowernumber
use C4::Members;  # MoveMemberToDeleted DelMember AddMember ModMember GetMemberIssuesAndFines

our $debug;
my $cgi = new CGI;

# getting the template
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "tools/external-member-sync.tmpl",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { tools => 1 },
    }
);

my @categories;
my $ldap_conn;
if ( C4::Context->config("MembersExternalEngine") ) {
    use C4::MembersExternal;  # GetMemberDetails_External ListMembers_External GetExternalMappedCategories
    push @categories, GetExternalMappedCategories();
}

if ( C4::Context->config("ldapserver") ) {
    my $ldap = C4::Context->config("ldapserver");
    my %mapping = %{$ldap->{mapping}};
    my @mapkeys = keys %mapping;

    if ( defined $mapping{categorycode}->{is} ) {
        unless ( $ldap_conn ) {
            my $prefhost = $ldap->{hostname};
            my $ldapname = $ldap->{user};
            my $ldappassword = $ldap->{pass};
            my @hosts = split(',', $prefhost);
            $ldap_conn = Net::LDAP->new(\@hosts);
            ($ldapname) ? $ldap_conn->bind($ldapname, password=>$ldappassword) : $ldap_conn->bind;
        }
        my $base = $ldap->{base};
        my $cat_field = $mapping{categorycode}->{is};
        my $filter_str = "($cat_field=*)";
        if ( $ldap->{filter} ) {
            $filter_str = "(&(".$ldap->{filter}.")$filter_str)";
        }
        my $filter = Net::LDAP::Filter->new($filter_str);
        my $search = $ldap_conn->search( base => $base, filter => $filter, attrs => [$cat_field] );
        if ( $search->code() ) { $debug && warn $search->error(); }
        my %unique_cat;
        while ( my $entry = $search->shift_entry ) {
            push @categories, $entry->get_value($cat_field);
        }
    }
    else {
        push @categories, $mapping{categorycode}->{content};
    }
}

# Make sure values in @categories are unique
{ my %h; @categories = grep {!$h{$_}++} @categories; }

my $dbh = C4::Context->dbh;
my $op     = $cgi->param( 'op' ) || '';
my $confirmed = $cgi->param( 'confirmed' ) || '';
my $branch = $cgi->param( 'branch' );
my $category = $cgi->param('category');

if ( $op eq 'Sync' and @categories ) {
#warn "Getting lists...";
    my $branches = GetBranches();
    my $historical_branch = GetBranchesWithProperty( 'HIST' );
    if ( @$historical_branch ) {
	$historical_branch = $$historical_branch[0];
    }
    else {
	$historical_branch = 0;
    }

    my ( $dbhash, $dirhash ) = ({},{});
    my $query = "SELECT * FROM borrowers";
    $query .= " WHERE branchcode = ". $dbh->quote( $branch ) if ( $branch );
    my $sth = $dbh->prepare( $query );
    $sth->execute();
    while ( my $data = $sth->fetchrow_hashref ) {
        $$data{cardnumber} =~ s/^\s*//;
        $$data{cardnumber} =~ s/\s*$//;
        $dbhash->{ $$data{cardnumber} } = $data;
    }
    if ( C4::Context->config("MembersExternalEngine") ) {
        $dirhash = ListMembers_External( $category, $branch );
        foreach my $card ( keys %$dirhash ) {
            my $attribs = GetMemberDetails_External( $card );
            $dirhash->{$card} = $attribs;
        }
    }
    if ( C4::Context->config("ldapserver") ) {
        require C4::Auth_with_ldap;
        use Net::LDAP::Control::Paged;
        use Net::LDAP::Constant qw( LDAP_CONTROL_PAGED );
        my $ldap = C4::Context->config("ldapserver");
        my $base = $ldap->{base};
        unless ( $ldap_conn ) {
            my $prefhost = $ldap->{hostname};
            my $ldapname = $ldap->{user};
            my $ldappassword = $ldap->{pass};
            my @hosts = split(',', $prefhost);
            $ldap_conn = Net::LDAP->new(\@hosts);
            ($ldapname) ? $ldap_conn->bind($ldapname, password=>$ldappassword) : $ldap_conn->bind;
        }
        my %mapping = %{$ldap->{mapping}};
        my @filters;
        my $filter_str;
        if ( defined $mapping{categorycode}->{is} ) {
            my $field = $mapping{categorycode}->{is};
            push @filters,"($field=$category)";
        }
        if ( $branch && defined $mapping{branchcode}->{is} ) {
            my $field = $mapping{branchcode}->{is};
            push @filters,"($field=$branch)";
        }
        if ( scalar @filters > 1 ) {
            $filter_str = "(&". (join "",@filters) .")";
        }
        else {
            $filter_str = $filters[0];
        }
        if ( $ldap->{filter} ) {
            $filter_str = "(&(".$ldap->{filter}.")$filter_str)";
        }
        my $filter = Net::LDAP::Filter->new($filter_str);
        my $paged = Net::LDAP::Control::Paged->new( size => 500 );
        while (1) {
            my $search = $ldap_conn->search( base => $base, filter => $filter, control => [ $paged ] );
            $search->code and last;
            while ( my $entry = $search->shift_entry ) {
                my %attribs = C4::Auth_with_ldap::ldap_entry_2_hash( $entry, undef );
                if ( $attribs{cardnumber} && $attribs{cardnumber} ne ' ' ) {
                    $dirhash->{$attribs{cardnumber}} = \%attribs;
                }
            }
            my ($response) = $search->control( LDAP_CONTROL_PAGED ) or last;
            my $cookie = $response->cookie or last;
            $paged->cookie($cookie);
        }
    }

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
	    my $bordata;
        if ( C4::Context->config("MembersExternalEngine") ) {
            $bordata = GetMemberDetails_External( $cardnumber )
        }
        if ( C4::Context->config("ldapserver") ) {
            my $ldap = C4::Context->config("ldapserver");
            my $base = $ldap->{base};
            unless ( $ldap_conn ) {
                my $prefhost = $ldap->{hostname};
                my $ldapname = $ldap->{user};
                my $ldappassword = $ldap->{pass};
                my @hosts = split(',', $prefhost);
                $ldap_conn = Net::LDAP->new(\@hosts);
                ($ldapname) ? $ldap_conn->bind($ldapname, password=>$ldappassword) : $ldap_conn->bind;
            }
            my %mapping = %{$ldap->{mapping}};
            if ( defined $mapping{cardnumber}->{is} ) {
                my $field = $mapping{cardnumber}->{is};
                my $filter_str = "($field=$cardnumber)";
                if ( $ldap->{filter} ) {
                    $filter_str = "(&(".$ldap->{filter}.")$filter_str)";
                }
                my $filter = Net::LDAP::Filter->new($filter_str);
                my $search = $ldap_conn->search( base => $base, filter => $filter );
                if ( $search->code() ) { $debug && warn $search->error(); }
                my $entry = $search->shift_entry;
                if ( $entry ) { %{$bordata} = C4::Auth_with_ldap::ldap_entry_2_hash( $entry, undef ); }
            }
        }
	    $$bordata{'surname'} ||= $$dbhash{$cardnumber}{'surname'};
	    $$bordata{'firstname'} ||= $$dbhash{$cardnumber}{'firstname'};
	    $$bordata{'cardnumber'} ||= $cardnumber;

	    my %this_report = (
		name => $$bordata{'surname'} .', '. $$bordata{'firstname'},
		cardnumber => $$bordata{'cardnumber'},
	    );

	    if ( $bordata && $$bordata{'branchcode'} && ( $$bordata{'branchcode'} != $branch ) ) {
		$allow_delete = 0;
		if ( $confirmed ) {
		    if ( $historical_branch && ! $$branches{$$bordata{'branchcode'}} ) {
			$branch_update->execute( $$historical_branch{'branchcode'}, $cardnumber );
		    } else {
			$branch_update->execute( $$bordata{'branchcode'}, $cardnumber )
		    }
		}
		#warn "Trying to change branch of $cardnumber to $$bordata{branchcode}";
		$this_report{moved} = 1;
	    }

	    # this prevents a delete when a patron has copies checked out
	    if ( $issues ) {
		 if ($allow_delete && $confirmed) { $gone_update->execute( $cardnumber ) };
		$allow_delete = 0;
		$this_report{issues} = 1;
	    }

	    # this prevents a delete when a patron has fines
	    if ( $fines != 0 ) {
		 if ($allow_delete && $confirmed) { $gone_update->execute( $cardnumber ) };
		$allow_delete = 0;
		$this_report{fines} = 1;
	    }

	    # this prevents a delete when a patron has reserves outstanding
	    if ( @reserves ) {
		 if ($allow_delete && $confirmed) { $gone_update->execute( $cardnumber ) };
		$allow_delete = 0;
		$this_report{reserves} = 1;
	    }

	    if ( $allow_delete ) { # || $historical_branch ) {
		$deleted{ $cardnumber } = 1;
	    }
        else {
            push @report, \%this_report;
        }
	}
    }
    foreach (sort keys %$dirhash) {
	if ( $$dbhash{ $_ } ) {
	    $existing{ $_ } = $dirhash->{$_};
	} else {
	    $added{ $_ } = $dirhash->{$_};
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

    $get = $dbh->prepare( "SELECT * FROM borrowers WHERE cardnumber = ? OR userid = ?" );
    # Handle new borrowers
#warn "Adding...";
    foreach my $cardnumber ( sort keys %added ) {
	my @fields;

	$get->execute( $cardnumber, $added{$cardnumber}{'userid'} );
	@fields = @{ $get->fetchall_arrayref({}) };
	$get->finish;

	if ( @fields ) {
	    # Cardnumber exists already.  Assume patron changed branches.
	    # This should be an update
        if ( $#fields > 1 ) {
            # To many rows returned
            push @report, {
                name => $added{$cardnumber}{'surname'} .', '. $added{$cardnumber}{'firstname'},
                cardnumber => $cardnumber,
                duplicate => 1,
            };
        }
        else {
            $existing{ $cardnumber } = $added{$cardnumber};
        }
	} else {
	    my $attribs = $added{$cardnumber};
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
	my $attribs = $existing{$cardnumber};
	$get->execute( $cardnumber, $existing{$cardnumber}{'userid'} );
	my $values = $get->fetchrow_hashref;
    my @changes;

	foreach ( keys %$attribs ) {
	    defined $$attribs{ $_ } &&
		$$attribs{ $_ } &&
		$$attribs{ $_ } =~ s/\s*$//;
	}
	unless ( $$attribs{ categorycode } ) {
	    $$attribs{ categorycode } = $category;
	}

	foreach ( sort keys %$values ) {
	    if ( exists $$attribs{ $_ } && defined $$attribs{ $_ } ) {
		if ( $_ eq 'password' ) {
		    if ( $$attribs{ $_ } ne $$values{ $_ } && $confirmed ) {
			changepassword( $$values{ 'userid' }, $$values{ 'borrowernumber' }, $$attribs{ 'password' } );
		    }
		    delete $$attribs{ 'password' };
		}
		elsif ( defined $$values{ $_ } ) {
		    if ( $$attribs{ $_ } ne $$values{ $_ } ) {
                $diff = 1;
                push @changes, { field => $_, old => $$values{$_}, new => $$attribs{$_} };
            }
		} else {
		    $diff = 1;
            push @changes, { field => $_, old => '', new => $$attribs{$_} };
		}
	    } elsif ( exists $$attribs{ $_ } ) {  # value is undefined.  Delete
		delete $$attribs{ $_ };
	    }
	}

	if ( $diff ) {
	    $$attribs{borrowernumber} = $$values{borrowernumber};

	    if ( $confirmed ) {
		if ( ! $$attribs{'gonenoaddress'} && $$values{'gonenoaddress'} ) {
		    $$attribs{'gonenoaddress'} = 0;
		}

		ModMember( %$attribs );
#warn "Updated $$attribs{cardnumber}";
	    }

	    push @report, {
		name => $$attribs{surname} .', '. $$attribs{firstname},
		cardnumber => $cardnumber,
		changed => \@changes,
	    };
	    $numchanged++;
	}
    }

    $template->param(
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
	);
}

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
