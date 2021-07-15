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
    report_file => 'borrowers_by_status',
    report_title => 'List patrons by status',
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
        input_id => 'cr_categories',
        input_name => 'categories',
        label => 'Patron Categories',
        crit => 'borrowers.categorycode',
        op => '=',
        select_box => 1,
        select_loop => [ map +{ value => $_->categorycode, label => $_->description }, Koha::Patron::Categories->search_with_library_limits->as_list ],
        first_blank => 1,
    },
    {
        input_id => 'cr_gone',
        input_name => 'gone',
        label => 'Students flagged as Gone',
        crit => 'COALESCE(borrowers.gonenoaddress,0)',
        op => '=',
        filter => '1',
        display => 'Gone',
        check_box => 1,
    },
    {
        input_id => 'cr_lost',
        input_name => 'lost',
        label => 'Students flagged as having lost their library card',
        crit => 'COALESCE(borrowers.lost,0)',
        op => '=',
        filter => '1',
        display => 'Lost card',
        check_box => 1,
    },
    {
        input_id => 'cr_debarred',
        input_name => 'debarred',
        label => 'Students flagged as debarred',
        crit => 'COALESCE(borrowers.debarred,0)',
        op => '=',
        filter => '1',
        display => 'Debarred',
        check_box => 1,
    },
    {
        input_id => 'cr_order',
        input_name => 'order',
        label => 'Sort By',
        select_box => 1,
        select_loop => [
            { value => 'lastname',   label => 'Last Name' },
            { value => 'cardnumber', label => 'Card number' },
            { value => 'sort2',      label => 'Homeroom Teacher' },
            { value => 'patron_list_id', label => 'Patron list' },
        ],
    },
);

my @column_titles = ( "Patron", "Cardnumber", "Category", "Graduation Date", "Homeroom Teacher", "Gone", "Lost", "Debarred" );

my $query = "";
my @query_params;
my @columns = ( "CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron", "cardnumber", "description", "sort1", "sort2", "gonenoaddress", "lost", "debarred", "borrowernumber" );
my $order = "patron";

my $using_patron_list = 0;
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

    for ( scalar $input->param("order") ) {
        if    ( $_ eq 'sort2' )   { $order = 'sort2,patron' }
        elsif ( $_ eq 'patron_list_id' ) { $order = 'patron_lists.name,patron' }
        elsif ( $_ eq 'cardnumber' ) { $order = 'cardnumber' }
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'borrowers.branchcode', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }

    if ( ( my $list_id = $input->param('plist') ) || $input->param("order") eq 'patron_list_id' ) {
        $using_patron_list = 1;
        unshift @columns, 'COALESCE(patron_lists.name,"")';
        unshift @column_titles,'Patron list';

        if ( $list_id ) {
            my @lists = grep { $_->patron_list_id eq $list_id } @patron_lists;
            my $list_name = ( @lists ? $lists[0]->name : $list_id );
            push @filters, { crit => 'patron_list_id', op => '=', filter => $dbh->quote($list_id), label => 'Patron list', value => $list_name };
        }

        $query =
    "SELECT ". (join',',@columns) ."
       FROM borrowers
  LEFT JOIN patron_list_patrons USING (borrowernumber)
  LEFT JOIN patron_lists USING (patron_list_id)
 CROSS JOIN categories using (categorycode) ";
    }
    else {
        $query =
    "SELECT ". (join',',@columns) ."
       FROM borrowers
 CROSS JOIN categories using (categorycode) ";
    }

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query .= 'WHERE '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= "ORDER BY $order" if ($order);
}

$template->param(
    'parameters' => \@parameters,
    'filters' => \@filters,
    'headers' => [ map +{ title => $_ }, @column_titles ],
);

if ( $do_it ) {
    my $results = calculate( $query, \@query_params, scalar @column_titles, $using_patron_list );
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
    my ( $query, $params, $num_columns, $using_patron_list ) = @_;
    my ( @outer, $inner );
    my $dbh = C4::Context->dbh;
    $inner = {results=>[],footer=>[]};
    my $r_offset = ( $using_patron_list ? 1 : 0 );

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my @results = map +{ value => $_ }, @values[0..$num_columns-1];

        $results[0+$r_offset]->{link} = "/cgi-bin/koha/members/moremember.pl?borrowernumber=$values[8+$r_offset]";
        $results[5+$r_offset]->{value} = ( $values[5+$r_offset] ? "Gone" : "" );
        $results[6+$r_offset]->{value} = ( $values[6+$r_offset] ? "Card Lost" : "" );
        $results[7+$r_offset]->{value} = ( $values[7+$r_offset] ? "Debarred" : "" );

        push @{$inner->{'results'}}, \@results;
    }

    push @outer, $inner;
    return \@outer;
}
