#!/usr/bin/perl

# This file is part of Koha.
#
# Copyright 2014 BibLibre
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

use Modern::Perl;

use CGI qw ( -utf8 );
use List::MoreUtils qw(uniq);
use C4::Auth qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );
use C4::Members;

use Koha::Patron::Categories;

my $input = CGI->new;

my $dbh = C4::Context->dbh;

my ( $template, $loggedinuser, $cookie, $staff_flags ) = get_template_and_user(
    {   template_name   => "common/patron_search.tt",
        query           => $input,
        type            => "intranet",
        flagsrequired   => { tools => 'label_creator' },
    }
);

my $q = $input->param('q') || '';
my $op = $input->param('op') || '';

my $referer = $input->referer();

my $patron_categories = Koha::Patron::Categories->search_with_library_limits;
my $sort_filter = { ( C4::Context->only_my_library ? (branchcode => C4::Context->userenv->{branch}) : () ) };
my @sort1 = sort {$a cmp $b} uniq( Koha::Patrons->search($sort_filter)->get_column('sort1') );
my @sort2 = sort {$a cmp $b} uniq( Koha::Patrons->search($sort_filter)->get_column('sort2') );
$template->param(
    view            => ( $input->request_method() eq "GET" ) ? "show_form" : "show_results",
    columns         => ['select', 'cardnumber', 'name', 'category', 'branch', 'dateexpiry', 'borrowernotes', 'action'],
    json_template   => 'patroncards/tables/members_results.tt',
    selection_type  => 'add',
    alphabet        => ( C4::Context->preference('alphabet') || join ' ', 'A' .. 'Z' ),
    categories      => $patron_categories,
    sort1           => \@sort1,
    sort2           => \@sort2,
    aaSorting       => 1,
);
output_html_with_http_headers( $input, $cookie, $template->output );
