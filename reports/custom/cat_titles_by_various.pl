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
    report_file => 'cat_titles_by_various',
    report_title => 'Titles by various criteria',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my @parameters = (
    {
        input_id => 'cr_itemcall',
        input_name => 'item_call',
        label => 'Call number',
        op => 'LIKE',
        input_box => 1,
    },
    {
        input_id => 'cr_lexile_from',
        input_name => 'lexile_from',
        label => 'Lexile From',
        op => 'BETWEEN',
        input_box => 1,
    },
    {
        input_id => 'cr_lexile_to',
        input_name => 'lexile_to',
        label => 'Lexile To',
        op => 'BETWEEN',
        input_box => 1,
    },
    {
        input_id => 'cr_awards',
        input_name => 'awards',
        label => 'Awards',
        op => 'LIKE',
        input_box => 1,
    },
    {
        input_id => 'cr_itemnote',
        input_name => 'item_note',
        label => 'Copy Notes',
        op => 'LIKE',
        input_box => 1,
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
        input_id => 'cr_shelfloc',
        input_name => 'shelf_loc',
        label => 'Shelving Locations',
        select_box => 1,
        select_loop => [ map +{ value => $_->authorised_value, label => $_->lib }, Koha::AuthorisedValues->search_with_library_limits({ category => 'LOC' },{order_by=>['lib']},(C4::Context->only_my_library ? C4::Context->userenv->{branch} : ''))->as_list ],
        first_blank => 1,
        multiple => 1,
    },
    {
        input_id => 'cr_onlyone',
        input_name => 'only_one',
        label => 'Only show one copy',
        check_box => 1,
    },
    {
        input_id => 'cr_order',
        input_name => 'order',
        label => 'Sort By',
        select_box => 1,
        select_loop => [
            { value => 'title',      label => 'Title' },
            { value => 'callnumber', label => 'Call number' },
        ],
    },
);

my @column_titles = ( "Title", "Author", "Series Title", "Volume", "Copyright", "Lexile", "Library", "Call Number", "Barcode", "Item Type", "Copy Notes", "Availability" );

my $query = "";
my @query_params;
my @columns = ( "CONCAT_WS(' ',b1.title,b1.subtitle) AS title", "b1.author",
            "b1.seriestitle", "biblioitems.volume", "b1.copyrightdate",
            'EXTRACTVALUE(biblio_metadata.metadata,\'//datafield[@tag="521" and @ind1="8"]/subfield[@code="a"]\')',
            "branches.branchname", "items.itemcallnumber", "items.barcode", "items.itype",
            "CONCAT_WS('\n',items.itemnotes,items.itemnotes_nonpublic) AS item_notes",
            "CASE WHEN COALESCE(items.withdrawn,0) <> 0 THEN 'Withdrawn' WHEN COALESCE(items.restricted,0) <> 0 THEN 'Restricted' WHEN COALESCE(items.itemlost,0) <> 0 THEN 'Lost' WHEN issues.issue_id IS NOT NULL THEN 'On loan' ELSE 'Available' END AS Availability",
            "items.itemnumber", "items.biblionumber" );
my $where = "";
my $order = "title";
my $group = "";

my @filters;
my ( $page_breaks, $break_index, $subtotal_index );

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

    if ( $input->param('item_note') ) {
        my $note = $input->param('item_note');
        push @filters, { crit => '( items.itemnotes LIKE ? OR items.itemnotes_nonpublic', op => 'LIKE', filter => '?)', label => 'Copy notes', value => $note };
        push @query_params, '%'. $note .'%', '%'. $note .'%';
    }

    if ( $input->param('item_call') ) {
        my $call = $input->param('item_call');
        push @filters, { crit => 'items.itemcallnumber', op => 'LIKE', filter => '?', label => 'Call number', value => $call };
        push @query_params, $call .'%';
    }

    if ( $input->param('lexile_from') || $input->param('lexile_to') ) {
        my $lexile_f = $input->param('lexile_from');
        my $lexile_t = $input->param('lexile_to');
        my $filter;
        if ( $lexile_f && $lexile_t ) {
            $filter = { crit => 'REGEXP_REPLACE(EXTRACTVALUE(biblio_metadata.metadata,\'//datafield[@tag="521" and @ind1="8"]/subfield[@code="a"]\'),"L$","")', op => 'BETWEEN', filter => $dbh->quote($lexile_f) .' AND '. $dbh->quote($lexile_t), label => 'Lexile', value => $lexile_f .' and '. $lexile_t };
            push @filters, $filter;
        }
        else {
            my $lexile = ($lexile_f ? $lexile_f : $lexile_t);
            $filter = { crit => 'EXTRACTVALUE(biblio_metadata.metadata,\'//datafield[@tag="521" and @ind1="8"]/subfield[@code="a"]\')', op => 'LIKE', filter => '?', label => 'Lexile', value => $lexile };
            push @filters, $filter;
            push @query_params, '%'. $lexile .'%';
        }
    }

    if ( $input->param('awards') ) {
        my $award = $input->param('awards');
        push @filters, { crit => 'EXTRACTVALUE(biblio_metadata.metadata,\'//datafield[@tag="586"]/subfield[@code="a"]\')', op => 'LIKE', filter => '?', label => 'Awards', value => $award };
        push @query_params, '%'. $award .'%';
    }

    if ( $input->param('shelf_locs') ) {
        my @locs = $input->multi_param('shelf_locs');
        push @filters, { crit => 'items.location', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @locs) .')', label => 'Shelving Locations', value => join ',',@locs };
    }

    if ( $input->param('itype') ) {
        my @itypes = $input->multi_param('itype');
        push @filters, { crit => 'items.itype', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @itypes) .')', label => 'Item Types', value => join ',',@itypes };
    }

    if ( $input->param('only_one') ) {
        $columns[5] = 'EXTRACTVALUE(ANY_VALUE(biblio_metadata.metadata),\'//datafield[@tag="521" and @ind1="8"]/subfield[@code="a"]\')';

        $columns[6] = 'GROUP_CONCAT(DISTINCT items.homebranch) AS branch';
        $columns[7] = 'GROUP_CONCAT(DISTINCT items.itemcallnumber) AS itemcallnumber';
        $columns[8] = 'GROUP_CONCAT(DISTINCT items.barcode) AS barcode';
        $columns[9] = 'GROUP_CONCAT(DISTINCT items.itype) AS itype';
        $columns[10] = 'CONCAT_WS("'."\n".'", GROUP_CONCAT(DISTINCT items.itemnotes), GROUP_CONCAT(DISTINCT itemnotes_nonpublic) ) AS item_notes';
        $columns[11] = 'CONCAT( COALESCE((SELECT COUNT(*) as num_avail FROM items CROSS JOIN biblio USING (biblionumber) LEFT JOIN issues USING (itemnumber) WHERE '. ($branch ? 'homebranch = '. $dbh->quote($branch) .' AND ' : '') .'COALESCE(items.withdrawn,0) = 0 AND COALESCE(items.restricted,0) = 0 AND COALESCE(items.itemlost,0) = 0 AND issues.itemnumber IS NULL AND biblio.biblionumber = b1.biblionumber GROUP BY biblio.biblionumber),0), " of ", count(itemnumber), " available") AS Availability';
        $columns[12] = 'MAX(items.itemnumber) AS itemnumber';
        $group = 'biblioitems.biblioitemnumber,b1.biblionumber';

        push @filters, { label => 'Show', op => 'only', value => 'one copy' };
    }

    for ( scalar $input->param("order") ) {
        if    ( $_ eq 'title' )      { $order = 'title' }
        elsif ( $_ eq 'callnumber' ) { $order = 'itemcallnumber,title' }
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'items.homebranch', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }

    $query = "SELECT ". (join ',',@columns) ." FROM items LEFT JOIN branches ON branches.branchcode = items.homebranch LEFT JOIN issues USING (itemnumber) CROSS JOIN biblio b1 USING (biblionumber) CROSS JOIN biblioitems USING (biblioitemnumber) LEFT JOIN biblio_metadata ON biblio_metadata.biblionumber = b1.biblionumber AND format = 'marcxml' ";

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query .= 'WHERE '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if ( @q_filters );

    $query .= "GROUP BY $group " if ($group);
    $query .= "ORDER BY $order" if ($order);
}

$template->param(
    'parameters' => \@parameters,
    'filters' => \@filters,
    'headers' => [ map +{ title => $_ }, @column_titles ],
);

if ( $do_it ) {
    my $results = calculate( $query, \@query_params, scalar @column_titles, $page_breaks, $break_index, $subtotal_index );
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
    my ( $query, $params, $num_columns, $page_breaks, $break_index, $subtotal_index ) = @_;
    my ( @outer, $inner, $total, $subtotal, $break, $subtotal_break );
    my $dbh = C4::Context->dbh;
    $inner = {results=>[],footer=>[]};

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my @results = map +{ value => $_ }, @values[0..$num_columns-1];
        $results[0]->{link} = "/cgi-bin/koha/catalogue/detail.pl?biblionumber=$values[13]";

        if ( defined $subtotal_index && ( ! defined $subtotal_break || $subtotal_break ne $results[$subtotal_index]->{value} ) ) {
            if ( defined $subtotal_break ) {
                push @{$inner->{ 'results' }}, [
                    {
                        colspan => $num_columns - 1,
                        value => 'Subtotal',
                    },
                    {
                        value => sprintf( "%.2f", $subtotal ),
                    }
                ];
                $subtotal = 0;
            }
            $subtotal_break = $results[$subtotal_index]->{value};
        }

        if ( $page_breaks && ( ! defined $break || $break ne $results[$break_index]->{value} ) ) {
            if ( defined $break ) {
                push @outer, $inner;
                $inner = {results=>[],footer=>[]};
                $inner->{break} = 1;
            }
            $break = $results[$break_index]->{value};
        }

        push @{$inner->{'results'}}, \@results;
        $total++;
    }

    if ( defined $subtotal_index && $inner->{'results'} && @{$inner->{'results'}} ) {
        push @{$inner->{ 'results' }}, [
            {
                colspan => $num_columns - 1,
                value => 'Subtotal',
            },
            {
                value => sprintf( "%.2f", $subtotal ),
            }
        ];
        $subtotal = 0;
    }

    if ( $total ) {
        if ( $page_breaks ) {
            push @outer, $inner;
            $inner = {break=>1,nodata=>1,results=>[],footer=>[]};
        }
        push @{$inner->{ $page_breaks ? 'results' : 'footer' }}, [
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
