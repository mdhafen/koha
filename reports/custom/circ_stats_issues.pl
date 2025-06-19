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
use Koha::AuthorisedValues;

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
    report_file => 'circ_stats_issues',
    report_title => 'Titles with check out information',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my @parameters = (
    {
        input_id => 'cr_from',
        input_name => 'from',
        label => 'From',
        loop => 'inner',
        #crit => 'issuedate',
        op => '>',
        calendar => 1,
        to_id => 'cr_to',
        value => ,
    },
    {
        input_id => 'cr_to',
        input_name => 'to',
        label => 'To',
        loop => 'inner',
        #crit => 'issuedate',
        op => '<',
        calendar => 1,
        value => ,
    },
    {
        input_id => 'cr_itype',
        input_name => 'itype',
        label => 'Item Types',
        loop => 'inner',
        select_box => 1,
        select_loop => [ map +{ value => $_->itemtype, label => $_->translated_description }, Koha::ItemTypes->search_with_localization->as_list ],
        first_blank => 1,
        multiple => 1,
    },
    {   input_id => 'cr_location',
        input_name => 'location',
        label => 'Shelving location',
        loop => 'inner',
        select_box => 1,
        select_loop => [ map +{ value => $_->authorised_value, label => $_->lib }, Koha::AuthorisedValues->search_with_library_limits({ category => 'LOC' },{order_by=>['lib']},(C4::Context->only_my_library ? C4::Context->userenv->{branch} : ''))->as_list ],
        first_blank => 1,
        multiple => 1,
    },
    {
        input_id => 'cr_order',
        input_name => 'order',
        label => 'Sort By',
        select_box => 1,
        select_loop => [
            { value => 'fulltitle',   label => 'Title' },
            { value => 'callnumbers', label => 'Call Number' },
            { value => 'shelf_locs',  label => 'Shelving Location' },
            { value => 'checkouts',   label => 'Check outs' },
        ],
    },
);

my @column_titles = ( "Title", "Author", "Copyright Date", "Copies", "Shelving locations", "Call Numbers", "Check outs", "Most recent checkout" );

my $query = "";
my ( @filters, @query_params );
my ( @u_filters, @u_params );
my @columns = ( "concat_ws(' ',title,subtitle) as fulltitle", "author", "coalesce(copyrightdate,'') as copyright", "count(items_w_check.itemnumber) as copies", "group_concat(distinct coalesce(av_loc.lib,location,'') order by coalesce(av_loc.lib,location,'')) as locations", "group_concat(distinct itemcallnumber order by itemcallnumber) as callnumbers", "sum(items_w_check.checkouts) as checkouts", "max(max_issue_date) as most_recent", "items_w_check.biblionumber" );
my $where = "";
my $order = "fulltitle";
my $group = "biblio.biblionumber";

my ( $page_breaks, $break_index, $subtotal_index );

if ( $do_it ) {
    if ( my $val = $input->param('from') ) {
        $val = eval { output_pref({ dt => dt_from_string($val), dateonly => 1, dateformat => 'iso' }); };
        push @u_filters, { crit => 'issuedate', op => '>', filter => '?' };
        push @u_params, $val;
        push @filters, { label => 'From', op => '>', value => $val, loop => 'inner' };
    }

    if ( my $val = $input->param('to') ) {
        $val = eval { output_pref({ dt => dt_from_string($val), dateonly => 1, dateformat => 'iso' }); };
        push @u_filters, { crit => 'issuedate', op => '<', filter => '?' };
        push @u_params, $val;
        push @filters, { label => 'To', op => '<', value => $val, loop => 'inner' };
    }

    foreach my $param ( @parameters ) {
        next unless ( $param->{crit} );

        my $val = $input->param( $param->{input_name} );
        if ( defined $val && ( $val || $val eq '0' ) ) {
            if ( $param->{calendar} ) {
                $val = eval { output_pref({ dt => dt_from_string($val), dateonly => 1, dateformat => 'iso' }); }
            }
            my $set = { crit => $param->{crit}, op => $param->{op}, filter => '?', label => $param->{label}, value => $val, loop => $param->{loop} };
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
        push @filters, { loop => 'inner', crit => 'items.itype', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @itypes) .')', label => 'Item Types', value => join ',',@itypes };
    }

    for ( scalar $input->param("order") ) {
        if    ( $_ eq 'fulltitle' )   { $order = 'fulltitle' }
        elsif ( $_ eq 'callnumbers' ) { $order = 'callnumbers,fulltitle' }
        elsif ( $_ eq 'shelf_locs' )  { $order = 'locations,fulltitle' }
        elsif ( $_ eq 'checkouts' )   { $order = 'checkouts,fulltitle' }
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'homebranch', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname, loop => 'inner' };
    }

    my @q_filters_i = grep { $_->{crit} && defined $_->{filter} && ( $_->{loop} eq 'inner' || $_->{loop} eq 'both' ) } @filters;
    $query = "SELECT ". (join ',',@columns) ."
 FROM biblio
 LEFT JOIN ( SELECT items.*,count(issue_id) as checkouts,max(issuedate) as max_issue_date FROM items left join (select * from issues union all select * from old_issues ) as all_issues using (itemnumber) ";
        $query .= ( ' WHERE '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters_i ) .' ' ) if (@q_filters_i);
        $query .= " group by itemnumber ) as items_w_check USING (biblionumber)
 LEFT JOIN authorised_values as av_loc on authorised_value = items_w_check.location and av_loc.category = 'LOC' ";

    my @q_filters = grep { $_->{crit} && defined $_->{filter} && $_->{loop} ne 'inner' } @filters;
    $query .= ' WHERE items_w_check.homebranch IS NOT NULL ';
    $query .= ' AND '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

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
        $results[0]->{link} = "/cgi-bin/koha/catalogue/detail.pl?biblionumber=$values[8]";

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
                value => sprintf( "%.2f", $total ),
            }
        ]
    }

    push @outer, $inner;
    return \@outer;
}
