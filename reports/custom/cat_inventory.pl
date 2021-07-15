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
use C4::Circulation qw( LostItem );

my $input    = CGI->new;
my $dbh      = C4::Context->dbh;

my $do_it    = $input->param('do_it');
my $output   = $input->param("output");
my $basename = $input->param("basename");
my $sep      = $input->param("sep") || C4::Context->preference('CSVDelimiter');
$sep = "\t" if ( $sep =~ /^tab/ );

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
    report_file => 'cat_inventory',
    report_title => 'Catalog Inventory',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my @parameters = (
    {
        input_id => 'cr_lastseen',
        input_name => 'lastseen',
        label => 'Last seen before',
        value => dt_from_string(),
        crit => 'datelastseen',
        op => '<',
        calendar => 1,
    },
    {
        input_id => 'cr_itype',
        input_name => 'itype',
        label => 'Item Types',
        select_box => 1,
        select_loop => [ map +{ value => $_->itemtype, label => $_->translated_description }, Koha::ItemTypes->search_with_localization ],
        first_blank => 1,
        multiple => 1,
    },
    {
        input_id => 'cr_skipissued',
        input_name => 'skip_issued',
        label => 'Skip copies on loan',
        check_box => 1,
        checked => 1,
        crit => 'issues.date_due',
        op => 'IS',
        filter => 'NULL',
        display => 'Not on loan',
    },
    {
        input_id => 'cr_setmissing',
        input_name => 'set_missing',
        label => 'Set copies as Missing',
        check_box => 1,
    },
    {
        input_id => 'cr_note',
        input_name => 'note',
        label => 'With note',
        input_box => 1,
    },
    {
        input_id => 'cr_order',
        input_name => 'order',
        label => 'Sort By',
        select_box => 1,
        select_loop => [
            { value => 'lastseen',   label => 'Date Last Seen' },
            { value => 'title',      label => 'Title' },
            { value => 'callnumber', label => 'Call Number' },
        ],
    },
);

my @column_titles = ( "Last Seen", "Call Number", "Barcode", "Title", "Library" );

my $query = "";
my @query_params;
my @columns = ( "items.datelastseen", "items.itemcallnumber", "items.barcode", "CONCAT_WS(' ', biblio.title, biblio.subtitle) AS fulltitle", "items.homebranch", "items.biblionumber", "items.itemnumber" );
my $where = "itemlost = 0 AND withdrawn = 0";
my $order = "datelastseen";

my @filters;
my ( $set_lost, $lost_message );

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

    for ( scalar $input->param("order") ) {
        if    ( $_ eq 'title' )      { $order = 'fulltitle' }
        elsif ( $_ eq 'callnumber' ) { $order = 'itemcallnumber' }
    }

    if ( $input->param('itype') ) {
        my @itypes = $input->multi_param('itype');
        push @filters, { crit => 'items.itype', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @itypes) .')', label => 'Item Types', value => join ',',@itypes };
    }

    if ( $input->param('set_missing') ) {
        $set_lost = 4;  # missing
        $lost_message = $input->param('note') || '';
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'items.homebranch', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }

    $query = "SELECT ". (join ',',@columns) ." FROM items CROSS JOIN biblio USING (biblionumber) CROSS JOIN biblioitems USING (biblioitemnumber) LEFT JOIN issues USING (itemnumber) WHERE $where ";

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query .= 'AND '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= "ORDER BY $order" if ($order);
}

$template->param(
    'parameters' => \@parameters,
    'filters' => \@filters,
    'headers' => [ map +{ title => $_ }, @column_titles ],
);

if ( $do_it ) {
    my $results = calculate( $query, \@query_params, scalar @column_titles, $set_lost, $lost_message );
    if ( $output eq 'file' ) {
        my $filename = "$basename.csv";
        $filename = "$basename.tsv" if ( $sep =~ m/^\t/ );
        my $csv = Text::CSV::Encoded->new({ encoding_out => 'UTF-8', sep_char => $sep });
        my $content = '';
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
    my ( $query, $params, $num_columns, $set_lost, $lost_message ) = @_;
    my ( @outer, $inner, $total );
    my $dbh = C4::Context->dbh;
    $inner = {results=>[],footer=>[]};

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my @results = map +{ value => $_ }, @values[0..$num_columns-1];
        $results[0]->{'is_date'} = 1;
        $results[2]->{link} = "/cgi-bin/koha/catalogue/moredetail.pl?biblionumber=$values[5]&itemnumber=$values[6]#item$values[6]";
        $results[3]->{link} = "/cgi-bin/koha/catalogue/detail.pl?biblionumber=$values[5]";

        if ( $set_lost ) {
            my $item = Koha::Items->find( $values[6] );
            if ( $item ) {
                my $item_hash = $item->unblessed;
                if ( $lost_message ) {
                    $item->itemnotes_nonpublic( $item_hash->{'itemnotes_nonpublic'} ."\n". $lost_message );
                }
                $item->itemlost( $set_lost );
                $item->store;
                LostItem($values[6], 'report_inventory', 1); # for fine/returned
            }
        }

        push @{$inner->{'results'}}, \@results;
        $total++;
    }

    if ( $total ) {
        push @{$inner->{ 'footer' }}, [
            {
                colspan => $num_columns - 1,
                value => 'Total',
            },
            {
                value => $total,
            }
        ]
    }

    push @outer, $inner;
    return \@outer;
}
