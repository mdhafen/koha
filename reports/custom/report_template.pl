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
    report_file => 'FIXME',
    report_title => 'FIXME',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

# FIXME sort1_loop, sort2_loop
my ( $sort1_loop, $sort2_loop, $sth );
$sth = $dbh->prepare( 'SELECT DISTINCTROW sort1 AS value, sort1 AS label FROM borrowers WHERE sort1 IS NOT NULL AND sort1 <> "" '. ( $branch ? 'AND branchcode =  '. $dbh->quote($branch) : '' ) .'ORDER BY sort1' );
$sth->execute();
$sort1_loop = $sth->fetchall_arrayref({});

$sth = $dbh->prepare( 'SELECT DISTINCTROW sort2 AS value, sort2 AS label FROM borrowers WHERE sort2 IS NOT NULL AND sort2 <> "" '. ( $branch ? 'AND branchcode =  '. $dbh->quote($branch) : '' ) .'ORDER BY sort2' );
$sth->execute();
$sort2_loop = $sth->fetchall_arrayref({});

# FIXME these are mostly for example
my @parameters = (
    {
        input_id => 'cr_sort2',
        input_name => 'sort2',
        label => 'Sort2',
        crit => 'borrowers.sort2',
        op => '=',
        select_box => 1,
        select_loop => $sort2_loop,
        first_blank => 1,
    },
    {
        input_id => 'cr_amount',
        input_name => 'amount',
        label => 'Fines/Credits greater than $',
        input_box => 1,
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
        input_id => 'cr_categories',
        input_name => 'categories',
        label => 'Patron Categories',
        op => 'IN',
        select_box => 1,
        select_loop => [ map +{ value => $_->categorycode, label => $_->description }, Koha::Patron::Categories->search_with_library_limits ],
        first_blank => 1,
        multiple => 1,
    },
    {
        input_id => 'cr_before',
        input_name => 'before',
        label => 'Before',
        crit => 'timestamp',
        op => '<',
        calendar => 1,
        value => dt_from_string(),
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
        input_id => 'cr_perpage',
        input_name => 'per_page',
        label => 'Seperate patrons results',
        first_blank => 1,
        blank_label => 'No paging',
        radio_group => 1,
        radio_loop => [{value=>'sort2',label=>'Class per page'},{value=>'borrowernumber',label=>'Patron per page'}],
    },
    {
        input_id => 'cr_order',
        input_name => 'order',
        label => 'Sort By',
        select_box => 1,
        select_loop => [
            { value => 'sort2',      label => 'Homeroom' },
            { value => 'lastname',   label => 'Last Name' },
            { value => 'cardnumber', label => 'Card number' },
        ],
    },
);

my @column_titles = ( "FIXME" );

my $query = "";
my @query_params;
my @columns = ( "FIXME" );
my $where = "1 <> 0";  # FIXME an example
my $order = "sort2, patron";  # FIXME hard coded value
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

    # FIXME these are examples
    if ( $input->param('categories') ) {
        my @cats = $input->multi_param('categories');
        push @filters, { crit => 'borrowers.categorycode', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @cats) .')', label => 'Patron Categories', value => join ',',@cats };
    }

    if ( $input->param('itype') ) {
        my @itypes = $input->multi_param('itype');
        push @filters, { crit => 'items.itype', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @itypes) .')', label => 'Item Types', value => join ',',@itypes };
    }

    if ( $input->param('amount') ) {
        my $amount = $input->param('amount') + 0; # force to number
        $subtotal_index = undef;
        $columns[5] = 'SUM(accountlines.amountoutstanding)';
        splice @columns,2,3;
        splice @column_titles,2,3;
        push @filters, { crit => '', op => '>=', filter => '', label => 'Fine/Credit', value => $amount };
        $group = "borrowernumber HAVING SUM(amountoutstanding) >= $amount";
        $group .= " OR SUM(amountoutstanding) <= -$amount";
    }

    for ( scalar $input->param("order") ) {
        # FIXME hard coded values
        if    ( $_ eq 'lastname' )   { $order = 'patron' }
        elsif ( $_ eq 'cardnumber' ) { $order = 'cardnumber' }
    }

    if ( my $per_page = $input->param("per_page") ) {
        $page_breaks = 1;
        # FIXME hard coded values
        $break_index = 0;
        $subtotal_index = 1;
        if ( $per_page eq 'sort2' ) {
            $break_index = 0;
            $order = "sort2,$order";
        }
        elsif ( $per_page eq 'borrowernumber' ) {
            $break_index = 6;
            $order = "borrowernumber,$order";
        }
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'items.homebranch', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }

    # FIXME this is an example
    $query = "SELECT ". (join ',',@columns) ." FROM accountlines CROSS JOIN borrowers USING (borrowernumber) LEFT JOIN items USING (itemnumber) LEFT JOIN biblio USING (biblionumber) WHERE $where ";

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
        # FIXME some examples
        $results[$num_columns-1]->{value} = sprintf( "%.2f", $results[$num_columns-1]->{value} );
        $results[0]->{link} = "/cgi-bin/koha/members/moremember.pl?borrowernumber=$values[8]";
        $results[3]->{'is_date','with_hours'} = (1,1);

        if ( defined $subtotal_index && ( ! defined $subtotal_break || $subtotal_break ne $results[$subtotal_index]->{value} ) ) {
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
            $subtotal_break = $results[$subtotal_index]->{value};
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

    # FIXME comment this out if you don't want a 'total' footer
    if ( $total ) {
        if ( $page_breaks ) {
            push @outer, $inner;
            $inner = {break=>1,nodata=>1,results=>[]};
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
