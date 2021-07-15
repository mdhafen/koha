#!/usr/bin/perl
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
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use CGI;

use C4::Auth qw( get_template_and_user );
use C4::Context;
use C4::Koha;
use C4::Output qw( output_html_with_http_headers );
use C4::Reports qw( GetDelimiterChoices );
use DateTime;
use Koha::DateUtils qw( dt_from_string output_pref );
use Text::CSV::Encoded;

use Koha::Libraries;
use Koha::ItemTypes;
use Koha::Patron::Categories;
use Koha::AuthorisedValues;

my $input    = CGI->new;
my $dbh      = C4::Context->dbh;

my $do_it    = $input->param('do_it');
my $output   = $input->param("output");
my $basename = $input->param("basename");
my $sep      = $input->param("sep") || C4::Context->preference('CSVDelimiter');
$sep = "\t" if ( $sep =~ /^tab/ );

my @itemlost_values = Koha::AuthorisedValues->get_descriptions_by_koha_field({kohafield => 'items.itemlost'});
my @withdrawn_values = Koha::AuthorisedValues->get_descriptions_by_koha_field({kohafield => 'items.withdrawn'});
my @damaged_values = Koha::AuthorisedValues->get_descriptions_by_koha_field({kohafield => 'items.damaged'});

my $template_file = ( $do_it ? "results" : "params" );
my ($template, $borrowernumber, $cookie) = get_template_and_user({
    template_name => "reports/custom/$template_file.tt",
    query => $input,
    type => "intranet",
    flagsrequired => {reports => '*'},
});

my $branch = $input->param('branch');
$branch = ( C4::Context->only_my_library('IndependentBranchesHideOtherBranchesItems') ? C4::Context->userenv->{branch} : $branch );

$template->param(
    report_file => 'cat_lost',
    report_title => 'Copies by status',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my @parameters = (
    {
        input_id => 'cr_seensince',
        input_name => 'seen_since',
        label => 'Last seen before',
        crit => 'datelastseen',
        op => '<',
        calendar => 1,
        value => dt_from_string(),
    },
    {
        input_id => 'cr_itemlost',
        input_name => 'itemlost',
        label => 'Lost status',
        select_box => 1,
        select_loop => [
            { value => '', label => '' },
            { value => '_ANY_', label => 'Any setting' },
            map { { value => $_->{authorised_value}, label => $_->{lib} } } @itemlost_values[1..$#itemlost_values]
        ],
    },
    {
        input_id => 'cr_withdrawn',
        input_name => 'withdrawn',
        label => 'Withdrawn status',
        select_box => 1,
        select_loop => [
            { value => '', label => '' },
            { value => '_ANY_', label => 'Any setting' },
            map { { value => $_->{authorised_value}, label => $_->{lib} } } @withdrawn_values[1..$#withdrawn_values]
        ],
    },
    {
        input_id => 'cr_damaged',
        input_name => 'damaged',
        label => 'Damaged status',
        select_box => 1,
        select_loop => [
            { value => '', label => '' },
            { value => '_ANY_', label => 'Any setting' },
            map { { value => $_->{authorised_value}, label => $_->{lib} } } @damaged_values[1..$#damaged_values]
        ],
    },
    {
        input_id => 'cr_itype',
        input_name => 'itype',
        label => 'Item Types',
        select_box => 1,
        select_loop => [ map +{ value => $_->itemtype, label => $_->translated_description }, Koha::ItemTypes->search_with_localization->as_list ],
        first_blank => 1,
        multiple => 1,
    },
    {
        input_id => 'cr_order',
        input_name => 'order',
        label => 'Sort By',
        select_box => 1,
        select_loop => [
            { value => 'title',      label => 'Title' },
            { value => 'callnumber', label => 'Call Number' },
            { value => 'lastseen',   label => 'Last Seen' },
        ],
    },
);

my @column_titles = ( "Title", "Barcode", "Call Number", "Lost", "Lost On", "Damaged", "Damaged On", "Withdrawn", "Withdrawn On", "Date Last Seen", "Last Borrower" );

my $query = "";
my @query_params;
my @columns = ( "CONCAT_WS(' ', biblio.title, biblio.subtitle ) AS title", "barcode", "itemcallnumber", "IF(itemlost,av1.lib,'') AS itemlost", "items.itemlost_on", "IF(damaged,av2.lib,'') AS damaged", "items.damaged_on", "IF(withdrawn,'Withdrawn','') AS withdrawn", "items.withdrawn_on", "datelastseen", "itemnumber", "biblionumber" );
my $where = '( items.itemlost <> 0 OR items.withdrawn <> 0 OR items.damaged <> 0 )';
my $order = "title";
my $group = "";

my @filters;

if ( $do_it ) {
    foreach my $param ( @parameters ) {
        next unless ( $param->{crit} );

        my $val = $input->param( $param->{input_name} );
        if ( defined $val && ( $val || $val eq '0' ) ) {
            if ( $param->{calendar} ) {
                $val = eval { output_pref({ dt => dt_from_string($val), dateonly => 1, dateformat => 'iso' }); }
            }
            my $set = { crit => $param->{crit}, op => $param->{op}, filter => '?', label => $param->{label}, value => $val };
            unless ( defined $param->{filter} ) {
                push @query_params, $val;
            }
            else {
                $set->{filter} = $param->{filter};
                $set->{value} = $param->{display};
            }

            push @filters, $set;
        }
    }

    if ( $input->param('itype') ) {
        my @itypes = $input->multi_param('itype');
        push @filters, { crit => 'items.itype', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @itypes) .')', label => 'Item Types', value => join ',',@itypes };
    }

    for ( scalar $input->param("itemlost") ) {
        if    ( $_ eq '_ANY_' ) { push @filters, { crit => 'items.itemlost', op => '!=', filter => '0', label => 'Lost status', value => 'available' }; }
        elsif ( $_ )            { push @filters, { crit => 'items.itemlost', op => '=', filter =>  $dbh->quote($_), label => 'Lost status', value => $_ }; }
    }

    for ( scalar $input->param("withdrawn") ) {
        if    ( $_ eq '_ANY_' ) { push @filters, { crit => 'items.withdrawn', op => '!=', filter => '0', label => 'Withdrawn status', value => 'available' }; }
        elsif ( $_ )            { push @filters, { crit => 'items.withdrawn', op => '=', filter =>  $dbh->quote($_), label => 'Withdrawn status', value => $_ }; }
    }

    for ( scalar $input->param("damaged") ) {
        if    ( $_ eq '_ANY_' ) { push @filters, { crit => 'items.damaged', op => '!=', filter => '0', label => 'Damaged status', value => 'available' }; }
        elsif ( $_ )            { push @filters, { crit => 'items.damaged', op => '=', filter =>  $dbh->quote($_), label => 'Damaged status', value => $_ }; }
    }

    for ( scalar $input->param("order") ) {
        if    ( $_ eq 'callnumber' )   { $order = 'itemcallnumber,title' }
        elsif ( $_ eq 'lastseen' ) { $order = 'datelastseen' }
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'items.homebranch', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }

    $query = "SELECT ". (join ',',@columns) ." FROM items CROSS JOIN biblio USING (biblionumber) CROSS JOIN biblioitems USING (biblionumber) LEFT JOIN authorised_values AS av1 ON av1.authorised_value = itemlost AND av1.category = 'LOST' LEFT JOIN authorised_values AS av2 ON av2.authorised_value = damaged AND av2.category = 'DAMAGED' WHERE $where ";

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query .= 'AND '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= "GROUP BY $group " if ($group);
    $query .= "ORDER BY $order" if ($order);
}

$template->param(
    'parameters' => \@parameters,
    'filters' => \@filters,
    'headers' => [ map +{ title => $_ }, @column_titles ],
);

if ( $do_it ) {
    my $results = calculate( $query, \@query_params, scalar @column_titles );
    if ( $output eq 'file' ) {
        my $filename = "$basename.csv";
        $filename = "$basename.tsv" if ( $sep =~ m/^\t/ );
        my $csv = Text::CSV::Encoded->new({ encoding_out => 'UTF-8', sep_char => $sep });
        my $content = '';
        #  Add UTF-8 BOM (Byte Order Mark) for MS Excel
        $content .= "\xEF\xBB\xBF";
        $csv->combine(@column_titles);
        $content .= $csv->string() ."\n";
        for my $table ( @$results ) {
            for my $row ( @{ $table->{results} } ) {
                my @out;
                for my $column ( @$row ) {
                    if ( $column->{colspan} ) {
                        push @out, '' for ( 1..($column->{colspan} - 1) );
                    }
                    push @out, $column->{value};
                }
                $csv->combine(@out);
                $content .= $csv->string() ."\n";
            }
            if ( $table->{footer} ) {
                my @out;
                for my $row ( @{ $table->{footer} } ) {
                    for my $column ( @$row ) {
                        if ( $column->{colspan} ) {
                            push @out, '' for ( 1..($column->{colspan} - 1) );
                        }
                        push @out, $column->{value};
                    }
                }
                $csv->combine(@out);
                $content .= $csv->string() ."\n";
            }
        }
        print $input->header(
            -type => 'application/vnd.sun.xml.calc',
            -encoding => 'utf-8',
            -attachment=>"$filename",
            -filename=>"$filename",
        );
        print $content;
    }
    else {
        $template->param(breakingloop => $results);
        output_html_with_http_headers $input, $cookie, $template->output;
    }
}
else {
    # show the parameters form
    output_html_with_http_headers $input, $cookie, $template->output;
}

sub calculate {
    my ( $query, $params, $num_columns ) = @_;
    my ( @outer, $inner );
    my $dbh = C4::Context->dbh;
    $inner = {results=>[],footer=>[]};

    my $sth_last = $dbh->prepare( "( SELECT CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS borrower, borrowernumber, timestamp FROM issues CROSS JOIN borrowers USING (borrowernumber) WHERE issues.itemnumber = ? ) UNION ( SELECT CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS borrower, borrowernumber, timestamp FROM old_issues CROSS JOIN borrowers USING (borrowernumber) WHERE old_issues.itemnumber = ? ) ORDER BY timestamp DESC LIMIT 1" );

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my @results = map +{ value => $_ }, @values[0..$num_columns-1];
        $results[1]->{link} = "/cgi-bin/koha/catalogue/moredetail.pl?biblionumber=$values[11]&itemnumber=$values[10]#item$values[10]";
        map { $_->{'is_date'} = 1 } @results[4,6,8,9];
#        map { $_->{'with_hours'} = 1 } @results[4,6,8,9];
        map { $_->{'order_by'} = $_->{'value'} } @results[4,6,8,9];

        $sth_last->execute( $values[10], $values[10] );
        my ( $last, $bor_num ) = $sth_last->fetchrow;
        if ( $last ) {
            $results[10] = {
                value => $last,
                link => "/cgi-bin/koha/members/moremember.pl?borrowernumber=$bor_num",
            }
        }
        else {
            $results[10] = {
                value => '',
            }
        }

        push @{$inner->{'results'}}, \@results;
    }

    push @outer, $inner;
    return \@outer;
}
