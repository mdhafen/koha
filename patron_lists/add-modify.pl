#!/usr/bin/perl

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

use Modern::Perl;

use CGI qw ( -utf8 );

use C4::Auth           qw( get_template_and_user );
use C4::Output         qw( output_html_with_http_headers );
use Koha::List::Patron qw( get_patron_list add_patron_list mod_patron_list grant_patrons_access_to_list revoke_patrons_access_from_list );

my $cgi = CGI->new;
my $op  = $cgi->param('op') // q{};

my ( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => "patron_lists/add-modify.tt",
        query         => $cgi,
        type          => "intranet",
        flagsrequired => { tools => 'manage_patron_lists' },
    }
);

my $id          = $cgi->param('patron_list_id');
my $name        = $cgi->param('name');
my $shared      = $cgi->param('shared');
my @grant_user  = $cgi->multi_param('grant_borrowernumber');
my @revoke_user = $cgi->multi_param('revoke_list_users_id');

if ($id) {
    my $list = get_patron_list( { 'patron_list_id' => $id } );
    $template->param( list => $list );
}

if ( $op eq 'cud-add_modify' && $name ) {
    my $list;
    if ($id) {
        mod_patron_list( { patron_list_id => $id, name => $name, shared => $shared } );
        print $cgi->redirect('lists.pl');
    } else {
        my $list = add_patron_list( { name => $name, shared => $shared } );
        print $cgi->redirect( "list.pl?patron_list_id=" . $list->patron_list_id() );
    }

    $template->param( list => $list );
}

if (@grant_user) {
    my $list = get_patron_list( { 'patron_list_id' => $id } );
    my $results = grant_patrons_access_to_list({
        list => $list,
        borrowernumbers => \@grant_user,
    });
    print $cgi->redirect("add-modify.pl?patron_list_id=" . $list->patron_list_id() );
    exit;
}

if (@revoke_user) {
    my $list = get_patron_list( { 'patron_list_id' => $id } );
    my $results = revoke_patrons_access_from_list({
        list => $list,
        patron_list_users => \@revoke_user,
    });
    print $cgi->redirect("add-modify.pl?patron_list_id=" . $list->patron_list_id() );
    exit;
}

output_html_with_http_headers( $cgi, $cookie, $template->output );
