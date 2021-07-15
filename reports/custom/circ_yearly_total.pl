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
    report_file => 'circ_yearly_total',
    report_title => 'Yearly circulation totals',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my @parameters = (
);

my @column_titles = ( "School Year", "Item Type", "Circulations" );

my $query = "";
my @query_params;
my @columns = ( 'all_issues.issuedate', 'itemtypes.description' );
my $order = "all_issues.issuedate";
my $group = "";

my @filters;
my ( $page_breaks, $break_index, $subtotal_index ) = ( 1, 0, undef );

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

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'items.homebranch', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }
    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;

    $query = "SELECT ". (join ',',@columns) ." FROM (";
    $query .= "SELECT issuedate, itype FROM issues LEFT JOIN items USING (itemnumber) ";
    $query .= 'WHERE '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);
    $query .= " UNION ALL SELECT issuedate, itype FROM old_issues LEFT JOIN items USING (itemnumber) ";
    $query .= 'WHERE '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);
    $query .= ") AS all_issues LEFT JOIN itemtypes ON itype = itemtype ";

    $query .= "GROUP BY $group " if ($group);
    $query .= "ORDER BY $order" if ($order);
    push @query_params, @query_params;
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
    my %data;

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my $year;
	    # FIXME this needs to be updated every year.
	    for ( $values[0] ) {
            if    ( $_ gt '2022-05-26' ) { $year = '2022-2023' }
            elsif ( $_ gt '2021-05-26' ) { $year = '2021-2022' }
            elsif ( $_ gt '2020-05-21' ) { $year = '2020-2021' }
            elsif ( $_ gt '2019-05-23' ) { $year = '2019-2020' }
            elsif ( $_ gt '2018-05-24' ) { $year = '2018-2019' }
            elsif ( $_ gt '2017-05-24' ) { $year = '2017-2018' }
            elsif ( $_ gt '2016-05-25' ) { $year = '2016-2017' }
            elsif ( $_ gt '2015-05-21' ) { $year = '2015-2016' }
            elsif ( $_ gt '2014-05-22' ) { $year = '2014-2015' }
            elsif ( $_ gt '2013-05-23' ) { $year = '2013-2014' }
            elsif ( $_ gt '2012-05-23' ) { $year = '2012-2013' }
            elsif ( $_ gt '2011-05-25' ) { $year = '2011-2012' }
            elsif ( $_ gt '2010-05-27' ) { $year = '2010-2011' }
            elsif ( $_ gt '2009-05-22' ) { $year = '2009-2010' }
	    }
	    if ( $year ) {
            $data{ $year }{ $values[1] }++;
            $data{ $year }{ '_total' }++;
	    }
    }
    foreach my $year ( sort { $b cmp $a } keys %data ) {
        my $year_hash = $data{$year};
        $break = undef;
        foreach my $type ( sort keys %$year_hash ) {
            my @results = (
                { value => $year },
                { value => $type },
                { value => $year_hash->{ $type } },
            ) unless ( $type eq '_total' );

            if ( $page_breaks && $type eq '_total' ) {
                push @{$inner->{'footer'}}, [
                    { value => 'Total', colspan => 2 },
                    { value => $year_hash->{ $type } },
                ];
                push @outer, $inner;
                $inner = {results=>[],footer=>[]};
                $inner->{break} = 1;
            }
            else {
                push @{$inner->{'results'}}, \@results;
            }
        }
    }

    #push @outer, $inner;
    return \@outer;
}
