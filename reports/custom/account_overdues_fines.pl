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
    report_file => 'account_overdues_fines',
    report_title => 'Overdue copies and fines',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my ( $sort1_loop, $sort2_loop, $sth );
$sth = $dbh->prepare( 'SELECT DISTINCTROW sort1 AS value, sort1 AS label FROM borrowers WHERE sort1 IS NOT NULL AND sort1 <> "" '. ( $branch ? 'AND branchcode =  '. $dbh->quote($branch) : '' ) .'ORDER BY sort1' );
$sth->execute();
$sort1_loop = $sth->fetchall_arrayref({});

$sth = $dbh->prepare( 'SELECT DISTINCTROW sort2 AS value, sort2 AS label FROM borrowers WHERE sort2 IS NOT NULL AND sort2 <> "" '. ( $branch ? 'AND branchcode =  '. $dbh->quote($branch) : '' ) .'ORDER BY sort2' );
$sth->execute();
$sort2_loop = $sth->fetchall_arrayref({});

my @parameters = (
    {
        input_id => 'cr_sort1',
        input_name => 'sort1',
        label => 'Sort1',
        crit => 'borrowers.sort1',
        op => '=',
        select_box => 1,
        select_loop => $sort1_loop,
        first_blank => 1,
    },
    {
        input_id => 'cr_sort2',
        input_name => 'sort2',
        label => 'Sort2',
        crit => 'sort2',
        op => '=',
        select_box => 1,
        select_loop => $sort2_loop,
        first_blank => 1,
    },
    {
        input_id => 'cr_categories',
        input_name => 'categories',
        label => 'Patron Categories',
        crit => 'borrowers.categorycode',
        op => '=',
        select_box => 1,
        select_loop => [ map +{ value => $_->categorycode, label => $_->description }, Koha::Patron::Categories->search_with_library_limits ],
        first_blank => 1,
        multiple => 1,
    },
    {
        input_id => 'cr_card',
        input_name => 'card',
        label => 'Only show patrons with these Card numbers',
        input_box => 1,
    },
    {
        input_id => 'cr_checkedout',
        input_name => 'checked_out',
        label => 'Show All Checked Out Copies',
        check_box => 1,
    },
    {
        input_id => 'cr_notgone',
        input_name => 'not_gone',
        label => 'Exclude Students flagged as Gone',
        crit => 'COALESCE(borrowers.gonenoaddress,0)',
        op => '=',
        filter => '0',
        display => 'Not Gone',
        check_box => 1,
    },
    {
        input_id => 'cr_onlyyours',
        input_name => 'only_yours',
        label => 'Only Students at your school',
        check_box => 1,
    },
    {
        input_id => 'cr_concise',
        input_name => 'concise',
        label => 'Concise Check Out info',
        check_box => 1,
    },
    {
        input_id => 'cr_nosort2',
        input_name => 'no_sort2',
        label => 'Don\'t show Homeroom Teacher',
        check_box => 1,
    },
    {
        input_id => 'cr_perpage',
        input_name => 'per_page',
        label => 'Seperate patrons results',
        first_blank => 1,
        blank_label => 'No paging',
        radio_group => 1,
        radio_loop => [{value=>'sort2',label=>'Class per page'},{value=>'borrowernumber',label=>'Patron per page'}],
    },
);

my @column_titles = ( "Homeroom Teacher", "Card number", "Patron", "Description", "Amount Outstanding" );

my $query = "";
my @query_params;
my $order = "bsort, patron";

my @filters;
my ( $page_breaks, $break_index, $subtotal_index );
my $local_only = ( $input->param('only_yours') ? 1 : 0 );
my $concise = $input->param('concise');
my $no_sort2 = $input->param('no_sort2');

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

    if ( my $cards = $input->param('card') ) {
        my $s = join ',', map { $dbh->quote($_) } split /[\s,]+/, $cards;
        push @filters, { crit => 'borrowers.cardnumber', op => 'in', filter =>  "($s)", label => 'Cardnumbers', value => $cards };
    }

    if ( $input->param('checked_out') ) {
        push @filters, { label => 'All', crit => '', op => 'Checked', filter => '', value => 'Out' };
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => '( borrowers.branchcode = '. $dbh->quote($branch) . ( $local_only ? ' AND ' : ' OR ') .'items.homebranch', op => '=', filter => $dbh->quote($branch) ." )", label => 'Library', value => $branchname };
    }

    if ( $concise ) {
        splice @column_titles, 1, 1;
        if ($page_breaks) {
            $break_index--;
            $subtotal_index--;
        }
    }

    if ( $no_sort2 ) {
        splice @column_titles, 0, 1;
        $order = 'patron';
        if ($page_breaks) {
            $break_index--;
            $subtotal_index--;
        }
    }

    if ( my $per_page = $input->param("per_page") ) {
        $page_breaks = 1;
        $subtotal_index = 2;
        if ( $per_page eq 'sort2' ) {
            $break_index = 7;
            $order = "bsort,$order";
        }
        elsif ( $per_page eq 'borrowernumber' ) {
            $break_index = 6;
            $order = "patron,$order";
        }
    }

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query = "( SELECT ". ($no_sort2 ? '' : 'borrowers.sort2,') . ($concise ? '' : 'borrowers.cardnumber,') ." CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron, description, amountoutstanding, borrowers.cardnumber, borrowers.borrowernumber, borrowers.sort2 AS bsort FROM accountlines CROSS JOIN borrowers USING (borrowernumber) LEFT JOIN items USING (itemnumber) WHERE amountoutstanding <> 0";

    $query .= ' AND '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= " ) UNION ( SELECT ". ($no_sort2 ? '' : 'borrowers.sort2,') . ($concise ? '' : 'borrowers.cardnumber,') ." CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron, ". ($concise ? "CONCAT_WS( ' &nbsp; ', barcode, CONCAT_WS( ' ', biblio.title, biblio.subtitle ) )" : "CONCAT_WS( '<br>', CONCAT_WS( ' ', biblio.title, biblio.subtitle ), CONCAT( 'Due: ', date_due ), CONCAT( 'Barcode: ', barcode, ' (', branchname,') &nbsp; Call Number: ', COALESCE(itemcallnumber,'') ), CONCAT( '<b>Replacement Price: ', replacementprice, '</b>' ) )") ." AS description, ". ($concise? 'replacementprice' : 'NULL') .", borrowers.cardnumber, borrowers.borrowernumber, borrowers.sort2 AS bsort FROM issues CROSS JOIN borrowers USING (borrowernumber) CROSS JOIN items USING (itemnumber) CROSS JOIN biblio USING (biblionumber) CROSS JOIN branches on homebranch = branches.branchcode WHERE ". ($input->param('checked_out') ? "0 = 0" : "date_due < CURRENT_DATE()" );

    $query .= ' AND '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= " ) ";

    $query .= "ORDER BY $order" if ($order);

    push @query_params, @query_params;  # The where is doubled, so double this
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
        $results[$num_columns-1]->{value} = sprintf( "%.2f", $results[$num_columns-1]->{value} ) if ($results[$num_columns-1]->{value});
        $results[$num_columns-3]->{link} = "/cgi-bin/koha/members/moremember.pl?borrowernumber=".$values[$num_columns+1];

        if ( defined $subtotal_index && ( ! defined $subtotal_break || $subtotal_break ne $values[$subtotal_index] ) ) {
            if ( defined $subtotal_break ) {
                push @{$inner->{ $page_breaks ? 'results' : 'footer' }}, [
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
            $subtotal_break = $values[$subtotal_index];
        }

        if ( $page_breaks && ( ! defined $break || $break ne $values[$break_index] ) ) {
            if ( defined $break ) {
                push @outer, $inner;
                $inner = {results=>[],footer=>[]};
                $inner->{break} = 1;
            }
            $break = $values[$break_index];
        }

        push @{$inner->{'results'}}, \@results;
        $total += $results[ $num_columns-1 ]->{value};
        $subtotal += $results[ $num_columns-1 ]->{value};
    }

    if ( defined $subtotal_index && $inner->{'results'} && @{$inner->{'results'}} ) {
        push @{$inner->{ $page_breaks ? 'results' : 'footer' }}, [
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
            $inner = {nobreak=>1,nodata=>1,results=>[]};
        }
        push @{$inner->{ $page_breaks ? 'results' : 'footer' }}, [
            {
                colspan => $num_columns - 1,
                value => 'Total',
            },
            {
                value => sprintf( "%.2f", $total ),
            }
        ]
    }

    push @outer, $inner;
    return \@outer;
}
