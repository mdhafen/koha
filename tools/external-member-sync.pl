#!/usr/bin/perl

# This file is part of Koha.
#
# Copyright (C) 2021 Washington County School District
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.
#

#
# external-member-sync.pl
#
#   Written by Michael Hafen michael.hafen@washk12.org on Mar. 2008
#    updated May 2021
#
# This script get patron lists which are pulled from the Koha database
#  and from an external database, and compares the two.

use Modern::Perl;
use CGI qw ( -utf8 );

use C4::Auth qw( get_template_and_user );;
use C4::Output qw( output_html_with_http_headers );
use C4::Members::Messaging;  # SetMessagingPreferencesFromDefaults

use Koha::DateUtils;  # output_pref
use Koha::Patrons;  #  AddMember ModMember move_to_deleted delete account checkounts holds
use Koha::Patron::Categories;
use Koha::Libraries;  # GetBranchesLoop GetBranches
use Koha::Library::Group;  # GetBranchesWithProperty

our $debug;
my $cgi = CGI->new;

# getting the template
my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name   => "tools/external-member-sync.tt",
        query           => $cgi,
        type            => "intranet",
        authnotrequired => 0,
        flagsrequired   => { tools => 'import_patrons' },
    }
);

my @categories;
my $ldap_conn;
if ( my $me_filename = C4::Context->config("MembersExternalModuleFilename") ) {
    require "C4/$me_filename.pm";  # GetMemberDetails_External ListMembers_External GetExternalMappedCategories
    push @categories, C4::MembersExternal::GetExternalMappedCategories();
}

if ( C4::Context->config("ldapserver") ) {
    use Net::LDAP::Control::Paged;
    use Net::LDAP::Constant qw( LDAP_CONTROL_PAGED );
    my $ldap = C4::Context->config("ldapserver");
    my %mapping = %{$ldap->{mapping}};
    my @mapkeys = keys %mapping;

    if ( defined $mapping{categorycode}->{is} ) {
        my %categorycode_conversions;
        my $default_categorycode;
        if(defined $ldap->{categorycode_mapping}) {
            $default_categorycode = $ldap->{categorycode_mapping}->{default};
            foreach my $cat (@{$ldap->{categorycode_mapping}->{categorycode}}) {
                $categorycode_conversions{$cat->{value}} = $cat->{content};
            }
        }

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
            $filter_str = "(&".$ldap->{filter}."$filter_str)";
        }
        my $filter = Net::LDAP::Filter->new($filter_str);
        my $paged = Net::LDAP::Control::Paged->new( size => 500 );
        while (1) {
            my $search = $ldap_conn->search( base => $base, filter => $filter, attrs => [$cat_field], control => [ $paged ] );
            if ( $search->code() ) { $debug && warn $search->error(); last; }
            while ( my $entry = $search->shift_entry ) {
                my $code = $entry->get_value($cat_field);
                if ( defined $categorycode_conversions{$code} ) {
                    $code = $categorycode_conversions{$code};
                }
                elsif ( !$code && $default_categorycode ) {
                    $code = $default_categorycode;
                }
                push @categories, $code;
            }
            my ($response) = $search->control( LDAP_CONTROL_PAGED ) or last;
            my $cookie = $response->cookie or last;
            $paged->cookie($cookie);
        }
    }
    else {
        push @categories, $mapping{categorycode}->{content};
    }
}

# Make sure values in @categories are unique
{ my %h; @categories = sort grep {!$h{$_}++} @categories; }

my $dbh = C4::Context->dbh;
my $op     = $cgi->param( 'op' ) || '';
my $confirmed = $cgi->param( 'confirmed' ) || '';
my $branch = $cgi->param( 'branch' );
my $category = $cgi->param('category');
my $branch_filter = C4::Context->only_my_library() ? { branchcode => C4::Context->userenv->{'branch'} } : {};
my $branches = Koha::Libraries->search($branch_filter, { order_by => ['branchname'] } )->unblessed;
my %branches_map = map { $_->{branchcode} => $_ } @$branches;

my $no_msg_branches = {};
{
    my @b_group = Koha::Library::Groups->search( { title => 'NoMessaging' } );
    if ( @b_group && $b_group[0]->children ) {
        @b_group = $b_group[0]->children;
        foreach my $b ( @b_group ) {
            $no_msg_branches->{$b->branchcode} = 1;
        }
    }
}
my $clear_msg_prefs_sth = $dbh->prepare('DELETE FROM borrower_message_preferences WHERE borrowernumber = ?');

if ( $op eq 'Sync' and @categories ) {
#warn "Getting lists...";
    my @b_group = Koha::Library::Groups->search( { title => 'Historical' } );
    my $historical_branch;
    if ( @b_group && $b_group[0]->children ) {
        @b_group = $b_group[0]->children;
        $historical_branch = $b_group[0];
    }
    else {
        $historical_branch = 0;
    }

    my ( $dbhash, $dirhash ) = ({},{});
    my ( $query, @query_params );
    if ( $branch ) {
        $query = '
SELECT *
FROM borrowers
WHERE branchcode = ?
';
        @query_params = ($branch);
    }
    else {
        $query = '
SELECT *
FROM borrowers
';
    }
    my $sth = $dbh->prepare( $query );
    $sth->execute(@query_params);
    while ( my $data = $sth->fetchrow_hashref ) {
        $data->{cardnumber} =~ s/^\s*//;
        $data->{cardnumber} =~ s/\s*$//;
        $dbhash->{ $data->{cardnumber} } = $data;
    }
    if ( C4::Context->config("MembersExternalModuleFilename") ) {
        $dirhash = C4::MembersExternal::ListMembers_External({ 'category' => $category, 'branch' => $branch });
        foreach my $card ( keys %$dirhash ) {
            my $attribs = C4::MembersExternal::GetMemberDetails_External({ 'cardnumber' => $card });
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
            my $search_cat = $category;
            my %cat_con;
            if(defined $ldap->{categorycode_mapping}) {
                foreach my $cat (@{$ldap->{categorycode_mapping}->{categorycode}}) {
                    $cat_con{$cat->{content}} = $cat->{value};
                }
                if ( $cat_con{$category} ) {
                    $search_cat = $cat_con{$category};
                }
            }
            push @filters,"($field=$search_cat)";
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
            $filter_str = "(&".$ldap->{filter}."$filter_str)";
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
    my ( $numdeleted, $numadded, $numchanged, $total ) = ( 0, 0, 0, 0 );
    my @report;

    $query = '
UPDATE borrowers
SET branchcode = ?
WHERE cardnumber = ?
';
    my $branch_update = $dbh->prepare($query);

    # Check for differences borrowers
    #  Check for patrons not in external, and in category
#warn "checking for deletes...";
    if ( $dirhash && %$dirhash ) {  # to make sure the directory isn't empty.
        foreach my $cardnumber (sort keys %$dbhash) {
            next if ( $dbhash->{$cardnumber}{categorycode} ne $category );
            next if ( $dirhash->{$cardnumber} );

            my $allow_delete = 1;

            my $borrnum = $dbhash->{$cardnumber}{borrowernumber};
            my $patron = Koha::Patrons->find( $borrnum );
            my $num_issues = $patron->checkouts->count;
            my $fines = $patron->account->balance;
            my $num_reserves = $patron->holds->count;
            $fines += 0;  #  Force to number

            # this prevents a delete when a patron has changed branches
            my $bordata = {};
            if ( C4::Context->config("MembersExternalModuleFilename") ) {
                $bordata = C4::MembersExternal::GetMemberDetails_External({ 'cardnumber' => $cardnumber });
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
                        $filter_str = "(&".$ldap->{filter}."$filter_str)";
                    }
                    my $filter = Net::LDAP::Filter->new($filter_str);
                    my $search = $ldap_conn->search( base => $base, filter => $filter );
                    if ( $search->code() ) { $debug && warn $search->error(); }
                    my $entry = $search->shift_entry;
                    if ( $entry ) { %$bordata = C4::Auth_with_ldap::ldap_entry_2_hash( $entry, undef ); }
                }
            }
            $bordata->{'surname'} ||= $dbhash->{$cardnumber}{'surname'};
            $bordata->{'firstname'} ||= $dbhash->{$cardnumber}{'firstname'};
            $bordata->{'cardnumber'} ||= $cardnumber;

            my %this_report = (
                name => $bordata->{'surname'} .', '. $bordata->{'firstname'},
                cardnumber => $bordata->{'cardnumber'},
                );

            if ( $bordata && $bordata->{'branchcode'} && ( $bordata->{'branchcode'} != $branch ) ) {
                $allow_delete = 0;
                if ( $confirmed ) {
                    if ( $historical_branch && ! $branches_map{$bordata->{'branchcode'}} ) {
                        $branch_update->execute( $historical_branch->branchcode, $cardnumber );
                        if (C4::Context->preference('EnhancedMessagingPreferences')) {
                            $clear_msg_prefs_sth->execute($dbhash->{$cardnumber}{'borrowernumber'});
                        }
                    } else {
                        $branch_update->execute( $bordata->{'branchcode'}, $cardnumber );
                        if (C4::Context->preference('EnhancedMessagingPreferences')) {
                            if ( $no_msg_branches->{$dbhash->{$cardnumber}{'branchcode'}} && ! $no_msg_branches->{$bordata->{'branchcode'}} ) {
                                C4::Members::Messaging::SetMessagingPreferencesFromDefaults({ borrowernumber => $dbhash->{$cardnumber}{'borrowernumber'}, categorycode => $category });
                            }
                            elsif ( $no_msg_branches->{$bordata->{'branchcode'}} ) {
                                $clear_msg_prefs_sth->execute($dbhash->{$cardnumber}{'borrowernumber'});
                            }
                        }
                    }
                }
                #warn "Trying to change branch of $cardnumber to $bordata->{branchcode}";
                $this_report{moved} = 1;
            }

            # this prevents a delete when a patron has copies checked out
            if ( $num_issues ) {
                $allow_delete = 0;
                $this_report{issues} = 1;
            }

            # this prevents a delete when a patron has fines
            if ( $fines != 0 ) {
                $allow_delete = 0;
                $this_report{fines} = 1;
            }

            # this prevents a delete when a patron has reserves outstanding
            if ( $num_reserves ) {
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
        if ( $dbhash->{$_} ) {
            $existing{$_} = $dirhash->{$_};
        } else {
            $added{ $_ } = $dirhash->{$_};
        }
        $total++;
    }

    undef $dbhash;  # free memory
    undef $dirhash;

    # DB Queries
    $query = '
SELECT *
FROM borrowers
WHERE cardnumber = ?
';
    my $get = $dbh->prepare($query);

    # Handle deleted borrowers
    #warn "Deleting...";
    foreach my $cardnumber ( sort keys %deleted ) {
        $get->execute( $cardnumber );
        my $fields = $get->fetchrow_hashref;
        $get->finish;

        my $action = ( $historical_branch ) ? 'historical' : 'deleted';

        if ( $confirmed ) {
            if ( $historical_branch ) {
                $branch_update->execute($historical_branch->branchcode,$cardnumber);
                if (C4::Context->preference('EnhancedMessagingPreferences')) {
                    $clear_msg_prefs_sth->execute( $fields->{'borrowernumber'} );
                }
            } else {
                my $patron = Koha::Patrons->find( $fields->{'borrowernumber'} );
                $patron->move_to_deleted();
                $patron->delete();
            }
        }

        $numdeleted++;
        push @report, {
            name => $fields->{'surname'} .', '. $fields->{'firstname'},
            cardnumber => $cardnumber,
            $action => 1,
        };
    }

    $query = '
SELECT *
FROM borrowers
WHERE cardnumber = ?
  OR userid = ?
';
    $get = $dbh->prepare($query);
    # Handle new borrowers
#warn "Adding...";
    foreach my $cardnumber ( sort keys %added ) {
        my @fields;

        $get->execute( $cardnumber, $added{$cardnumber}{'userid'} );
        @fields = @{ $get->fetchall_arrayref({}) };
        $get->finish;

        if ( @fields ) {
            # userid exists already.
            # Assume patron changed branches and update.
            if ( $#fields > 1 ) {
                # To many rows returned
                push @report, {
                    name => $added{$cardnumber}{'surname'} .', '. $added{$cardnumber}{'firstname'},
                    cardnumber => $cardnumber,
                    duplicate => 1,
                };
            }
            else {
                $existing{$cardnumber} = $added{$cardnumber};
            }
        } else {
            my $attribs = $added{$cardnumber};
            foreach my $attr ( keys %$attribs ) {
                $attribs->{$attr} =~ s/\s*$// if ( $attribs->{$attr} );
            }
            $attribs->{categorycode} = $category;
            my $mandatory_fields = C4::Context->preference("BorrowerMandatoryField");
            my @check_fields = split( /\|/, $mandatory_fields );
            # Mandatory Fields
            foreach ( 'surname', 'address', 'city', @check_fields ) {
                unless ( exists $attribs->{ $_ } && defined $attribs->{ $_ } ) {
                    $attribs->{ $_ } = '';
                }
            }

            if ( $confirmed ) {
                # store handles dateexpiry, dateenrolled, and password
                my $patron = eval { Koha::Patron->new(\%$attribs)->store };
                if ( $@ ) {
                    $debug && warn "Patron creation failed! - $@";

                    push @report, {
                        name => $attribs->{surname} .', '. $attribs->{firstname},
                        cardnumber => $cardnumber,
                        error => 1,
                        create_error => 1,
                    };
                    next;
                }
                else {
                    if (C4::Context->preference('EnhancedMessagingPreferences')) {
                        unless ( $no_msg_branches->{$attribs->{'branchcode'}} ) {
                            C4::Members::Messaging::SetMessagingPreferencesFromDefaults({ borrowernumber => $patron->borrowernumber, categorycode => $category });
                        }
                    }
		}
            }

            push @report, {
                name => $attribs->{surname} .', '. $attribs->{firstname},
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
        @fields = @{ $get->fetchall_arrayref({}) };
        $get->finish;

        if ( $#fields > 1 ) {
            # To many rows returned
            push @report, {
                name => $existing{$cardnumber}{'surname'} .', '. $existing{$cardnumber}{'firstname'},
                cardnumber => $cardnumber,
                duplicate => 1,
            };
        }
        else {
            my $values = $fields[0];
            my @changes;
            my $patron = Koha::Patrons->find($values->{'borrowernumber'});

            foreach ( keys %$attribs ) {
                defined $attribs->{ $_ } &&
                    $attribs->{ $_ } &&
                    $attribs->{ $_ } =~ s/\s*$//;
            }
            # Don't change categorycode on existing patrons!
            if ( $attribs->{ categorycode } ) {
                delete $attribs->{ categorycode };
            }

            foreach ( sort keys %$values ) {
                if ( exists $attribs->{ $_ } && defined $attribs->{ $_ } ) {
                    if ( $_ eq 'password' ) {
                        if ( $attribs->{ $_ } ne $values->{ $_ } && $confirmed ) {
                            $patron->set_password({ password => $attribs->{'password'}, skip_validation => 1 });
                        }
                        delete $attribs->{ 'password' };
                    }
                    elsif ( defined $values->{ $_ } ) {
                        if ( $attribs->{ $_ } ne $values->{ $_ } ) {
                            $diff = 1;
                            push @changes, { field => $_, old => $values->{$_}, new => $attribs->{$_} };
                        }
                    } else {
                        $diff = 1;
                        push @changes, { field => $_, old => '', new => $attribs->{$_} };
                    }
                } elsif ( exists $attribs->{ $_ } ) {  # value is undefined.  Delete
                    delete $attribs->{ $_ };
                }
            }

            if ( ! $attribs->{'gonenoaddress'} && $values->{'gonenoaddress'} ) {
                $attribs->{'gonenoaddress'} = 0;
                $diff = 1;
                push @changes, { field => 'gonenoaddress', old => 'set', new => 'cleared' };
            }

            if ( $diff ) {
                if ( $confirmed ) {
                    $patron->set( $attribs )->store;
                    #warn "Updated $attribs->{cardnumber}";
                    if ( $attribs->{'branchcode'} && C4::Context->preference('EnhancedMessagingPreferences') ) {
                        if ( $no_msg_branches->{$values->{'branchcode'}} && ! $no_msg_branches->{$attribs->{'branchcode'}} ) {
                            C4::Members::Messaging::SetMessagingPreferencesFromDefaults({ borrowernumber => $values->{'borrowernumber'}, categorycode => $category });
                        }
                        elsif ( $no_msg_branches->{$attribs->{'branchcode'}} ) {
                            $clear_msg_prefs_sth->execute($values->{'borrowernumber'});
                        }
                    }
                }

                push @report, {
                    name => $attribs->{surname} .', '. $attribs->{firstname},
                    cardnumber => $cardnumber,
                    changed => \@changes,
                };
                $numchanged++;
            }
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
    #my $branches = GetBranchesLoop();

    my @categoryloop;
    foreach my $cat ( @categories ) {
        my $category = Koha::Patron::Categories->find( $cat );
        push @categoryloop, {
            categorycode => $cat,
            categoryname => $category->description,
        };
    }
    @categoryloop = sort { $a->{categoryname} cmp $b->{categoryname} } @categoryloop;

    $template->param(
        'branchloop' => $branches,
        'categoryloop' => \@categoryloop,
    );
}

#writing the template
output_html_with_http_headers $cgi, $cookie, $template->output;
