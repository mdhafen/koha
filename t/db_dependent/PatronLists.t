#!/usr/bin/perl

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

use Modern::Perl;

use Test::NoWarnings;
use Test::More tests => 17;
use t::lib::TestBuilder;
use t::lib::Mocks;

use Koha::Database;
use Koha::List::Patron
    qw( add_patron_list add_patrons_to_list del_patron_list del_patrons_from_list get_patron_list get_patron_lists mod_patron_list grant_patrons_access_to_list revoke_patrons_access_from_list );
use Koha::Patrons;

my $schema = Koha::Database->schema;
$schema->storage->txn_begin;

my $builder = t::lib::TestBuilder->new;
my $branchcode   = $builder->build( { source => 'Branch' } )->{branchcode};

t::lib::Mocks::mock_userenv({branchcode => $branchcode});

# Create 10 sample borrowers
my @borrowers = ();
foreach ( 1 .. 10 ) {
    push @borrowers, $builder->build( { source => 'Borrower' } );
}

my $owner  = $borrowers[0]->{borrowernumber};
my $owner2 = $borrowers[1]->{borrowernumber};
my $owner3 = Koha::Patron->new(
    {
        surname      => 'Test 1',
        branchcode   => $branchcode,
        categorycode => $borrowers[0]->{categorycode}
    }
);
$owner3->store();

my @lists               = get_patron_lists( { owner => $owner } );
my $list_count_original = @lists;

my $list1 = add_patron_list( { name => 'Test List 1', owner => $owner } );
is( $list1->name(), 'Test List 1', 'add_patron_list works' );

my $list2 = add_patron_list( { name => 'Test List 2', owner => $owner } );

mod_patron_list(
    {
        patron_list_id => $list2->patron_list_id(),
        name           => 'Test List 3',
        owner          => $owner
    }
);
$list2->discard_changes();
is( $list2->name(), 'Test List 3', 'mod_patron_list works' );

$list1 =
    get_patron_list( { patron_list_id => $list1->patron_list_id() } );
is( $list1->name(), 'Test List 1', 'get_patron_list works' );

add_patrons_to_list( { list => $list1, cardnumbers => [ map { $_->{cardnumber} } @borrowers ] } );
is(
    scalar @borrowers,
    $list1->patron_list_patrons()->search_related('borrowernumber')->all(),
    'AddPatronsToList works for cardnumbers'
);

add_patrons_to_list(
    {
        list            => $list2,
        borrowernumbers => [ map { $_->{borrowernumber} } @borrowers ]
    }
);
is(
    scalar @borrowers,
    $list2->patron_list_patrons()->search_related('borrowernumber')->all(),
    'add_patrons_to_list works for borrowernumbers'
);

my $deleted_patron = $builder->build_object( { class => 'Koha::Patrons' } );
$deleted_patron->delete;
my @result = add_patrons_to_list( { list => $list2, borrowernumbers => [ $deleted_patron->borrowernumber ] } );
is( scalar @result, 0, 'Invalid borrowernumber not added' );
@result = add_patrons_to_list( { list => $list2, cardnumbers => [ $deleted_patron->cardnumber ] } );
is( scalar @result, 0, 'Invalid cardnumber not added' );

my @ids =
    $list1->patron_list_patrons()->get_column('patron_list_patron_id')->all();
del_patrons_from_list(
    {
        list                => $list1,
        patron_list_patrons => \@ids,
    }
);
$list1->discard_changes();
is( $list1->patron_list_patrons()->count(), 0, 'del_patrons_from_list works.' );

my $patron = $builder->build_object( { class => 'Koha::Patrons' } );
add_patrons_to_list( { list => $list2, borrowernumbers => [ $patron->borrowernumber ] } );
@lists = $patron->get_lists_with_patron;
is( scalar @lists, 1, 'get_lists_with_patron works' );

@lists = get_patron_lists( { owner => $owner } );
is( scalar @lists, $list_count_original + 2, 'get_patron_lists works' );

my $list3 = add_patron_list( { name => 'Test List 3', owner => $owner2, shared => 0 } );
@lists = get_patron_lists( { owner => $owner } );
is( scalar @lists, $list_count_original + 2, 'get_patron_lists does not return non-shared list' );

my $list4 = add_patron_list( { name => 'Test List 4', owner => $owner2, shared => 1 } );
@lists = get_patron_lists( { owner => $owner } );
is( scalar @lists, $list_count_original + 3, 'get_patron_lists does return shared list' );

del_patron_list( { patron_list_id => $list1->patron_list_id(), owner => $owner } );
del_patron_list( { patron_list_id => $list2->patron_list_id(), owner => $owner } );

$list1 =
    get_patron_list( { patron_list_id => $list1->patron_list_id() } );
is( $list1, undef, 'del_patron_list works' );

@lists = get_patron_lists();
my $lib_list_count = @lists;
my $list5 = add_patron_list( { name => 'Test List 5', owner => $owner3->borrowernumber, shared => 2 } );
my $list6 = add_patron_list( { name => 'Test List 6', owner => $owner3->borrowernumber, shared => 3 } );
@lists = get_patron_lists();
is( scalar @lists, $lib_list_count + 1, 'get_patron_lists returns list shared with library' );

grant_patrons_access_to_list( { list => $list6, borrowernumbers => [ $patron->borrowernumber ] } );

@lists = get_patron_lists({ owner => $patron->borrowernumber });
is( scalar @lists, $lib_list_count + 2, 'get_patron_lists returns list shared with individual, grant_patrons_access_to_list works' );

my @list_users = $list6->patron_list_users->get_column('patron_list_user_id')->all();
revoke_patrons_access_from_list({ list => $list6, patron_list_users => \@list_users });
@lists = get_patron_lists();
is( scalar @lists, $lib_list_count + 1, 'revoke_patrons_access_from_list works' );

$schema->storage->txn_rollback;

