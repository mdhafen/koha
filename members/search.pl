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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;

use CGI qw ( -utf8 );
use C4::Context;
use C4::Auth qw( get_template_and_user );
use C4::Output qw( output_html_with_http_headers );
use Koha::Patron::Attribute::Types;
use List::MoreUtils qw( uniq );
use C4::Koha qw( GetAuthorisedValues );


my $input = CGI->new;

my ( $template, $loggedinuser, $cookie, $staff_flags ) = get_template_and_user(
    {   template_name   => "members/search.tt",
        query           => $input,
        type            => "intranet",
        flagsrequired   => { catalogue => '*' },
    }
);

my $referer = $input->referer();

my @columns = split ',', $input->param('columns');
my $callback = $input->param('callback');
my $selection_type = $input->param('selection_type') || 'select';
my $filter = $input->param('filter');
my @form_filters = split ',', $input->param('form_filters');
unless (@form_filters) { @form_filters = ('branch','category') };

my $sort_filter = { ( C4::Context->only_my_library ? (branchcode => C4::Context->userenv->{branch}) : () ) };
my ( @sort1, @sort2, $pat_search_rs );
if ( grep { $_ eq 'sort1' } @form_filters ) {
    @sort1 = map { $_->{lib} } @{ GetAuthorisedValues("Bsort1") };
    unless ( @sort1 ) {
        $pat_search_rs = Koha::Patrons->search($sort_filter);
        @sort1 = sort {$a cmp $b} uniq( $pat_search_rs->get_column('sort1') );
    }
}
if ( grep { $_ eq 'sort2' } @form_filters ) {
    @sort2 = map { $_->{lib} } @{ GetAuthorisedValues("Bsort2") };
    unless ( @sort2 ) {
        unless ($pat_search_rs) { $pat_search_rs = Koha::Patrons->search($sort_filter) };
        @sort2 = sort {$a cmp $b} uniq( $pat_search_rs->get_column('sort2') );
    }
}

$template->param(
    view           => ( $input->request_method() eq "GET" ) ? "show_form" : "show_results",
    callback       => $callback,
    columns        => \@columns,
    filter         => $filter,
    selection_type => $selection_type,
    patron_search_unfiltered => ($input->param('unfiltered') ? "1" : "" ),
    form_filters    => \@form_filters,
    sort1           => \@sort1,
    sort2           => \@sort2,
);
output_html_with_http_headers( $input, $cookie, $template->output );
