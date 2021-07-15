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
use Koha::List::Patron qw( GetPatronLists );

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
    report_file => 'circ_issued',
    report_title => 'Checked out copies',
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

my @patron_lists = GetPatronLists();

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
        crit => 'borrowers.sort2',
        op => '=',
        select_box => 1,
        select_loop => $sort2_loop,
        first_blank => 1,
    },
    {
        input_id => 'cr_plist',
        input_name => 'plist',
        label => 'Patron list',
        op => '=',
        select_box => 1,
        first_blank => 1,
        select_loop => [ map +{ value => $_->patron_list_id, label => $_->name }, @patron_lists ],
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
        input_id => 'cr_after',
        input_name => 'after',
        label => 'Due after',
        crit => 'date_due',
        op => '>=',
        calendar => 1,
        to_id => 'cr_before',
    },
    {
        input_id => 'cr_before',
        input_name => 'before',
        label => 'Due Before',
        crit => 'date_due',
        op => '<',
        calendar => 1,
    },
    {
        input_id => 'cr_perpage',
        input_name => 'per_page',
        label => 'Seperate patrons results',
        first_blank => 1,
        blank_label => 'No paging',
        radio_group => 1,
        radio_loop => [{value=>'sort2',label=>'Class per page'},{value=>'patron_list_id',label=>'List per page'},{value=>'borrowernumber',label=>'Patron per page'}],
    },
    {
        input_id => 'cr_order',
        input_name => 'order',
        label => 'Sort By',
        select_box => 1,
        select_loop => [
            { value => 'datedue',  label => 'Due Date' },
            { value => 'borrower', label => 'Last Name' },
            { value => 'sort2',    label => 'Teacher' },
            { value => 'itype',    label => 'Item type' },
        ],
    },
);

my @column_titles = ( "Homeroom Teacher", "Date Due", "Borrower", "Borrowers School", "Title", "Call Number", "Barcode", "Replacement Price", "Copy notes" );

my $query = "";
my @query_params;
my @columns = ( "borrowers.sort2", "issues.date_due", "CONCAT( borrowers.surname, ', ', borrowers.firstname ) AS borrower", "branches.branchname", "CONCAT_WS(' ',biblio.title,biblio.subtitle) AS title", "items.itemcallnumber", "items.barcode", "COALESCE(items.replacementprice,0)", "items.itemnotes", "borrowers.borrowernumber" );
my $where = "";
my $order = "sort2,borrower";
my $group = "";

my @filters;
my ( $page_breaks, $break_index, $subtotal_index, $use_patron_lists );

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

    for ( scalar $input->param("order") ) {
        if    ( $_ eq 'datedue' )  { $order = 'date_due ASC,sort2,borrower' }
        elsif ( $_ eq 'borrower' ) { $order = 'borrower,date_due,title' }
        elsif ( $_ eq 'itype' )    { $order = 'items.itype,title,sort2,borrower' }
        elsif ( $_ eq 'sort2' )    { $order = 'sort2,borrower' }
    }

    if ( my $per_page = $input->param("per_page") ) {
        $page_breaks = 1;
        $break_index = 2;
        if ( $per_page eq 'sort2' ) {
            $break_index = 0;
            $order = 'sort2,borrower';
        }
        elsif ( $per_page eq 'patron_list_id' ) {
            $break_index = -1;
            $order = 'patron_list.name,borrower';
        }
        elsif ( $per_page eq 'borrowernumber' ) {
            $break_index = 2;
            $order = 'borrower,date_due,title';
        }
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'items.homebranch', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }

    if ( ( my $list_id = $input->param('plist') ) || ( $input->param("per_page") eq 'patron_list_id' ) ) {
        $use_patron_lists = 1;
        unshift @columns,'COALESCE(patron_lists.name,"")';
        unshift @column_titles,'Patron list';
        if ( $page_breaks ) { $break_index++; }
        if ( $list_id ) {
            my @lists = grep { $_->patron_list_id eq $list_id } @patron_lists;
            my $list_name = ( @lists ? $lists[0]->name : $list_id );

            push @filters, { crit => 'patron_list_id', op => '=', filter => $dbh->quote($list_id), label => 'Patron List', value => $list_name };
        }

        $query = "SELECT ". (join ',',@columns) ." FROM issues CROSS JOIN borrowers USING (borrowernumber) LEFT JOIN patron_list_patrons USING (borrowernumber) LEFT JOIN patron_lists USING (patron_list_id) CROSS JOIN items USING (itemnumber) CROSS JOIN biblio USING (biblionumber) CROSS JOIN biblioitems USING (biblioitemnumber) CROSS JOIN branches ON borrowers.branchcode = branches.branchcode ";
    }
    else {
        $query = "SELECT ". (join ',',@columns) ." FROM issues CROSS JOIN borrowers USING (borrowernumber) CROSS JOIN items USING (itemnumber) CROSS JOIN biblio USING (biblionumber) CROSS JOIN biblioitems USING (biblioitemnumber) CROSS JOIN branches ON borrowers.branchcode = branches.branchcode ";
    }

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query .= 'WHERE '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= "GROUP BY $group " if ($group);
    $query .= "ORDER BY $order" if ($order);
}

$template->param(
    'parameters' => \@parameters,
    'filters' => \@filters,
    'headers' => [ map +{ title => $_ }, @column_titles ],
);

if ( $do_it ) {
    my $results = calculate( $query, \@query_params, scalar @column_titles, $page_breaks, $break_index, $subtotal_index, $use_patron_lists );
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
    my ( $query, $params, $num_columns, $page_breaks, $break_index, $subtotal_index, $use_patron_lists ) = @_;
    my ( @outer, $inner, $total, $subtotal, $break, $subtotal_break );
    my $dbh = C4::Context->dbh;
    $inner = {results=>[],footer=>[]};
    my $a_offset = ( $use_patron_lists ? 1 : 0 );

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my @results = map +{ value => $_ }, @values[0..$num_columns-1];
        $results[7+$a_offset]->{value} = sprintf( "%.2f", $values[7+$a_offset] );
        $results[2+$a_offset]->{link} = "/cgi-bin/koha/members/moremember.pl?borrowernumber=$values[9+$a_offset]";
        $results[1+$a_offset]->{'is_date'} = 1;

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
                value => $total,
            }
        ]
    }

    push @outer, $inner;
    return \@outer;
}
