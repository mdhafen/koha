package Koha::List::Patron;

# Copyright 2013 ByWater Solutions
#
# This file is part of Koha.
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
# along with Koha; if not, see <https://www.gnu.org/licenses>.

=head1 NAME

Koha::List::Patron - Management of lists of patrons

=head1 FUNCTIONS

=cut

use Modern::Perl;

use Carp qw( carp croak );

use Koha::Database;

our ( @ISA, @EXPORT_OK );

BEGIN {
    require Exporter;
    @ISA       = qw(Exporter);
    @EXPORT_OK = qw(
        get_patron_list
        get_patron_lists

        del_patron_list
        add_patron_list
        mod_patron_list

        add_patrons_to_list
        del_patrons_from_list

        grant_patrons_access_to_list
        revoke_patrons_access_from_list
    );
}

=head2 get_patron_list

    my $list = get_patron_list( { patron_list_id => 2 } );

    Returns the patron list with patron_list_id.
=cut

sub get_patron_list {
    my ($params) = @_;

    unless ( $params->{'patron_list_id'} ) {
        carp("No list id passed in or defined!");
        return;
    }

    my $schema = Koha::Database->new()->schema();

    my $patron_list = $schema->resultset('PatronList')->find($params->{'patron_list_id'});

    return $patron_list;
}

=head2 get_patron_lists

    my @lists = get_patron_lists( $params );

    Returns an array of lists created by the the given user
    or the logged in user if none is passed in.
=cut

sub get_patron_lists {
    my ($params) = @_;

    $params->{owner} ||= C4::Context->userenv->{'number'};
    my $user_branch = C4::Context->userenv->{'branch'};
    my $search_attrs = {};

    unless ( $params->{owner} ) {
        carp("No owner passed in or defined!");
        return;
    }

    delete $params->{owner} if C4::Context->IsSuperLibrarian();
    #  Avoid 'patron_list_id is ambiguous in where clause' due to joins
    if ( $params->{'patron_list_id'} && ! $params->{'me.patron_list_id'} ) {
        $params->{'me.patron_list_id'} = $params->{'patron_list_id'};
        delete $params->{'patron_list_id'};
    }

    if ( my $owner = $params->{owner} ) {
        delete $params->{owner};
        $params->{'-or'} = [
            owner  => $owner,
            shared => 1,
            '-and' => [
                shared => 2,
                branchcode => $user_branch,
            ],
            '-and' => [
                shared => { 'IN' => [2,3] },
                'patron_list_users.borrowernumber' => $owner,
            ],
        ];
        $search_attrs = {
            join => [ 'owner', 'patron_list_users' ],
            group_by => 'me.patron_list_id',
        };
    }

    my $schema = Koha::Database->new()->schema();

    my @patron_lists = $schema->resultset('PatronList')->search($params, $search_attrs);

    return wantarray() ? @patron_lists : \@patron_lists;
}

=head2 del_patron_list

    del_patron_list( { patron_list_id => $list_id [, owner => $owner ] } );

=cut

sub del_patron_list {
    my ($params) = @_;

    $params->{owner} ||= C4::Context->userenv->{'number'};

    unless ( $params->{patron_list_id} ) {
        croak("No patron list id passed in!");
    }
    unless ( $params->{owner} ) {
        carp("No owner passed in or defined!");
        return;
    }

    delete( $params->{owner} ) if ( C4::Context->IsSuperLibrarian() );

    return Koha::Database->new()->schema()->resultset('PatronList')->search($params)->single()->delete();
}

=head2 add_patron_list

    add_patron_list( { name => $name [, owner => $owner ] } );

=cut

sub add_patron_list {
    my ($params) = @_;

    $params->{owner} ||= C4::Context->userenv->{'number'};

    unless ( $params->{owner} ) {
        carp("No owner passed in or defined!");
        return;
    }

    unless ( $params->{name} ) {
        carp("No list name passed in!");
        return;
    }

    return Koha::Database->new()->schema()->resultset('PatronList')->create($params);
}

=head2 mod_patron_list

    mod_patron_list( { patron_list_id => $id, name => $name [, owner => $owner ] } );

=cut

sub mod_patron_list {
    my ($params) = @_;

    unless ( $params->{patron_list_id} ) {
        carp("No patron list id passed in!");
        return;
    }

    my $list = get_patron_list(
        {
            patron_list_id => $params->{patron_list_id},
        }
    );

    return $list->update($params);
}

=head2 add_patrons_to_list

    add_patrons_to_list({ list => $list, cardnumbers => \@cardnumbers });

=cut

sub add_patrons_to_list {
    my ($params) = @_;

    my $list            = $params->{list};
    my $cardnumbers     = $params->{'cardnumbers'};
    my $borrowernumbers = $params->{'borrowernumbers'};

    return unless ( $list && ( $cardnumbers || $borrowernumbers ) );

    my @borrowernumbers;

    my %search_param;
    if ($cardnumbers) {
        $search_param{cardnumber} = { 'IN' => $cardnumbers };
    } else {
        $search_param{borrowernumber} = { 'IN' => $borrowernumbers };
    }

    @borrowernumbers = Koha::Database->new()->schema()->resultset('Borrower')->search(
        \%search_param,
        { columns => [qw/ borrowernumber /] }
    )->get_column('borrowernumber')->all();

    my $patron_list_id = $list->patron_list_id();

    my $plp_rs = Koha::Database->new()->schema()->resultset('PatronListPatron');

    my @results;
    foreach my $borrowernumber (@borrowernumbers) {
        my $result = $plp_rs->update_or_create(
            {
                patron_list_id => $patron_list_id,
                borrowernumber => $borrowernumber
            }
        );
        push( @results, $result );
    }

    return wantarray() ? @results : \@results;
}

=head2 del_patrons_from_list

    del_patrons_from_list({ list => $list, patron_list_patrons => \@patron_list_patron_ids });

=cut

sub del_patrons_from_list {
    my ($params) = @_;

    my $list                = $params->{list};
    my $patron_list_patrons = $params->{patron_list_patrons};

    return unless ( $list && $patron_list_patrons );

    return Koha::Database->new()->schema()->resultset('PatronListPatron')
        ->search( { patron_list_patron_id => { 'IN' => $patron_list_patrons } } )->delete();
}

=head2 grant_patrons_access_to_list

    grant_patrons_access_to_list({ list => $list, cardnumbers => \@cardnumbers });

=cut

sub grant_patrons_access_to_list {
    my ($params) = @_;

    my $list            = $params->{list};
    my $cardnumbers     = $params->{'cardnumbers'};
    my $borrowernumbers = $params->{'borrowernumbers'};

    return unless ( $list && ( $cardnumbers || $borrowernumbers ) );

    my @borrowernumbers;

    my %search_param;
    if ($cardnumbers) {
        $search_param{cardnumber} = { 'IN' => $cardnumbers };
    } else {
        $search_param{borrowernumber} = { 'IN' => $borrowernumbers };
    }

    @borrowernumbers =
      Koha::Database->new()->schema()->resultset('Borrower')->search(
        \%search_param,
        { columns    => [qw/ borrowernumber /] }
      )->get_column('borrowernumber')->all();

    my $patron_list_id = $list->patron_list_id();

    my $plu_rs = Koha::Database->new()->schema()->resultset('PatronListUser');

    my @results;
    foreach my $borrowernumber (@borrowernumbers) {
        my $result = $plu_rs->update_or_create(
            {
                patron_list_id => $patron_list_id,
                borrowernumber => $borrowernumber
            }
        );
        push( @results, $result );
    }

    return wantarray() ? @results : \@results;
}

=head2 revoke_patrons_access_from_list

    revoke_patrons_access_from_list({ list => $list, patron_list_users => \@patron_list_user_ids });

=cut

sub revoke_patrons_access_from_list {
    my ($params) = @_;

    my $list              = $params->{list};
    my $patron_list_users = $params->{patron_list_users};

    return unless ( $list && $patron_list_users );

    return Koha::Database->new()->schema()->resultset('PatronListUser')
      ->search( { patron_list_user_id => { 'IN' => $patron_list_users } } )
      ->delete();
}

=head1 AUTHOR

Kyle M Hall, E<lt>kyle@bywatersolutions.comE<gt>

=cut

1;

__END__
